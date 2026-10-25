package com.orchardatlas.orchard_atlas

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class ReminderChannel(private val activity: MainActivity) : MethodChannel.MethodCallHandler {
    private var permission: MethodChannel.Result? = null
    override fun onMethodCall(call: MethodCall,result: MethodChannel.Result) {
        when(call.method) {
            "permission" -> {
                if(Build.VERSION.SDK_INT>=33 && activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED) {
                    if(permission!=null){result.error("busy","Permission request already open",null);return}
                    permission=result;activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS),9402)
                } else result.success(activity.getSystemService(NotificationManager::class.java).areNotificationsEnabled())
            }
            "replace" -> {
                try {
                    val scope=call.argument<String>("orchard") ?: error("No orchard")
                    val records=JSONArray(call.argument<List<Map<String,Any>>>("notifications") ?: emptyList<Map<String,Any>>())
                    ReminderReceiver.replace(activity,scope,records);result.success(null)
                }catch(_:Exception){result.error("reminder_failed","Could not schedule reminders",null)}
            }
            else -> result.notImplemented()
        }
    }
    fun permissionResult(code:Int,grants:IntArray):Boolean {
        if(code!=9402)return false
        permission?.success(grants.isNotEmpty() && grants[0]==PackageManager.PERMISSION_GRANTED);permission=null;return true
    }
}
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context:Context,intent:Intent) {
        if(intent.action==Intent.ACTION_BOOT_COMPLETED || intent.action==Intent.ACTION_MY_PACKAGE_REPLACED) {
            val prefs=context.getSharedPreferences("orchard-reminders",Context.MODE_PRIVATE)
            for((scope,value) in prefs.all) if(value is String) schedule(context,scope,JSONArray(value))
            return
        }
        val title=intent.getStringExtra("title") ?: return
        val manager=context.getSystemService(NotificationManager::class.java)
        if(Build.VERSION.SDK_INT>=26) manager.createNotificationChannel(NotificationChannel("orchard-tasks","Orchard task reminders",NotificationManager.IMPORTANCE_DEFAULT))
        val launch=context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return
        val open=PendingIntent.getActivity(context,0,launch,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder=if(Build.VERSION.SDK_INT>=26)Notification.Builder(context,"orchard-tasks") else Notification.Builder(context)
        try { manager.notify(intent.data.toString().hashCode(),builder.setSmallIcon(android.R.drawable.ic_menu_agenda).setContentTitle(title)
            .setContentText(intent.getStringExtra("body")).setContentIntent(open).setAutoCancel(true).build()) }catch(_:SecurityException){}
    }
    companion object {
        private fun pending(context:Context,scope:String,r:JSONObject):PendingIntent {
            val intent=Intent(context,ReminderReceiver::class.java).apply {
                data=Uri.parse("orchard-reminder://$scope/${r.getString("id")}")
                putExtra("title",r.getString("title"));putExtra("body",r.getString("body"))
            }
            return PendingIntent.getBroadcast(context,0,intent,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        fun replace(context:Context,scope:String,records:JSONArray) {
            val prefs=context.getSharedPreferences("orchard-reminders",Context.MODE_PRIVATE)
            val alarm=context.getSystemService(AlarmManager::class.java)
            val old=JSONArray(prefs.getString(scope,"[]"))
            for(i in 0 until old.length())alarm.cancel(pending(context,scope,old.getJSONObject(i)))
            check(prefs.edit().putString(scope,records.toString()).commit())
            schedule(context,scope,records)
        }
        fun schedule(context:Context,scope:String,records:JSONArray) {
            val alarm=context.getSystemService(AlarmManager::class.java)
            for(i in 0 until records.length()) {
                val r=records.getJSONObject(i);val time=r.getLong("time")
                if(time>System.currentTimeMillis())alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,time,pending(context,scope,r))
            }
        }
    }
}
