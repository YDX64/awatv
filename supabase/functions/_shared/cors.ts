// Shared CORS helper for AWAtv edge functions.
//
// All AWAtv edge functions are called from the Flutter mobile app (native
// HTTP client, not a browser) and from Supabase Studio (browser). Native
// clients ignore CORS headers, so the cost of being permissive is small.
//
// The ALLOWED_ORIGINS environment variable can tighten this in production
// (comma-separated list of origins). Default: "*".
//
// Usage:
//   import { corsHeaders, handlePreflight } from "../_shared/cors.ts";
//
//   const pre = handlePreflight(req);
//   if (pre) return pre;
//   ...
//   return new Response(JSON.stringify(body), {
//     status: 200,
//     headers: { ...corsHeaders(req), "content-type": "application/json" },
//   });

const ALLOWED_HEADERS = [
  "authorization",
  "content-type",
  "x-client-info",
  "apikey",
  "x-revenuecat-signature",
].join(", ");

const ALLOWED_METHODS = "GET, POST, PUT, PATCH, DELETE, OPTIONS";

function resolveOrigin(req: Request): string {
  const allowed = (Deno.env.get("ALLOWED_ORIGINS") ?? "*")
    .split(",")
    .map((o) => o.trim())
    .filter(Boolean);

  if (allowed.includes("*") || allowed.length === 0) {
    return "*";
  }

  const origin = req.headers.get("origin");
  if (origin && allowed.includes(origin)) {
    return origin;
  }
  // Fall back to the first explicit origin so credentials-bearing requests
  // still work; non-matching browsers will see a CORS failure (intentional).
  return allowed[0];
}

export function corsHeaders(req: Request): Record<string, string> {
  return {
    "access-control-allow-origin": resolveOrigin(req),
    "access-control-allow-methods": ALLOWED_METHODS,
    "access-control-allow-headers": ALLOWED_HEADERS,
    "access-control-max-age": "86400",
    "vary": "origin",
  };
}

/**
 * Returns a 204 preflight response if the request is an OPTIONS preflight,
 * else null. Call at the top of every edge function.
 */
export function handlePreflight(req: Request): Response | null {
  if (req.method !== "OPTIONS") return null;
  return new Response(null, {
    status: 204,
    headers: corsHeaders(req),
  });
}

/** JSON response helper that always carries CORS + content-type headers. */
export function jsonResponse(
  req: Request,
  body: unknown,
  status = 200,
  extraHeaders: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(req),
      "content-type": "application/json; charset=utf-8",
      ...extraHeaders,
    },
  });
}
