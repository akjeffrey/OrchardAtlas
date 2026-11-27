package com.orchardatlas.orchard_atlas

import android.Manifest
import android.content.ContentUris
import android.content.ContentValues
import android.content.pm.PackageManager
import android.provider.CalendarContract
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.concurrent.Executors

/** Uses the phone's calendar sync adapter. No Google OAuth token is stored by Flutter. */
class TaskCalendarChannel(private val activity: MainActivity) : MethodChannel.MethodCallHandler {
    private val prefs = activity.getSharedPreferences("orchard-task-calendars", 0)
    private val worker = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private val permissionCode = 8347
    private fun allowed() = activity.checkSelfPermission(Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED &&
        activity.checkSelfPermission(Manifest.permission.WRITE_CALENDAR) == PackageManager.PERMISSION_GRANTED

    fun permissionResult(code: Int, grants: IntArray): Boolean {
        if (code != permissionCode) return false
        val result = pending; pending = null
        if (result != null) {
            if (allowed()) perform("calendars", emptyMap(), result)
            else result.error("calendar_permission", "Allow Calendar access in Android settings to connect Google Calendar.", null)
        }
        return true
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "calendars" && !allowed()) {
            if (pending != null) { result.error("busy", "A calendar permission request is already open", null); return }
            pending = result
            activity.requestPermissions(arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR), permissionCode)
            return
        }
        @Suppress("UNCHECKED_CAST")
        perform(call.method, call.arguments as? Map<String, Any?> ?: emptyMap(), result)
    }
    private fun perform(method: String, args: Map<String, Any?>, result: MethodChannel.Result) {
        worker.execute {
            try {
                val scope = args["scope"] as? String ?: ""
                val value: Any? = when (method) {
                    "selected" -> prefs.getString("calendar/$scope", null)
                    "calendars" -> calendars()
                    "select" -> {
                        check(allowed()) { "Calendar permission is required to change connections" }
                        val next = args["calendar"] as? String
                        if (next != null) check(calendars().any { it["id"] == next }) { "Choose a writable calendar" }
                        val previous = prefs.getString("calendar/$scope", null)
                        if (previous != next) {
                            if (previous != null) reconcile(scope, previous.toLong(), emptyList())
                            prefs.edit().putString("calendar/$scope", next).commit()
                        }
                        null
                    }
                    "replace" -> {
                        val calendar = prefs.getString("calendar/$scope", null)
                        if (calendar != null) {
                            check(allowed()) { "Calendar access has been revoked" }
                            check(calendars().any { it["id"] == calendar }) { "The connected calendar is no longer writable" }
                            @Suppress("UNCHECKED_CAST")
                            val events = args["events"] as? List<Map<String, Any?>> ?: emptyList()
                            reconcile(scope, calendar.toLong(), events)
                        }
                        null
                    }
                    else -> throw IllegalArgumentException("Unknown calendar method")
                }
                activity.runOnUiThread { result.success(value) }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("calendar_sync", e.message ?: "Calendar unavailable", null) }
            }
        }
    }
    private fun calendars(): List<Map<String, String>> {
        check(allowed()) { "Calendar permission is required" }
        val rows = mutableListOf<Map<String, String>>()
        activity.contentResolver.query(CalendarContract.Calendars.CONTENT_URI,
            arrayOf("_id", "calendar_displayName", "account_name", "calendar_access_level", "sync_events"),
            "calendar_access_level >= ? AND sync_events = 1", arrayOf("500"), "calendar_displayName ASC")?.use { c ->
            while (c.moveToNext()) rows.add(mapOf("id" to c.getLong(0).toString(), "name" to (c.getString(1) ?: "Calendar"), "account" to (c.getString(2) ?: "Device calendar")))
        }
        return rows
    }
    private fun reconcile(scope: String, calendar: Long, events: List<Map<String, Any?>>) {
        val resolver = activity.contentResolver
        val key = "events/$scope/$calendar"
        val saved = JSONObject(prefs.getString(key, "{}") ?: "{}")
        val marker = "[OrchardAtlas:$scope]"
        val desired = events.associateBy { it["id"] as String }
        // Persist each mutation so a process interruption is safely retried.
        fun remember() { check(prefs.edit().putString(key, saved.toString()).commit()) { "Could not save calendar sync state" } }
        fun owned(id: Long): Boolean {
            resolver.query(ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, id),
                arrayOf("calendar_id", "description", "deleted"), null, null, null)?.use { c ->
                return c.moveToFirst() && c.getLong(0) == calendar && c.getString(1).orEmpty().contains(marker) && c.getInt(2) == 0
            }
            return false
        }
        for (id in saved.keys().asSequence().toList()) {
            if (!desired.containsKey(id)) {
                val eventId = saved.getLong(id)
                if (owned(eventId)) resolver.delete(ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, eventId), null, null)
                saved.remove(id); remember()
            }
        }
        for ((id, row) in desired) {
            val values = ContentValues().apply {
                put(CalendarContract.Events.CALENDAR_ID, calendar)
                put(CalendarContract.Events.TITLE, row["title"] as String)
                put(CalendarContract.Events.DESCRIPTION, (row["description"] as String) + "\n" + marker + "\n" + "$marker/$id")
                put(CalendarContract.Events.DTSTART, (row["start"] as Number).toLong())
                put(CalendarContract.Events.DTEND, (row["end"] as Number).toLong())
                put(CalendarContract.Events.EVENT_TIMEZONE, "UTC")
                put(CalendarContract.Events.ALL_DAY, 1)
                put(CalendarContract.Events.HAS_ALARM, 0)
            }
            val previous = if (saved.has(id)) saved.getLong(id) else null
            if (previous != null && owned(previous)) {
                if (prefs.getString("signature/$scope/$id", null) == values.toString()) continue
                resolver.update(ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, previous), values, null, null)
            } else {
                // Recover an insert whose ID was not persisted before process death.
                val description = (row["description"] as String) + "\n" + marker
                val eventMarker = "$marker/$id"
                values.put(CalendarContract.Events.DESCRIPTION, description + "\n" + eventMarker)
                var recovered: Long? = null
                resolver.query(CalendarContract.Events.CONTENT_URI, arrayOf("_id"), "calendar_id=? AND description LIKE ? AND deleted=0", arrayOf(calendar.toString(), "%$eventMarker"), null)?.use { c ->
                    if (c.moveToFirst()) recovered = c.getLong(0)
                }
                val eventId = recovered ?: ContentUris.parseId(checkNotNull(resolver.insert(CalendarContract.Events.CONTENT_URI, values)))
                saved.put(id, eventId); remember()
            }
            prefs.edit().putString("signature/$scope/$id", values.toString()).commit()
        }
    }
}
