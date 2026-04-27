// ============================================================================
// AWAtv — sync-snapshot
// ----------------------------------------------------------------------------
// Returns a unified hydration payload for the calling user:
//
//   {
//     "profile":          { user_id, display_name, avatar_url, locale, ... },
//     "subscription":     { plan, status, expires_at, ... } | null,
//     "premium_status":   "free" | "premium",
//     "playlist_sources": [ ... ],
//     "favorites":        [ ... ],
//     "watch_history":    [ ... ],
//     "device_sessions":  [ ... ],
//     "fetched_at":       "2026-04-27T12:34:56Z"
//   }
//
// Why an aggregator?
//   On app launch we want the smallest number of round trips so the user sees
//   their data fast, even on cold starts or flaky links. One function call
//   fans out to six small queries inside the Postgres VPC and returns a
//   single JSON blob. Each list is bounded so the payload stays predictable.
//
// Auth
//   verify_jwt = true in config.toml. The user's JWT is forwarded verbatim
//   so RLS narrows every query to that user automatically.
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { handlePreflight, jsonResponse } from "../_shared/cors.ts";

const FAVORITES_LIMIT = 500;
const HISTORY_LIMIT = 100;
const PLAYLISTS_LIMIT = 50;
const DEVICES_LIMIT = 20;

Deno.serve(async (req) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;

  if (req.method !== "GET" && req.method !== "POST") {
    return jsonResponse(req, { error: "method_not_allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !anonKey) {
    console.error("SUPABASE_URL / SUPABASE_ANON_KEY missing.");
    return jsonResponse(req, { error: "server_misconfigured" }, 500);
  }

  // Forward the caller's JWT so RLS applies normally — every query below
  // sees only the authenticated user's rows.
  const auth = req.headers.get("authorization") ?? "";
  if (!auth.toLowerCase().startsWith("bearer ")) {
    return jsonResponse(req, { error: "unauthenticated" }, 401);
  }

  const sb = createClient(supabaseUrl, anonKey, {
    global: { headers: { authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: userErr } = await sb.auth.getUser();
  if (userErr || !userData?.user) {
    return jsonResponse(req, { error: "invalid_token" }, 401);
  }
  const userId = userData.user.id;

  // Fan out — independent reads run concurrently.
  const [
    profileRes,
    subscriptionRes,
    premiumRes,
    playlistsRes,
    favoritesRes,
    historyRes,
    devicesRes,
  ] = await Promise.all([
    sb.from("profiles").select("*").eq("user_id", userId).maybeSingle(),
    sb.from("subscriptions").select("*").eq("user_id", userId).maybeSingle(),
    sb.rpc("get_premium_status", { p_user_id: userId }),
    sb
      .from("playlist_sources")
      .select("*")
      .eq("user_id", userId)
      .order("added_at", { ascending: false })
      .limit(PLAYLISTS_LIMIT),
    sb
      .from("favorites")
      .select("*")
      .eq("user_id", userId)
      .order("added_at", { ascending: false })
      .limit(FAVORITES_LIMIT),
    sb
      .from("watch_history")
      .select("*")
      .eq("user_id", userId)
      .order("watched_at", { ascending: false })
      .limit(HISTORY_LIMIT),
    sb
      .from("device_sessions")
      .select("*")
      .eq("user_id", userId)
      .order("last_seen_at", { ascending: false })
      .limit(DEVICES_LIMIT),
  ]);

  // First non-null error is reported; we don't abort the whole snapshot
  // because individual table failures shouldn't block the rest.
  const errors = [
    profileRes.error,
    subscriptionRes.error,
    playlistsRes.error,
    favoritesRes.error,
    historyRes.error,
    devicesRes.error,
  ].filter(Boolean);
  if (errors.length > 0) {
    console.warn("sync-snapshot partial failures:", errors.map((e) => e?.message));
  }

  const body = {
    profile: profileRes.data ?? null,
    subscription: subscriptionRes.data ?? null,
    premium_status: typeof premiumRes.data === "string" ? premiumRes.data : "free",
    playlist_sources: playlistsRes.data ?? [],
    favorites: favoritesRes.data ?? [],
    watch_history: historyRes.data ?? [],
    device_sessions: devicesRes.data ?? [],
    fetched_at: new Date().toISOString(),
  };

  return jsonResponse(req, body, 200);
});
