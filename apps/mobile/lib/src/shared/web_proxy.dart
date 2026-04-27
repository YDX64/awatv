import 'package:awatv_mobile/src/app/env.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Wraps a URL through the AWAtv web proxy, but only on the web platform
/// (and only for http/https targets that aren't already pointed at the
/// proxy). On mobile / desktop / TV the original URL is returned untouched.
///
/// The proxy gives us two things browsers natively refuse to do from a
/// HTTPS page:
///   1. Reach `http://` upstreams without a mixed-content gate.
///   2. Add CORS headers so XHR / fetch / hls.js requests succeed.
///
/// HLS manifests are also rewritten by the Worker so segment URIs route
/// back through it transparently — the player just sees a normal
/// HTTPS+CORS response.
String proxify(String url) {
  if (!kIsWeb) return url;
  if (url.isEmpty) return url;
  final proxy = Env.webProxyUrl;
  if (proxy.isEmpty) return url;
  if (url.startsWith(proxy)) return url;
  if (!(url.startsWith('http://') || url.startsWith('https://'))) {
    return url;
  }
  return '$proxy/?url=${Uri.encodeComponent(url)}';
}

/// Dio interceptor that proxifies every outbound request when running on
/// the web. It rewrites the request to a single GET at the proxy and
/// preserves headers and method via the proxy's pass-through.
class WebProxyInterceptor extends Interceptor {
  const WebProxyInterceptor();

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    if (!kIsWeb) {
      handler.next(options);
      return;
    }
    final proxy = Env.webProxyUrl;
    if (proxy.isEmpty) {
      handler.next(options);
      return;
    }

    final original = options.uri.toString();
    if (original.startsWith(proxy)) {
      handler.next(options);
      return;
    }
    if (!(original.startsWith('http://') || original.startsWith('https://'))) {
      handler.next(options);
      return;
    }

    // Replace the target URI; clear path/query that Dio merged in so the
    // final outbound URL is exactly the proxy with our `?url=` param.
    final proxied = Uri.parse(
      '$proxy/?url=${Uri.encodeComponent(original)}',
    );
    options
      ..path = proxied.toString()
      ..queryParameters = const <String, dynamic>{};
    handler.next(options);
  }
}
