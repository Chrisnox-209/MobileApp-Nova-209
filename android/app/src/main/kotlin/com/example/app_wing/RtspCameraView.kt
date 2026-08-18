package com.example.app_wing

import android.content.Context
import android.view.SurfaceHolder
import android.view.View
import com.pedro.rtplibrary.view.OpenGlView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.platform.PlatformView

class RtspCameraView(
    private val context: Context,
    messenger: BinaryMessenger,
    id: Int
) : PlatformView, SurfaceHolder.Callback {

    private val openGlView: OpenGlView = OpenGlView(context)

    init {
        openGlView.holder.addCallback(this)
    }

    override fun getView(): View {
        return openGlView
    }

    override fun dispose() {
        // We do not stop the stream! We just detach the view
        StreamManager.detachView(context)
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        StreamManager.attachView(openGlView)
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        StreamManager.detachView(context)
    }
}
