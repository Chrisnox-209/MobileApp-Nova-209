package com.example.app_wing

import android.content.Context
import android.util.Log
import com.pedro.encoder.input.video.CameraHelper
import com.pedro.rtsp.rtsp.VideoCodec
import com.pedro.rtsp.utils.ConnectCheckerRtsp
import com.pedro.rtspserver.RtspServerCamera2
import io.flutter.plugin.common.MethodChannel
import com.pedro.rtplibrary.view.OpenGlView

object StreamManager : ConnectCheckerRtsp {
    private const val TAG = "StreamManager"
    var rtspServerCamera2: RtspServerCamera2? = null
    var methodChannel: MethodChannel? = null
    var isStreaming = false

    fun init(context: Context, channel: MethodChannel) {
        methodChannel = channel
        if (rtspServerCamera2 == null) {
            // Initialize headlessly with context, but enable OpenGL so OpenGlView works!
            rtspServerCamera2 = RtspServerCamera2(context, true, this, 8554)
        }
    }

    fun attachView(view: OpenGlView) {
        rtspServerCamera2?.replaceView(view)
        rtspServerCamera2?.startPreview()
    }

    fun detachView(context: Context) {
        rtspServerCamera2?.stopPreview()
        rtspServerCamera2?.replaceView(context)
    }

    fun startServer(context: Context, width: Int, height: Int, fps: Int, bitrate: Int, codecStr: String, token: String) {
        if (rtspServerCamera2?.isStreaming == false) {
            val videoCodec = if (codecStr == "H.265") VideoCodec.H265 else VideoCodec.H264
            rtspServerCamera2?.setVideoCodec(videoCodec)

            if (token.isNotEmpty()) {
                rtspServerCamera2?.setAuthorization("admin", token)
            } else {
                rtspServerCamera2?.setAuthorization("", "")
            }

            val prepared = rtspServerCamera2?.prepareVideo(
                width, height, fps, bitrate, 0, CameraHelper.getCameraOrientation(context)
            ) ?: false

            if (prepared) {
                rtspServerCamera2?.startStream()
                isStreaming = true
            } else {
                methodChannel?.invokeMethod("onConnectionFailed", "Could not prepare video encoder")
            }
        }
    }

    fun stopServer() {
        if (rtspServerCamera2?.isStreaming == true) {
            rtspServerCamera2?.stopStream()
            isStreaming = false
        }
    }

    override fun onAuthErrorRtsp() {
        Log.e(TAG, "onAuthErrorRtsp")
    }
    
    override fun onAuthSuccessRtsp() {
        Log.i(TAG, "onAuthSuccessRtsp")
    }
    
    override fun onConnectionFailedRtsp(reason: String) {
        Log.e(TAG, "onConnectionFailedRtsp: \$reason")
        methodChannel?.invokeMethod("onConnectionFailed", reason)
        stopServer()
    }
    
    override fun onConnectionStartedRtsp(rtspUrl: String) {
        Log.i(TAG, "onConnectionStartedRtsp: \$rtspUrl")
        methodChannel?.invokeMethod("onConnectionStarted", rtspUrl)
    }
    
    override fun onConnectionSuccessRtsp() {
        Log.i(TAG, "onConnectionSuccessRtsp")
        methodChannel?.invokeMethod("onConnectionSuccess", null)
    }
    
    override fun onDisconnectRtsp() {
        Log.i(TAG, "onDisconnectRtsp")
        methodChannel?.invokeMethod("onDisconnect", null)
        isStreaming = false
    }
    
    override fun onNewBitrateRtsp(bitrate: Long) {
        Log.i(TAG, "onNewBitrateRtsp: \$bitrate")
    }
}
