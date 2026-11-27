package dev.attendance.cookie_bridge

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.CalendarContract
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry
import java.util.TimeZone
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.webkit.CookieManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class CookieBridgePlugin : FlutterPlugin, MethodCallHandler, ActivityAware,
  PluginRegistry.RequestPermissionsResultListener, PluginRegistry.NewIntentListener,
  PluginRegistry.ActivityResultListener {
  private var sharedFile: Map<String, Any>? = null

  /** Keeps a file another app opened or shared with this one (up to 5 MB). */
  private fun takeIntent(intent: Intent?) {
    if (intent == null || intent.getBooleanExtra("cb_seen", false)) return
    @Suppress("DEPRECATION")
    val uri: Uri = when (intent.action) {
      Intent.ACTION_VIEW -> intent.data
      Intent.ACTION_SEND -> intent.getParcelableExtra(Intent.EXTRA_STREAM)
      else -> null
    } ?: return
    intent.putExtra("cb_seen", true)
    sharedFile = readUri(uri, 5 * 1024 * 1024) ?: return
  }

  /** {name, mime, bytes} of a file another app gives us, or null when it
   *  cannot be read or is larger than [limit] bytes. */
  private fun readUri(uri: Uri, limit: Int): Map<String, Any>? {
    try {
      var name = ""
      context.contentResolver.query(uri, null, null, null, null)?.use {
        val i = it.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
        if (i >= 0 && it.moveToFirst()) name = it.getString(i) ?: ""
      }
      val bytes = context.contentResolver.openInputStream(uri)?.use { input ->
        val out = java.io.ByteArrayOutputStream()
        val buf = ByteArray(16384)
        while (true) {
          val n = input.read(buf)
          if (n < 0) break
          out.write(buf, 0, n)
          if (out.size() > limit) return null
        }
        out.toByteArray()
      } ?: return null
      val mime = context.contentResolver.getType(uri) ?: ""
      return mapOf("name" to name, "mime" to mime, "bytes" to bytes)
    } catch (e: Exception) {
      return null // unreadable
    }
  }

  private var picking: Result? = null

  override fun onActivityResult(code: Int, resultCode: Int, data: Intent?): Boolean {
    if (code != 7422) return false
    val r = picking ?: return true
    picking = null
    val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
    if (uri == null) {
      r.success(null)
    } else {
      val file = readUri(uri, 12 * 1024 * 1024)
      if (file == null) r.error("too_big", "The file is too big or cannot be read", null)
      else r.success(file)
    }
    return true
  }

  override fun onNewIntent(intent: Intent): Boolean {
    takeIntent(intent)
    return false
  }

  private lateinit var channel: MethodChannel
  private lateinit var context: Context
  private var activity: Activity? = null
  private var asking: Result? = null

  private val calAccount = "IIMM Buddy"
  private val calPerms =
    arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR)

  private fun calAllowed() = calPerms.all {
    context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
  }

  /** Calendar links that let the app manage its own on-phone calendar. */
  private fun asOwner(uri: Uri): Uri = uri.buildUpon()
    .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
    .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_NAME, calAccount)
    .appendQueryParameter(
      CalendarContract.Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL
    ).build()

  private fun calendarId(create: Boolean): Long? {
    val cr = context.contentResolver
    cr.query(
      CalendarContract.Calendars.CONTENT_URI,
      arrayOf(CalendarContract.Calendars._ID),
      "${CalendarContract.Calendars.ACCOUNT_NAME}=? AND ${CalendarContract.Calendars.ACCOUNT_TYPE}=?",
      arrayOf(calAccount, CalendarContract.ACCOUNT_TYPE_LOCAL), null
    )?.use { if (it.moveToFirst()) return it.getLong(0) }
    if (!create) return null
    val v = ContentValues().apply {
      put(CalendarContract.Calendars.ACCOUNT_NAME, calAccount)
      put(CalendarContract.Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
      put(CalendarContract.Calendars.NAME, calAccount)
      put(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME, calAccount)
      put(CalendarContract.Calendars.CALENDAR_COLOR, 0xFF9B1C1C.toInt())
      put(
        CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL,
        CalendarContract.Calendars.CAL_ACCESS_OWNER
      )
      put(CalendarContract.Calendars.OWNER_ACCOUNT, calAccount)
      put(CalendarContract.Calendars.VISIBLE, 1)
      put(CalendarContract.Calendars.SYNC_EVENTS, 1)
      put(CalendarContract.Calendars.CALENDAR_TIME_ZONE, TimeZone.getDefault().id)
    }
    val made = cr.insert(asOwner(CalendarContract.Calendars.CONTENT_URI), v) ?: return null
    return ContentUris.parseId(made)
  }

  /** Replaces everything in the app's calendar with [events]. */
  private fun writeCalendar(events: List<*>): Boolean {
    if (!calAllowed()) return false
    val id = calendarId(true) ?: return false
    val cr = context.contentResolver
    cr.delete(
      asOwner(CalendarContract.Events.CONTENT_URI),
      "${CalendarContract.Events.CALENDAR_ID}=?", arrayOf(id.toString())
    )
    val zone = TimeZone.getDefault().id
    val rows = events.map { e ->
      val a = e as List<*>
      ContentValues().apply {
        put(CalendarContract.Events.CALENDAR_ID, id)
        put(CalendarContract.Events.TITLE, a[0] as String)
        put(CalendarContract.Events.DTSTART, (a[1] as Number).toLong())
        put(CalendarContract.Events.DTEND, (a[2] as Number).toLong())
        put(CalendarContract.Events.EVENT_LOCATION, a[3] as String)
        put(CalendarContract.Events.DESCRIPTION, a[4] as String)
        put(CalendarContract.Events.EVENT_TIMEZONE, zone)
      }
    }
    if (rows.isNotEmpty()) {
      cr.bulkInsert(asOwner(CalendarContract.Events.CONTENT_URI), rows.toTypedArray())
    }
    return true
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
    binding.addRequestPermissionsResultListener(this)
    binding.addOnNewIntentListener(this)
    binding.addActivityResultListener(this)
    takeIntent(binding.activity.intent)
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
    onAttachedToActivity(binding)

  override fun onDetachedFromActivity() {
    activity = null
  }

  override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

  override fun onRequestPermissionsResult(
    code: Int, permissions: Array<out String>, results: IntArray
  ): Boolean {
    if (code != 7421) return false
    asking?.success(calAllowed())
    asking = null
    return true
  }

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    channel = MethodChannel(binding.binaryMessenger, "cookie_bridge")
    channel.setMethodCallHandler(this)
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    try {
      val cm = CookieManager.getInstance()
      when (call.method) {
        "get" -> result.success(cm.getCookie(call.arguments as String) ?: "")
        "set" -> {
          val a = call.arguments as List<*>
          cm.setCookie(a[0] as String, a[1] as String)
          cm.flush()
          result.success(null)
        }
        "keep" -> {
          // Session cookies are dropped when the app is closed. Writing them
          // back with a long life keeps the sign-in across restarts.
          val a = call.arguments as List<*>
          val url = a[0] as String
          val names = (a[1] as List<*>).map { it as String }
          val all = cm.getCookie(url) ?: ""
          for (part in all.split(";")) {
            val eq = part.indexOf('=')
            if (eq <= 0) continue
            val name = part.substring(0, eq).trim()
            if (name in names) {
              val value = part.substring(eq + 1).trim()
              cm.setCookie(url, "$name=$value; Max-Age=31536000; Path=/; Secure; HttpOnly")
            }
          }
          cm.flush()
          result.success(null)
        }
        "widget" -> {
          val cn = ComponentName(context, context.packageName + ".AttendanceWidget")
          val ids = AppWidgetManager.getInstance(context).getAppWidgetIds(cn)
          if (ids.isNotEmpty()) {
            context.sendBroadcast(
              Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                .setComponent(cn)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            )
          }
          result.success(null)
        }
        "email" -> {
          val a = call.arguments as List<*>
          val uri = Uri.parse(
            "mailto:" + Uri.encode(a[0] as String, "@,") +
              "?subject=" + Uri.encode(a[1] as String) +
              "&body=" + Uri.encode(a[2] as String)
          )
          context.startActivity(
            Intent(Intent.ACTION_SENDTO, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
          )
          result.success(null)
        }
        "calAsk" -> {
          val a = activity
          if (calAllowed()) {
            result.success(true)
          } else if (a == null || asking != null) {
            result.success(false)
          } else {
            asking = result
            a.requestPermissions(calPerms, 7421)
          }
        }
        "calWrite" -> result.success(writeCalendar(call.arguments as List<*>))
        "calRemove" -> {
          if (calAllowed()) {
            calendarId(false)?.let {
              context.contentResolver.delete(
                asOwner(ContentUris.withAppendedId(CalendarContract.Calendars.CONTENT_URI, it)),
                null, null
              )
            }
          }
          result.success(null)
        }
        "batteryOk" -> {
          val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
          result.success(pm.isIgnoringBatteryOptimizations(context.packageName))
        }
        "batteryMode" -> {
          // "unrestricted", "optimized" (Android's default, also what the
          // "Allow background usage" switch gives on Android 15+), or
          // "restricted" (the app is stopped in the background).
          val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
          val am = context.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
          result.success(
            when {
              pm.isIgnoringBatteryOptimizations(context.packageName) -> "unrestricted"
              Build.VERSION.SDK_INT >= 28 && am.isBackgroundRestricted -> "restricted"
              else -> "optimized"
            }
          )
        }
        "batteryAsk" -> {
          // The system's own "let this app run in the background?" question.
          // Falls back to the app's settings page where that is not offered,
          // or when the build leaves out the permission it needs (Play).
          val declared = context.packageManager.checkPermission(
            Manifest.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            context.packageName
          ) == PackageManager.PERMISSION_GRANTED
          try {
            if (!declared) throw SecurityException("not declared")
            context.startActivity(
              Intent(
                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:" + context.packageName)
              ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
          } catch (e: Exception) {
            context.startActivity(
              Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:" + context.packageName)
              ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
          }
          result.success(null)
        }
        "maker" -> result.success(Build.MANUFACTURER ?: "")
        "package" -> result.success(context.packageName)
        "device" -> result.success(
          "${Build.MANUFACTURER} ${Build.MODEL}, Android ${Build.VERSION.RELEASE}"
        )
        "appInfo" -> {
          context.startActivity(
            Intent(
              Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
              Uri.parse("package:" + context.packageName)
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
          )
          result.success(null)
        }
        "pickFile" -> {
          val a = activity
          if (a == null || picking != null) {
            result.success(null)
          } else {
            picking = result
            val types = (call.arguments as? List<*>)?.map { "$it" }?.toTypedArray()
              ?: arrayOf("*/*")
            a.startActivityForResult(
              Intent(Intent.ACTION_OPEN_DOCUMENT)
                .addCategory(Intent.CATEGORY_OPENABLE)
                .setType(if (types.size == 1) types[0] else "*/*")
                .putExtra(Intent.EXTRA_MIME_TYPES, types),
              7422
            )
          }
        }
        "takeFile" -> {
          result.success(sharedFile)
          sharedFile = null
        }
        "open" -> {
          context.startActivity(
            Intent(Intent.ACTION_VIEW, Uri.parse(call.arguments as String))
              .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
          )
          result.success(null)
        }
        else -> result.notImplemented()
      }
    } catch (e: Exception) {
      result.error("cookie", e.message, null)
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }
}
