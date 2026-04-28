// AWAtv CORS / HTTPS / HLS-aware proxy.
//
// Usage:
//   GET https://awa-proxy.<account>.workers.dev/?url=<urlencoded-target>
//
// Strips Host/Origin/Referer headers, fetches the target on Cloudflare's
// edge (no browser mixed-content gate), mirrors response with permissive
// CORS headers. For HLS .m3u8 / .m3u manifests it also rewrites every
// embedded URI so child playlists and .ts segments also loop through us.

const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, POST, HEAD, OPTIONS',
  'access-control-allow-headers': '*',
  'access-control-expose-headers': '*',
  'access-control-max-age': '86400',
};

export default {
  async fetch(req) {
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
    // Most IPTV panels (worldiptv.me, several Xtream panels) reject any
    // browser-style User-Agent with a 456 status. They expect a native
    // player UA (VLC, IPTV Smarters, MX Player, …). We override
    // unconditionally to a VLC string — the same way real IPTV clients
    // do — so the upstream serves the stream regardless of what header
    // the browser added.
    fwdHeaders.set('user-agent', 'VLC/3.0.20 LibVLC/3.0.20');

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
