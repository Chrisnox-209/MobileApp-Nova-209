import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RtspCameraWidget extends StatefulWidget {
  final Function(MethodChannel)? onChannelCreated;

  const RtspCameraWidget({Key? key, this.onChannelCreated}) : super(key: key);

  @override
  State<RtspCameraWidget> createState() => _RtspCameraWidgetState();
}

class _RtspCameraWidgetState extends State<RtspCameraWidget> {
  @override
  Widget build(BuildContext context) {
    return AndroidView(
      viewType: 'rtsp_camera_view',
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: (int id) {
        if (widget.onChannelCreated != null) {
          widget.onChannelCreated!(MethodChannel('com.novawing/rtsp_\$id'));
        }
      },
    );
  }
}
