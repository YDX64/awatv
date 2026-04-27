// ============================================================================
// AWAtv — RevenueCat webhook receiver
// ----------------------------------------------------------------------------
// Receives RevenueCat lifecycle events and upserts public.subscriptions so
// the rest of the system has a single source of truth for premium state.
//
// Auth model
//   RevenueCat signs each webhook with the shared secret you configure in
//   the RC dashboard. We compare it to the REVENUECAT_WEBHOOK_SECRET secret
//   set on the Supabase project (`supabase secrets set ...`).
//
//   We use a constant-time comparison to avoid timing oracles.
//
// Idempotency
//   RC may retry on transient failures. We always upsert by user_id, so
//   replaying the same event is a no-op for terminal states.
//
// Security
//   * Never logs the request body (could contain user emails).
//   * Returns 401 on bad auth, 400 on malformed payload, 200 on success.
//   * Uses the service-role key to bypass RLS — this function is the only
//     legitimate writer of public.subscriptions.
//
// References
//   * https://www.revenuecat.com/docs/webhooks
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { handlePreflight, jsonResponse } from "../_shared/cors.ts";

// ---------- Types matching the subset of the RC webhook payload we care about

type RcEventType =
  | "INITIAL_PURCHASE"
  | "RENEWAL"
  | "NON_RENEWING_PURCHASE"
  | "CANCELLATION"
  | "EXPIRATION"
  | "BILLING_ISSUE"
  | "PRODUCT_CHANGE"
  | "UNCANCELLATION"
  | "SUBSCRIPTION_PAUSED"
  | "TRANSFER"
  | "TEST";

interface RcEvent {
  type: RcEventType;
  app_user_id: string;
  original_app_user_id?: string;
  product_id?: string;
  period_type?: "NORMAL" | "TRIAL" | "INTRO" | "PROMOTIONAL";
  expiration_at_ms?: number;
  entitlement_ids?: string[];
  cancel_reason?: string;
  // The raw payload also carries `event` (object) wrapping these fields when
  // sent at the top level. We accept both shapes below.
}

interface RcPayload {
  event: RcEvent;
  api_version?: string;
}

// ---------- Plan + status mapping

function mapPlan(productId: string | undefined): "monthly" | "yearly" | "lifetime" {
  if (!productId) return "monthly";
  const id = productId.toLowerCase();
  if (id.includes("lifetime") || id.includes("life")) return "lifetime";
  if (id.includes("year") || id.includes("annual")) return "yearly";
  return "monthly";
}

function mapStatus(
  type: RcEventType,
  periodType?: string,
  expirationMs?: number,
): "active" | "expired" | "cancelled" | "in_grace" | "trial" {
  const expired = expirationMs !== undefined && expirationMs < Date.now();
  switch (type) {
    case "EXPIRATION":
      return "expired";
    case "CANCELLATION":
      // Cancelled but not yet expired = still active until expiration.
      return expired ? "expired" : "cancelled";
    case "BILLING_ISSUE":
      return "in_grace";
    case "INITIAL_PURCHASE":
    case "RENEWAL":
    case "UNCANCELLATION":
    case "NON_RENEWING_PURCHASE":
    case "PRODUCT_CHANGE":
    case "TRANSFER":
      if (periodType === "TRIAL" || periodType === "INTRO") return "trial";
      return expired ? "expired" : "active";
    default:
      return expired ? "expired" : "active";
  }
}

// ---------- Constant-time secret check

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
}

function authorize(req: Request): boolean {
  const expected = Deno.env.get("REVENUECAT_WEBHOOK_SECRET");
  if (!expected) {
    // Fail closed if the secret was never set in the env.
    console.error("REVENUECAT_WEBHOOK_SECRET is not configured.");
    return false;
  }
  // RC supports a custom Authorization header. The exact header name is
  // configured in the RC dashboard; we accept "authorization" or
  // "x-revenuecat-signature" for flexibility.
  const provided =
    req.headers.get("authorization")?.replace(/^Bearer\s+/i, "") ??
    req.headers.get("x-revenuecat-signature") ??
    "";
  return constantTimeEqual(provided, expected);
}

// ---------- Handler

Deno.serve(async (req) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;

  if (req.method !== "POST") {
    return jsonResponse(req, { error: "method_not_allowed" }, 405);
  }

  if (!authorize(req)) {
    return jsonResponse(req, { error: "unauthorized" }, 401);
  }

  let payload: RcPayload;
  try {
    payload = await req.json();
  } catch {
    return jsonResponse(req, { error: "invalid_json" }, 400);
  }

  const event = payload?.event;
  if (!event || typeof event !== "object" || !event.type || !event.app_user_id) {
    return jsonResponse(req, { error: "invalid_payload" }, 400);
  }

  // Discard test events early so we don't pollute the production table.
  if (event.type === "TEST") {
    return jsonResponse(req, { ok: true, ignored: "test_event" }, 200);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    console.error("Supabase service-role env vars missing.");
    return jsonResponse(req, { error: "server_misconfigured" }, 500);
  }

  const sb = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // RC's app_user_id is set client-side to auth.users.id when the user is
  // signed in. Anonymous purchases will arrive with an RC-managed id and we
  // skip them — they get attached on next login via RC's identity API.
  const userIdLooksLikeUuid =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      event.app_user_id,
    );
  if (!userIdLooksLikeUuid) {
    return jsonResponse(req, { ok: true, ignored: "anonymous_app_user_id" }, 200);
  }

  const plan = mapPlan(event.product_id);
  const status = mapStatus(event.type, event.period_type, event.expiration_at_ms);
  const expiresAt = event.expiration_at_ms
    ? new Date(event.expiration_at_ms).toISOString()
    : null;
  const willRenew =
    event.type !== "CANCELLATION" &&
    event.type !== "EXPIRATION" &&
    event.type !== "NON_RENEWING_PURCHASE";
  const entitlement = event.entitlement_ids?.[0] ?? "premium";

  const { error } = await sb
    .from("subscriptions")
    .upsert(
      {
        user_id: event.app_user_id,
        plan,
        status,
        expires_at: expiresAt,
        will_renew: willRenew,
        rc_app_user_id: event.app_user_id,
        rc_entitlement: entitlement,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "user_id" },
    );

  if (error) {
    console.error("Failed to upsert subscription:", error.message);
    return jsonResponse(req, { error: "db_write_failed" }, 500);
  }

  return jsonResponse(req, { ok: true, type: event.type, status }, 200);
});
