// AWAtv CORS / HTTPS / HLS-aware proxy.
//
// Usage:
//   GET https://awa-proxy.<account>.workers.dev/?url=<urlencoded-target>
//
// Strips Host/Origin/Referer headers, fetches the target on Cloudflare's
// edge (no browser mixed-content gate), mirrors response with permissive
// CORS headers. For HLS .m3u8 / .m3u manifests it also rewrites every
// embedded URI so child playlists and .ts segments also loop through us.
//
// Provider intelligence: many panels reject any non-native-player UA.
// The PROVIDER_PROFILES map mirrors awatv_core's provider_intel.dart
// fingerprints so the proxy emits the SAME User-Agent the native
// players would send. Default falls back to VLC, which is what the
// majority of Xtream-based panels accept.

const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, POST, HEAD, OPTIONS',
  'access-control-allow-headers': '*',
  'access-control-expose-headers': '*',
  'access-control-max-age': '86400',
};

const DEFAULT_UA = 'VLC/3.0.20 LibVLC/3.0.20';

// Per-host fingerprint table. Mirrors provider_intel.dart's registry —
// keep these two lists in sync when adding new providers.
//
// `match` is a list of host suffixes; if the upstream host equals one
// or ends with `.suffix` we use that fingerprint. First match wins.
//
// `ua` overrides the User-Agent header.
// `referer` (optional) sets a Referer header on outbound requests for
// hot-link-protected panels; default is `<scheme>://<host>/`.
// `addReferer` (default false) flips the auto-Referer behaviour on for
// generic panels that don't need a custom value.
// `notes` is human-readable rationale for review.
const PROVIDER_PROFILES = [
  {
    id: 'worldiptv',
    match: ['worldiptv.me', 'worldiptv.live', 'worldiptv.tv'],
    ua: DEFAULT_UA,
    addReferer: true,
    notes: 'IP-locked to residential; UA must be VLC/Smarters; Referer required.',
  },
  {
    id: 'xtream-codes-original',
    match: ['xtreamcodes.com', 'xtream-codes.com'],
    ua: DEFAULT_UA,
    notes: 'Original (defunct) Xtream Codes layout.',
  },
  {
    id: 'iptvmate-style',
    match: ['iptvmate.io', 'iptvmate.app', 'ottmate.tv'],
    ua: DEFAULT_UA,
    notes: '/play/ rooted Node-based panels. m3u8-only.',
  },
  {
    id: 'sansat-style',
    match: ['sansat.tv', 'sansat.io', 'kralhd.tv'],
    ua: DEFAULT_UA,
    addReferer: true,
    notes: 'Hot-link-protected: Referer must match panel host.',
  },
  {
    id: 'ott-iptv-stream',
    match: ['ott.iptv-stream.tv', 'iptv-stream.tv'],
    ua: DEFAULT_UA,
    notes: 'Direct mp4/mkv VOD; no HLS layer.',
  },
  {
    id: 'tivustream',
    match: ['tivustream.tv', 'tivustream.live', 'tivunetwork.tv'],
    ua: DEFAULT_UA,
    notes: 'Series under /tv/ instead of /series/.',
  },
  {
    id: 'smarters-pro',
    match: ['smarters.pro', 'iptvsmarters.com'],
    // Smarters-branded panels often whitelist the Smarters mobile UA.
    ua: 'IPTVSmarters',
    notes: 'IPTV Smarters-branded panels accept the Smarters UA explicitly.',
  },
  {
    id: 'cdnvip',
    match: ['cdnvip.tv', 'cdnvip.live', 'vip-cdn.tv'],
    ua: DEFAULT_UA,
    notes: '.ts-only — no HLS muxer. Mandatory proxy for browsers.',
  },
  {
    id: 'generic-hls',
    match: ['hlspanel.io', 'hls-iptv.tv'],
    ua: DEFAULT_UA,
    notes: 'Defensive entry for HLS-first generic panels.',
  },
];

function profileFor(hostname) {
  const h = (hostname || '').toLowerCase();
  if (!h) return null;
  for (const p of PROVIDER_PROFILES) {
    for (const suffix of p.match) {
      const s = suffix.toLowerCase();
      if (h === s || h.endsWith('.' + s)) return p;
    }
  }
  return null;
}

// Resolve the User-Agent for [profile], honouring per-profile env overrides.
// Env var name is `UA_OVERRIDE_<id>` with hyphens replaced by underscores
// (Cloudflare env vars can't contain hyphens). Falls back to DEFAULT_UA.
function resolveUa(profile, env) {
  if (env) {
    if (profile && profile.id) {
      const key = 'UA_OVERRIDE_' + profile.id.replace(/-/g, '_');
      const overriden = env[key];
      if (typeof overriden === 'string' && overriden.length > 0) {
        return overriden;
      }
    }
    if (typeof env.DEFAULT_UA === 'string' && env.DEFAULT_UA.length > 0) {
      // Profile-supplied UA still wins over env default — env DEFAULT_UA
      // only applies when the profile doesn't specify one.
      if (profile && profile.ua) return profile.ua;
      return env.DEFAULT_UA;
    }
  }
  return (profile && profile.ua) || DEFAULT_UA;
}

export default {
  async fetch(req, env) {
    if (req.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: CORS });
    }

    const reqUrl = new URL(req.url);
    const target = reqUrl.searchParams.get('url');
    if (!target) {
      return json({ error: 'missing ?url= query parameter' }, 400);
    }

    let upstream;
    try {
      upstream = new URL(decodeURIComponent(target));
    } catch (_) {
      return json({ error: 'malformed url parameter' }, 400);
    }
    if (!/^https?:$/.test(upstream.protocol)) {
      return json({ error: 'only http and https targets allowed' }, 400);
    }

    const fwdHeaders = new Headers(req.headers);
    [
      'host', 'origin', 'referer',
      'cf-connecting-ip', 'cf-ipcountry', 'cf-ray', 'cf-visitor',
      'x-forwarded-for', 'x-forwarded-host', 'x-forwarded-proto', 'x-real-ip',
    ].forEach((h) => fwdHeaders.delete(h));

    // Look up the per-host fingerprint. The default profile is VLC with
    // no Referer — works for most generic Xtream panels. Specific
    // panels (worldiptv.me, sansat.tv, smarters.pro, …) override.
    const profile = profileFor(upstream.hostname);
    const ua = resolveUa(profile, env);
    fwdHeaders.set('user-agent', ua);

    // Some panels (sansat.tv, worldiptv.me) reject 403 unless a Referer
    // header matches the panel's own origin. We only set this when the
    // profile asks for it, otherwise an unexpected Referer can itself
    // cause the upstream to reject us (some CDNs prefer "no Referer"
    // over "wrong Referer").
    if (profile && profile.addReferer) {
      const referer = profile.referer
        || `${upstream.protocol}//${upstream.hostname}/`;
      fwdHeaders.set('referer', referer);
    }

    let upstreamRes;
    try {
      upstreamRes = await fetch(upstream.toString(), {
        method: req.method,
        headers: fwdHeaders,
        body: ['GET', 'HEAD'].includes(req.method) ? undefined : req.body,
        redirect: 'follow',
      });
    } catch (err) {
      return json({ error: 'upstream fetch failed', detail: String(err) }, 502);
    }

    const ct = (upstreamRes.headers.get('content-type') || '').toLowerCase();
    const path = upstream.pathname.toLowerCase();
    const isHls =
      ct.includes('mpegurl') ||
      ct.includes('vnd.apple.mpegurl') ||
      path.endsWith('.m3u8') ||
      path.endsWith('.m3u');

    const resHeaders = new Headers(upstreamRes.headers);
    Object.entries(CORS).forEach(([k, v]) => resHeaders.set(k, v));
    resHeaders.delete('content-security-policy');
    resHeaders.delete('strict-transport-security');
    resHeaders.delete('x-frame-options');

    if (!isHls) {
      return new Response(upstreamRes.body, {
        status: upstreamRes.status,
        headers: resHeaders,
      });
    }

    let body = await upstreamRes.text();
    body = rewriteHls(body, upstream, reqUrl.origin);
    resHeaders.set('content-type', 'application/vnd.apple.mpegurl');
    resHeaders.delete('content-length');
    return new Response(body, {
      status: upstreamRes.status,
      headers: resHeaders,
    });
  },
};

function rewriteHls(body, upstreamUrl, proxyOrigin) {
  const lines = body.split(/\r?\n/);
  const out = lines.map((line) => {
    if (!line || line.startsWith('#')) {
      return line.replace(/URI="([^"]+)"/g, (_m, raw) => {
        return `URI="${proxify(raw, upstreamUrl, proxyOrigin)}"`;
      });
    }
    return proxify(line, upstreamUrl, proxyOrigin);
  });
  return out.join('\n');
}

function proxify(raw, upstreamUrl, proxyOrigin) {
  let abs;
  try {
    abs = new URL(raw, upstreamUrl).toString();
  } catch (_) {
    return raw;
  }
  return `${proxyOrigin}/?url=${encodeURIComponent(abs)}`;
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { 'content-type': 'application/json', ...CORS },
  });
}
