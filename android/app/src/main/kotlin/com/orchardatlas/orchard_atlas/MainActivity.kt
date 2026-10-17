package com.orchardatlas.orchard_atlas

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.pm.PackageManager
import android.location.Geocoder
import android.os.Build
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import java.util.Locale

class MainActivity : FlutterActivity() {
    private lateinit var backupChannel: BackupChannel
    @Deprecated("Used by Android document providers on supported trial phones")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        if (::backupChannel.isInitialized && backupChannel.onActivityResult(requestCode, resultCode, data)) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onResume() {
        super.onResume()
        window.decorView.post { hideNavigationBar() }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideNavigationBar()
    }

    @Suppress("DEPRECATION")
    private fun hideNavigationBar() {
        // Use native insets as well as Flutter's UI mode for recent edge-to-edge SDKs.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.apply {
                systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                hide(WindowInsets.Type.navigationBars())
            }
        } else {
            window.decorView.systemUiVisibility = window.decorView.systemUiVisibility or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        backupChannel = BackupChannel(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "orchard_atlas/backup").setMethodCallHandler(backupChannel)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "orchard_atlas/map_services")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "mapsConfigured" -> {
                        val info = packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
                        val key = info.metaData?.getString("com.google.android.geo.API_KEY").orEmpty()
                        result.success(key.isNotBlank() && !key.startsWith("\${"))
                    }
                    "searchAddress" -> {
                        val query = call.argument<String>("query").orEmpty().trim()
                        if (query.isEmpty() || query.length > 500) {
                            result.error("invalid_query", "Enter an address", null)
                        } else if (!Geocoder.isPresent()) {
                            result.error("unavailable", "Address lookup is unavailable on this device", null)
                        } else {
                            // The legacy API also supports pre-Android 13 trial phones.
                            Thread {
                                try {
                                    @Suppress("DEPRECATION")
                                    val addresses = Geocoder(this, Locale.getDefault()).getFromLocationName(query, 5).orEmpty()
                                    val matches = addresses.filter { it.hasLatitude() && it.hasLongitude() }.map {
                                        mapOf("label" to (it.getAddressLine(0) ?: query),
                                            "latitude" to it.latitude, "longitude" to it.longitude)
                                    }
                                    runOnUiThread { result.success(matches) }
                                } catch (_: Exception) {
                                    runOnUiThread { result.error("lookup_failed", "Address lookup failed. Check your connection or use coordinates.", null) }
                                }
                            }.start()
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
