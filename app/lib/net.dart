// Signed-in requests to the attendance site and Moodle.
//
// Requests use the Android WebView cookie jar (through the cookie_bridge
// plugin), so they work both in the app and in background checks. Both sites
// sign in through the same Microsoft account. When a site's own session has
// run out, [httpSsoSite] / [httpSsoMoodle] replay the Microsoft sign-in with
// plain requests: as long as Microsoft still remembers the user ("Stay signed
// in"), that succeeds without showing anything.

import 'dart:convert';
import 'dart:io';

import 'package:cookie_bridge/cookie_bridge.dart';

import 'demo.dart';

const siteHost = 'iimmumbai.ac.in';
const siteBase = 'https://iimmumbai.ac.in/attendancestudent/';
const moodleHost = 'moodle.iimmumbai.ac.in';
const moodleBase = 'https://moodle.iimmumbai.ac.in';
const ssoStart = '${siteBase}public/microsoft-login.php';
const moodleLogin = '$moodleBase/login/index.php';

class NotSignedIn implements Exception {}

const _agent = 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36';

class HttpReply {
  HttpReply(this.url, this.response);

  /// Address after following redirects.
  final Uri url;
  final HttpClientResponse response;

  int get status => response.statusCode;
  String get contentType => response.headers.contentType?.mimeType ?? '';
  Future<String> text() =>
      response.transform(const Utf8Decoder(allowMalformed: true)).join();
}

final _client = HttpClient()
  ..connectionTimeout = const Duration(seconds: 20)
  ..idleTimeout = const Duration(seconds: 30);

/// One request with the WebView's cookies, following redirects by hand so the
/// right cookies go to each host.
Future<HttpReply> httpSend(Uri url, {String? jsonBody}) async {
  if (demoMode && (url.host == siteHost || url.host == moodleHost)) {
    throw Exception(demoNote);
  }
  var method = jsonBody == null ? 'GET' : 'POST';
  for (var hop = 0; hop < 8; hop++) {
    final req = await _client.openUrl(method, url);
    req.followRedirects = false;
    req.headers.set(HttpHeaders.userAgentHeader, _agent);
    final cookie = await cookiesFor('$url');
    if (cookie.isNotEmpty) req.headers.set(HttpHeaders.cookieHeader, cookie);
    if (method == 'POST') {
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonBody!));
    }
    final res = await req.close().timeout(const Duration(seconds: 60));
    for (final c in res.headers[HttpHeaders.setCookieHeader] ?? const []) {
      await storeCookie('$url', c);
    }
    final loc = res.headers.value(HttpHeaders.locationHeader);
    if (res.isRedirect && loc != null) {
      await res.drain<void>();
      url = url.resolve(loc);
      method = 'GET';
      continue;
    }
    return HttpReply(url, res);
  }
  throw Exception('Too many redirects');
}

bool insideSite(String url) {
  final u = Uri.tryParse(url);
  if (u == null || u.host != siteHost) return false;
  if (!u.path.startsWith('/attendancestudent')) return false;
  return !u.path.endsWith('/login.php') &&
      !u.path.endsWith('/microsoft-login.php') &&
      !u.path.endsWith('/callback.php');
}

bool insideMoodle(String url) {
  final u = Uri.tryParse(url);
  return u != null &&
      u.host == moodleHost &&
      !u.path.startsWith('/login') &&
      !u.path.startsWith('/auth');
}

/// Session cookies normally vanish when the app closes; keep them.
Future<void> keepSessions() async {
  try {
    await keepCookies(siteBase, ['PHPSESSID']);
    await keepCookies('$moodleBase/', ['MoodleSession']);
  } catch (_) {}
}

/// Signs in to the attendance site again without showing anything.
Future<bool> httpSsoSite() async {
  try {
    final r = await httpSend(Uri.parse(ssoStart));
    await r.response.drain<void>();
    final ok = insideSite('${r.url}');
    if (ok) await keepSessions();
    return ok;
  } on SocketException {
    rethrow;
  } catch (_) {
    return false;
  }
}

/// Signs in to Moodle again without showing anything.
Future<bool> httpSsoMoodle() async {
  try {
    var r = await httpSend(Uri.parse(moodleLogin));
    final html = await r.text();
    if (!insideMoodle('${r.url}')) {
      final m =
          RegExp(r'href="([^"]*auth/oauth2/login\.php[^"]*)"').firstMatch(html);
      if (m == null) return false;
      r = await httpSend(Uri.parse(m.group(1)!.replaceAll('&amp;', '&')));
      await r.response.drain<void>();
    }
    final ok = insideMoodle('${r.url}');
    if (ok) await keepSessions();
    return ok;
  } on SocketException {
    rethrow;
  } catch (_) {
    return false;
  }
}

/// Fetches an attendance-site API path, signing in again if needed.
/// [onScreen] is the last resort: a sign-in the user completes on screen.
Future<String> siteApi(String path, {Future<bool> Function()? onScreen}) async {
  if (demoMode) return demoSummary(DateTime.now());
  Future<String?> once() async {
    final r = await httpSend(Uri.parse(siteBase).resolve(path));
    final body = await r.text();
    final out = r.url.path.endsWith('login.php') ||
        r.status == 401 ||
        body.contains('Unauthorized access');
    return out ? null : body;
  }

  var body = await once();
  if (body == null && await httpSsoSite()) body = await once();
  if (body == null) {
    if (onScreen == null || !await onScreen()) throw NotSignedIn();
    body = await once();
    if (body == null) throw Exception('The site did not accept the sign-in');
  }
  return body;
}
