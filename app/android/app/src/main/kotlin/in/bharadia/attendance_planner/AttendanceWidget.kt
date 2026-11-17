package `in`.bharadia.attendance_planner

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews

/**
 * Home screen widget: the next class with a live countdown, and overall
 * attendance. The app writes the texts into Flutter's shared preferences.
 */
class AttendanceWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val p = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val startsAt = (p.getString("flutter.w_at", "0") ?: "0").toLongOrNull() ?: 0L
        val left = startsAt - System.currentTimeMillis()
        for (id in ids) {
            val v = RemoteViews(context.packageName, R.layout.attendance_widget)
            val past = startsAt > 0 && left <= 0
            v.setTextViewText(
                R.id.w_course,
                if (past) "Open the app for the next class"
                else p.getString("flutter.w_course", "Open the app to sign in")
            )
            v.setTextViewText(R.id.w_when, if (past) "" else p.getString("flutter.w_when", ""))
            v.setTextViewText(R.id.w_pct, p.getString("flutter.w_pct", ""))
            v.setTextViewText(R.id.w_state, p.getString("flutter.w_state", ""))
            // A ticking "in 1:23:45" for a class within the next day.
            if (left in 1 until 24L * 3600 * 1000 && Build.VERSION.SDK_INT >= 24) {
                v.setViewVisibility(R.id.w_timer, View.VISIBLE)
                v.setChronometerCountDown(R.id.w_timer, true)
                v.setChronometer(
                    R.id.w_timer, SystemClock.elapsedRealtime() + left, "in %s", true
                )
            } else {
                v.setViewVisibility(R.id.w_timer, View.GONE)
            }
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launch != null) {
                v.setOnClickPendingIntent(
                    R.id.w_root,
                    PendingIntent.getActivity(
                        context, 0, launch,
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                    )
                )
            }
            manager.updateAppWidget(id, v)
        }
    }
}
