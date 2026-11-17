// The on-screen sign-in.
//
// Data is fetched with plain requests (see net.dart), which also renew the
// sign-in silently. This WebView is the last resort: it is shown only when
// Microsoft itself wants the user to sign in again.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'net.dart';

export 'net.dart';

enum SessionState { checking, signedIn, needsLogin }

class Session extends ChangeNotifier {
  Session() {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: _onPage,
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? false) _onPage('error:${e.description}');
        },
      ));
  }

  late final WebViewController controller;
  SessionState state = SessionState.checking;

  final _pageEvents = StreamController<String>.broadcast();
  Future<void> _queue = Future.value();

  void _onPage(String url) {
    _pageEvents.add(url);
    // While the sign-in screen is showing, notice when the user gets through.
    if (state == SessionState.needsLogin &&
        (insideSite(url) || insideMoodle(url))) {
      keepSessions();
      _set(SessionState.signedIn);
    }
  }

  void _set(SessionState s) {
    if (state == s) return;
    state = s;
    notifyListeners();
  }

  /// Runs [go] (something that makes the WebView navigate) and waits until
  /// navigation settles: redirect chains fire several page events, so wait for
  /// a quiet moment. Returns the final URL.
  Future<String> _settle(Future<void> Function() go,
      {int timeoutSeconds = 25}) async {
    String? last;
    Timer? quiet;
    final done = Completer<String>();
    final sub = _pageEvents.stream.listen((u) {
      last = u;
      quiet?.cancel();
      quiet = Timer(const Duration(milliseconds: 1200), () {
        if (!done.isCompleted) done.complete(u);
      });
    });
    await go();
    try {
      return await done.future.timeout(Duration(seconds: timeoutSeconds),
          onTimeout: () => last ?? 'error:timeout');
    } finally {
      quiet?.cancel();
      await sub.cancel();
    }
  }

  Future<String> _load(String url) =>
      _settle(() => controller.loadRequest(Uri.parse(url)));

  /// The WebView can only do one sign-in at a time.
  Future<T> _oneAtATime<T>(Future<T> Function() job) {
    final run = _queue.then((_) => job());
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<bool>? _ensuringSite;
  Future<bool>? _ensuringMoodle;

  /// Makes sure the attendance site has a live session. Returns false when the
  /// user has to sign in on screen. Throws on network failure.
  Future<bool> ensure() =>
      _ensuringSite ??= _oneAtATime(_ensureSite).whenComplete(() {
        _ensuringSite = null;
      });

  Future<bool> _ensureSite() async {
    final url = await _load(ssoStart);
    if (insideSite(url)) {
      await keepSessions();
      _set(SessionState.signedIn);
      return true;
    }
    if (url.startsWith('error:')) throw Exception('Cannot reach the site');
    // The WebView is now on Microsoft's sign-in page (or the site's own).
    if (Uri.tryParse(url)?.host == siteHost) {
      await controller.loadRequest(Uri.parse(ssoStart));
    }
    _set(SessionState.needsLogin);
    return false;
  }

  /// Same for Moodle.
  Future<bool> ensureMoodle() =>
      _ensuringMoodle ??= _oneAtATime(_ensureMoodle).whenComplete(() {
        _ensuringMoodle = null;
      });

  Future<bool> _ensureMoodle() async {
    var url = await _load(moodleLogin);
    if (url.startsWith('error:')) throw Exception('Cannot reach Moodle');
    if (!insideMoodle(url)) {
      // Press Moodle's "Microsoft" button.
      url = await _settle(() => controller.runJavaScript(
          "var a=document.querySelector('a[href*=\"auth/oauth2/login.php\"]');"
          "if(a){location.href=a.href;}else{location.reload();}"));
    }
    if (insideMoodle(url)) {
      await keepSessions();
      _set(SessionState.signedIn);
      return true;
    }
    if (url.startsWith('error:')) throw Exception('Cannot reach Moodle');
    _set(SessionState.needsLogin);
    return false;
  }

  /// Restart the on-screen sign-in from the beginning.
  Future<void> restartLogin() => controller.loadRequest(Uri.parse(ssoStart));

  /// Fetches an attendance-site API path, signing in again if needed.
  Future<String> api(String path) async {
    final body = await siteApi(path, onScreen: ensure);
    _set(SessionState.signedIn);
    return body;
  }

  Future<void> signOut() async {
    await WebViewCookieManager().clearCookies();
    await controller.clearLocalStorage();
    _set(SessionState.needsLogin);
    await restartLogin();
  }
}
