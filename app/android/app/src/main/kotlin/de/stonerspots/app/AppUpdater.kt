package de.stonerspots.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Hands a downloaded update to the system package installer
 * (`lib/features/updater/installer.dart`). The Dart side has already checked
 * the APK against the signed checksums; Android checks that it is signed with
 * the installed app's key and asks the user to confirm.
 */
class AppUpdater(private val activity: Activity) : MethodChannel.MethodCallHandler {
    // Only files in the cache folder the FileProvider shares (xml/updater_paths.xml).
    private fun updatesDir() = File(activity.cacheDir, "updates").canonicalFile

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "canInstall" -> result.success(
                Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                    activity.packageManager.canRequestPackageInstalls(),
            )
            "openInstallSettings" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    activity.startActivity(
                        Intent(
                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:${activity.packageName}"),
                        ),
                    )
                }
                result.success(null)
            }
            "install" -> {
                val file = File(call.arguments as String).canonicalFile
                if (file.parentFile != updatesDir() || !file.name.endsWith(".apk") || !file.isFile) {
                    result.error("bad_path", "not a downloaded update", null)
                    return
                }
                val uri = FileProvider.getUriForFile(
                    activity,
                    "${activity.packageName}.updater",
                    file,
                )
                val intent = Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, "application/vnd.android.package-archive")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                try {
                    activity.startActivity(intent)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("no_installer", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }
}

/** Its own class, so it never clashes with a plugin's FileProvider entry. */
class UpdateFileProvider : FileProvider()
