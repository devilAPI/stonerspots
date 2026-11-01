package de.stonerspots.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "de.stonerspots.app/home_widget")
            .setMethodCallHandler { call, result ->
                if (call.method == "update") {
                    NearestSpotWidget.save(this, call.arguments as String)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
