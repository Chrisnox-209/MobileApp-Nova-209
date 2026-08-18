package com.example.app_wing

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        val channel = io.flutter.plugin.common.MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.novawing/stream_manager")
        StreamManager.init(context, channel)
        
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startServer" -> {
                    val bitrate = (call.argument<Double>("bitrate") ?: 1.2) * 1024 * 1024
                    val codecStr = call.argument<String>("codec") ?: "H.265"
                    val resolutionStr = call.argument<String>("resolution") ?: "720p"
                    val fps = call.argument<Int>("fps") ?: 24
                    val token = call.argument<String>("token") ?: ""
                    
                    var width = 1280
                    var height = 720
                    when (resolutionStr) {
                        "480p" -> { width = 854; height = 480 }
                        "720p" -> { width = 1280; height = 720 }
                        "1080p" -> { width = 1920; height = 1080 }
                    }
                    
                    StreamManager.startServer(context, width, height, fps, bitrate.toInt(), codecStr, token)
                    result.success(true)
                }
                "stopServer" -> {
                    StreamManager.stopServer()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "rtsp_camera_view",
            RtspCameraFactory(flutterEngine.dartExecutor.binaryMessenger)
        )
    }
}
