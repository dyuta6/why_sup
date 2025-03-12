package com.example.why_sup

import android.app.AppOpsManager
import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.os.Build
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.*

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.why_sup/usage_stats"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCurrentApp" -> {
                    if (checkUsageStatsPermission()) {
                        val currentApp = getCurrentApp()
                        result.success(currentApp)
                    } else {
                        result.error("PERMISSION_DENIED", "Usage Stats permission is required.", null)
                    }
                }
                "checkUsageStatsPermission" -> {
                    result.success(checkUsageStatsPermission())
                }
                "openAppSettings" -> {
                    openAppSettings()
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun checkUsageStatsPermission(): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        
        // İzin durumunu kontrol et
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName
            )
        } else {
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName
            )
        }

        // Eğer izin verilmemişse, son 24 saat içindeki kullanım istatistiklerini kontrol et
        if (mode != AppOpsManager.MODE_ALLOWED) {
            val usageStatsManager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val time = System.currentTimeMillis()
            val stats = usageStatsManager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                time - 1000 * 60 * 60 * 24,
                time
            )
            return !stats.isEmpty()
        }

        return true
    }

    private fun getCurrentApp(): Map<String, String?> {
        try {
            val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val time = System.currentTimeMillis()
            val stats = usageStatsManager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                time - 1000 * 1000, // Son 1000 saniye
                time
            )

            if (stats != null) {
                val packageManager = packageManager
                var lastUsedApp: UsageStats? = null
                var lastTimeUsed: Long = 0
                
                // Özel olarak dahil edilecek popüler uygulama paket adları
                val whitelistedPackages = setOf(
                    "com.android.chrome",           // Chrome
                    "com.google.android.youtube",   // YouTube
                    "com.google.android.gm",        // Gmail
                    "com.google.android.apps.photos", // Google Photos
                    "com.google.android.apps.maps", // Google Maps
                    "com.google.android.apps.youtube.music", // YouTube Music
                    "com.facebook.katana",          // Facebook
                    "com.instagram.android",        // Instagram
                    "com.whatsapp",                 // WhatsApp
                    "com.twitter.android",          // Twitter
                    "com.spotify.music",            // Spotify
                    "com.netflix.mediaclient",      // Netflix
                    "com.amazon.avod.thirdpartyclient" // Prime Video
                )

                for (usageStats in stats) {
                    try {
                        val packageName = usageStats.packageName
                        
                        // Paketi debug için logla
                        android.util.Log.d("WhySup", "Checking package: $packageName")
                        
                        // Sistem uygulaması mı kontrol et
                        val applicationInfo = packageManager.getApplicationInfo(packageName, 0)
                        val isSystemApp = applicationInfo.flags and ApplicationInfo.FLAG_SYSTEM != 0
                        
                        // Whitelist kontrolü
                        val isWhitelisted = packageName in whitelistedPackages
                        
                        // Debug için logla
                        if (isSystemApp) {
                            android.util.Log.d("WhySup", "System app: $packageName")
                        }
                        if (isWhitelisted) {
                            android.util.Log.d("WhySup", "Whitelisted app: $packageName")
                        }
                        
                        // Whitelist'teki uygulamalar her zaman dahil edilir veya sistem uygulaması değilse dahil edilir
                        if ((isWhitelisted || !isSystemApp) && usageStats.lastTimeUsed > lastTimeUsed) {
                            lastTimeUsed = usageStats.lastTimeUsed
                            lastUsedApp = usageStats
                            android.util.Log.d("WhySup", "Selected app: $packageName, time: $lastTimeUsed")
                        }
                    } catch (e: Exception) {
                        android.util.Log.e("WhySup", "Error processing package: ${e.message}")
                        continue
                    }
                }

                if (lastUsedApp != null) {
                    try {
                        val packageName = lastUsedApp.packageName
                        val packageInfo = packageManager.getApplicationInfo(packageName, 0)
                        val appName = packageManager.getApplicationLabel(packageInfo).toString()
                        android.util.Log.d("WhySup", "Returning app: $appName ($packageName)")
                        
                        // Hem uygulama adını hem de paket adını döndür
                        return mapOf(
                            "appName" to appName,
                            "packageName" to packageName
                        )
                    } catch (e: Exception) {
                        android.util.Log.e("WhySup", "Error getting app name: ${e.message}")
                    }
                } else {
                    android.util.Log.d("WhySup", "No app selected")
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("WhySup", "General error: ${e.message}")
        }
        return mapOf(
            "appName" to null,
            "packageName" to null
        )
    }

    private fun openAppSettings() {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
        startActivity(intent)
    }
}
