// ============================================================================
// AWAtv — TMDB proxy
// ----------------------------------------------------------------------------
// Forwards authenticated requests to The Movie Database API while keeping the
// TMDB API key server-side. Premium users get richer metadata via this path;
// it also lets us layer caching and rate-limit insulation.
//
// Path mapping
//   POST /tmdb-proxy/<tmdb_path>?<query>       →  GET https://api.themoviedb.org/3/<tmdb_path>?<query>&api_key=<server_key>
//   GET  /tmdb-proxy/search/movie?query=..    →  GET https://api.themoviedb.org/3/search/movie?query=..&api_key=...
//
// Caching
//   Responses to GET requests are cached for 24h in a Supabase storage bucket
//   ("tmdb-cache"). Cache key = sha256(method + path + sorted query). The
//   bucket can be configured public or private; this function reads/writes
//   it with the service role.
//
//   Cache misses fall through to TMDB; cache hits return immediately with
//   a "x-cache: HIT" header for diagnostics.
//
// Auth
//   verify_jwt = true in config.toml — Supabase Functions Gateway rejects
//   unauthenticated calls before they reach this code.
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { handlePreflight, corsHeaders, jsonResponse } from "../_shared/cors.ts";

const TMDB_BASE = "https://api.themoviedb.org/3";
const CACHE_BUCKET = "tmdb-cache";
const CACHE_TTL_SECONDS = 24 * 60 * 60;

// Allowlist of TMDB endpoint roots we expose — keeps the proxy from being
// turned into an open relay. Extend as the app needs more endpoints.
const ALLOWED_PREFIXES = [
  "search/",
  "movie/",
  "tv/",
  "configuration",
  "genre/",
  "trending/",
  "discover/",
  "person/",
];

function pathIsAllowed(path: string): boolean {
  return ALLOWED_PREFIXES.some((p) => path === p || path.startsWith(p));
}

async function sha256(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const buf = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function buildCacheKey(method: string, path: string, qs: string): Promise<string> {
  // Sort query params so identical requests with different ordering hit the
  // same cache entry.
  const sorted = qs
    .split("&")
    .filter(Boolean)
    .sort()
    .join("&");
  return sha256(`${method.toUpperCase()}|/${path}|${sorted}`);
}

interface CacheEnvelope {
  status: number;
  headers: Record<string, string>;
  body: string;
  cachedAt: number;
}

Deno.serve(async (req) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;

  if (req.method !== "GET" && req.method !== "POST") {
    return jsonResponse(req, { error: "method_not_allowed" }, 405);
  }

  const url = new URL(req.url);
  // Path arrives like "/tmdb-proxy/search/movie". Strip the function prefix.
  const fnPrefix = "/tmdb-proxy/";
  const idx = url.pathname.indexOf(fnPrefix);
  if (idx === -1) {
    return jsonResponse(req, { error: "bad_path" }, 400);
  }
  const tmdbPath = url.pathname.slice(idx + fnPrefix.length).replace(/^\/+/, "");
  if (!tmdbPath || !pathIsAllowed(tmdbPath)) {
    return jsonResponse(req, { error: "forbidden_path" }, 403);
  }

  const tmdbKey = Deno.env.get("TMDB_API_KEY");
  if (!tmdbKey) {
    console.error("TMDB_API_KEY missing in env.");
    return jsonResponse(req, { error: "server_misconfigured" }, 500);
  }

  // Compose the upstream URL. We strip any incoming api_key to prevent
  // clients from masquerading the secret.
  const upstreamParams = new URLSearchParams(url.search);
  upstreamParams.delete("api_key");
  upstreamParams.append("api_key", tmdbKey);
  const upstreamUrl = `${TMDB_BASE}/${tmdbPath}?${upstreamParams.toString()}`;

  const cacheKey = await buildCacheKey(req.method, tmdbPath, url.searchParams.toString());

  // ----- Cache lookup (only for GET — POSTs are reserved for mutating calls
  // we don't currently use, but kept open in the path mapping above).
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  let sb: ReturnType<typeof createClient> | null = null;
  if (supabaseUrl && serviceKey) {
    sb = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  }

  if (req.method === "GET" && sb) {
    const { data, error } = await sb.storage.from(CACHE_BUCKET).download(`${cacheKey}.json`);
    if (!error && data) {
      try {
        const text = await data.text();
        const env: CacheEnvelope = JSON.parse(text);
        const age = (Date.now() - env.cachedAt) / 1000;
        if (age < CACHE_TTL_SECONDS) {
          return new Response(env.body, {
            status: env.status,
            headers: {
              ...corsHeaders(req),
              ...env.headers,
              "x-cache": "HIT",
              "x-cache-age": Math.floor(age).toString(),
            },
          });
        }
      } catch {
        // Corrupted entry; fall through and refresh.
      }
    }
  }

  // ----- Upstream call.
  const upstream = await fetch(upstreamUrl, {
    method: req.method,
    headers: {
      accept: "application/json",
      "user-agent": "AWAtv/1.0 (Supabase Edge Function)",
    },
    body: req.method === "POST" ? await req.text() : undefined,
  });

  const body = await upstream.text();
  const responseHeaders: Record<string, string> = {
    "content-type": upstream.headers.get("content-type") ?? "application/json; charset=utf-8",
    "x-cache": "MISS",
  };

  // ----- Cache write (only on 200 GET responses).
  if (
    req.method === "GET" &&
    upstream.status === 200 &&
    sb &&
    body.length < 1_000_000 // 1 MB safety belt; TMDB responses are typically <100 kB.
  ) {
    const envelope: CacheEnvelope = {
      status: upstream.status,
      headers: { "content-type": responseHeaders["content-type"] },
      body,
      cachedAt: Date.now(),
    };
    // Best-effort write — never block the response on cache failure.
    sb.storage
      .from(CACHE_BUCKET)
      .upload(`${cacheKey}.json`, JSON.stringify(envelope), {
        upsert: true,
        contentType: "application/json",
      })
      .then(({ error }) => {
        if (error) console.warn("tmdb-cache write failed:", error.message);
      });
  }

  return new Response(body, {
    status: upstream.status,
    headers: { ...corsHeaders(req), ...responseHeaders },
  });
});
