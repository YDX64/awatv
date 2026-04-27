-- ============================================================================
-- AWAtv — Performance indexes
-- ----------------------------------------------------------------------------
-- Migration: 20260427000003_indexes
-- Author:    database-optimizer agent
-- Purpose:   Indexes that match the actual access patterns clients use.
--
-- Access patterns
--   1. "List my playlists"             → playlist_sources where user_id = ?
--   2. "List my favorites, newest first" → favorites where user_id = ? order by added_at desc
--   3. "Continue watching"             → watch_history where user_id = ? order by watched_at desc
--   4. "List my devices, active first"   → device_sessions where user_id = ? order by last_seen_at desc
--   5. "Recent telemetry for analytics" → telemetry_events where user_id = ? order by occurred_at desc
--
-- Notes
--   * The (user_id) prefix on every index lines up with RLS predicates so the
--     planner can satisfy both row filtering and ordering with a single scan.
--   * For favorites / watch_history / device_sessions / telemetry_events we
--     use composite (user_id, <ts> desc) indexes so order-by is satisfied by
--     the index itself — no in-memory sort even on hot users.
-- ============================================================================

-- (1) playlist_sources: simple per-user lookup; no ordering.
create index if not exists idx_playlist_sources_user
  on public.playlist_sources (user_id);

-- (2) favorites: ordered by recency.
create index if not exists idx_favorites_user_added_at
  on public.favorites (user_id, added_at desc);

-- (3) watch_history: ordered by last-watched.
create index if not exists idx_watch_history_user_watched_at
  on public.watch_history (user_id, watched_at desc);

-- (4) device_sessions: ordered by last-seen for active-device UI.
create index if not exists idx_device_sessions_user_last_seen
  on public.device_sessions (user_id, last_seen_at desc);

-- (5) telemetry_events: ordered by occurrence for time-window queries.
create index if not exists idx_telemetry_events_user_occurred_at
  on public.telemetry_events (user_id, occurred_at desc);

-- Standalone time index helps housekeeping queries that scan by date alone
-- (e.g. "delete events older than 90 days" service-role job).
create index if not exists idx_telemetry_events_occurred_at
  on public.telemetry_events (occurred_at desc);
