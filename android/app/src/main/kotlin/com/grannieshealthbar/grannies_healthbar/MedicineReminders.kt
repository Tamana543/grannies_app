package com.grannieshealthbar.grannies_healthbar

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

object MedicineReminders {
    private const val CHANNEL = "daily_medicines"
    private const val PREFS = "medicine_reminders"
    private const val SCHEDULE = "schedule"

    fun update(context: Context, events: List<Map<String, Any>>) {
        // Group medicines at the same time into one alarm/notification.
        val groups = events.groupBy { it["time"] as String }.toSortedMap()
        val schedule = JSONArray()
        groups.forEach { (time, medicines) ->
            require(Regex("^([01]\\d|2[0-3]):[0-5]\\d$").matches(time))
            schedule.put(JSONObject().put("time", time).put("names",
                medicines.map { it["name"] as String }.distinct().joinToString(", ")))
        }
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val old = prefs.getString(SCHEDULE, "[]")!!
        if (old == schedule.toString()) return
        val alarms = context.getSystemService(AlarmManager::class.java)
        val notifications = context.getSystemService(NotificationManager::class.java)
        val previous = JSONArray(old)
        for (i in 0 until previous.length()) {
            alarms.cancel(pending(context, i, previous.getJSONObject(i)))
            notifications.cancel(1000 + i)
        }
        prefs.edit().putString(SCHEDULE, schedule.toString()).commit()
        restore(context)
    }

    fun restore(context: Context) {
        val schedule = JSONArray(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(SCHEDULE, "[]"))
        for (i in 0 until schedule.length()) scheduleNext(context, i, schedule.getJSONObject(i))
    }

    fun scheduleNext(context: Context, id: Int, event: JSONObject) {
        val parts = event.getString("time").split(":")
        val now = System.currentTimeMillis()
        val next = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, parts[0].toInt())
            set(Calendar.MINUTE, parts[1].toInt())
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= now) add(Calendar.DAY_OF_YEAR, 1)
        }
        val alarms = context.getSystemService(AlarmManager::class.java)
        val intent = pending(context, id, event)
        // Permission can be revoked between checking and scheduling.
        try {
            if (Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms()) {
                alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.timeInMillis, intent)
            } else {
                alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.timeInMillis, intent)
            }
        } catch (_: SecurityException) {
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.timeInMillis, intent)
        }
    }

    private fun pending(context: Context, id: Int, event: JSONObject): PendingIntent =
        PendingIntent.getBroadcast(context, id,
            Intent(context, MedicineAlarmReceiver::class.java)
                .setAction("${context.packageName}.MEDICINE.$id")
                .putExtra("id", id).putExtra("event", event.toString()),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    fun notify(context: Context, id: Int, event: JSONObject) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "Medicine reminders",
            NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Reminders for your daily medicine schedule"
                enableVibration(true)
            })
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(
                Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val open = PendingIntent.getActivity(context, 0,
            Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val body = "It’s time for ${event.getString("names")}."
        manager.notify(1000 + id, Notification.Builder(context, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("Medicine time · ${event.getString("time")}")
            .setContentText(body).setStyle(Notification.BigTextStyle().bigText(body))
            .setCategory(Notification.CATEGORY_REMINDER).setContentIntent(open)
            .setVisibility(Notification.VISIBILITY_PRIVATE).setAutoCancel(true).build())
    }
}

class MedicineAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("id", -1)
        if (id < 0) return
        // Read the current schedule; ignore old queued broadcasts after a plan change.
        val schedule = JSONArray(context.getSharedPreferences("medicine_reminders", Context.MODE_PRIVATE)
            .getString("schedule", "[]"))
        if (id >= schedule.length()) return
        val event = schedule.getJSONObject(id)
        if (event.toString() != intent.getStringExtra("event")) return
        MedicineReminders.scheduleNext(context, id, event)
        MedicineReminders.notify(context, id, event)
    }
}

class ReminderRestoreReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        MedicineReminders.restore(context)
    }
}
