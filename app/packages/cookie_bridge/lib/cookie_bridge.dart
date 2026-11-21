// Gives Dart code (in the app and in background work) access to the Android
// WebView cookie jar, so requests made outside the WebView stay signed in.
import 'package:flutter/services.dart';

const _channel = MethodChannel('cookie_bridge');

/// Cookie header value for [url] ("a=1; b=2"), or an empty string.
Future<String> cookiesFor(String url) async =>
    await _channel.invokeMethod<String>('get', url) ?? '';

/// Stores one Set-Cookie header value received from [url].
Future<void> storeCookie(String url, String setCookie) =>
    _channel.invokeMethod('set', [url, setCookie]);

/// Makes the named session cookies of [url] survive app restarts.
Future<void> keepCookies(String url, List<String> names) =>
    _channel.invokeMethod('keep', [url, names]);

/// Asks Android to redraw the home screen widget.
Future<void> refreshWidget() => _channel.invokeMethod('widget');

/// Opens the phone's email app with a draft. [to] may be empty.
Future<void> composeEmail(String to, String subject, String body) =>
    _channel.invokeMethod('email', [to, subject, body]);

/// Asks the user for calendar access. True when granted.
Future<bool> askCalendar() async =>
    await _channel.invokeMethod<bool>('calAsk') ?? false;

/// Replaces the app's own phone calendar with [events]: each one is
/// [title, start ms, end ms, place, note]. False without calendar access.
Future<bool> writeCalendar(List<List<Object>> events) async =>
    await _channel.invokeMethod<bool>('calWrite', events) ?? false;

/// Removes the app's phone calendar and everything in it.
Future<void> removeCalendar() => _channel.invokeMethod('calRemove');

/// True when Android lets the app run in the background without limits.
Future<bool> batteryUnrestricted() async =>
    await _channel.invokeMethod<bool>('batteryOk') ?? true;

/// The phone maker, lower case ("xiaomi", "samsung"...).
Future<String> phoneMaker() async =>
    (await _channel.invokeMethod<String>('maker') ?? '').toLowerCase();

/// Opens this app's page in the phone's Settings.
Future<void> openAppInfo() => _channel.invokeMethod('appInfo');

/// A file another app opened with, or shared to, this app since the last
/// call: (name, bytes). Null when there is none.
Future<(String, List<int>)?> takeSharedFile() async {
  final m = await _channel.invokeMethod<Map<Object?, Object?>>('takeFile');
  if (m == null) return null;
  return ('${m['name']}', (m['bytes'] as List).cast<int>());
}

/// "samsung SM-A546E, Android 14".
Future<String> deviceName() async =>
    await _channel.invokeMethod<String>('device') ?? '';

/// Asks Android to let the app run in the background without limits.
Future<void> askBatteryUnrestricted() => _channel.invokeMethod('batteryAsk');

/// Lets the user pick a file of one of [types] ("image/*",
/// "application/pdf"): (name, mime type, bytes), or null when they backed
/// out. Throws when the file is over 12 MB or cannot be read.
Future<(String, String, List<int>)?> pickFile(List<String> types) async {
  final m = await _channel.invokeMethod<Map<Object?, Object?>>('pickFile', types);
  if (m == null) return null;
  return ('${m['name']}', '${m['mime']}', (m['bytes'] as List).cast<int>());
}
