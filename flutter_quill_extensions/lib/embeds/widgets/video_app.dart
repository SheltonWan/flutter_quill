import 'dart:io' show File;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../flutter_quill_extensions.dart';

/// Widget for playing back video
/// Refer to https://github.com/flutter/plugins/tree/master/packages/video_player/video_player
class VideoApp extends StatefulWidget {
  const VideoApp(
      {required this.videoUrl,
      required this.context,
      required this.readOnly,
      super.key,
      this.onVideoInit,
      this.onCacheVideoProvider});

  final String videoUrl;
  final BuildContext context;
  final bool readOnly;
  final void Function(GlobalKey videoContainerKey)? onVideoInit;
  final Future<String> Function(String)? onCacheVideoProvider;

  @override
  VideoAppState createState() => VideoAppState();
}

class VideoAppState extends State<VideoApp> {
  VideoPlayerController? _controller;
  GlobalKey videoContainerKey = GlobalKey();
  bool _hasError = false;

  @override
  void initState() {
    super.initState();

    if (widget.onCacheVideoProvider != null) {
      widget.onCacheVideoProvider!(widget.videoUrl).then((newUrl) {
        final file = File(newUrl);
        if (!file.existsSync()) {
          if (mounted) {
            setState(() {
              _hasError = true;
            });
          }

          return;
        }
        _controller = VideoPlayerController.file(file);

        _controller?.setLooping(false);
        _controller?.initialize().then((_) {
          _hasError = _controller!.value.hasError;
          setState(() {});
        }).catchError((err) {
          _hasError = true;
          setState(() {});
        });
      });
    } else {
      _controller = isHttpBasedUrl(widget.videoUrl)
          ? VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
          : VideoPlayerController.file(File(widget.videoUrl))
        ..initialize().then((_) {
          // Ensure the first frame is shown after the video is initialized,
          // even before the play button has been pressed.
          setState(() {});
          if (widget.onVideoInit != null) {
            widget.onVideoInit?.call(videoContainerKey);
          }
        }).catchError((error) {
          setState(() {});
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultStyles = DefaultStyles.getInstance(context);
    if (_hasError) {
      if (widget.readOnly) {
        return RichText(
          text: TextSpan(
            text: widget.videoUrl,
            style: defaultStyles.link,
            recognizer: TapGestureRecognizer()
              ..onTap = () => launchUrl(
                    Uri.parse(widget.videoUrl),
                  ),
          ),
        );
      }

      return RichText(
        text: TextSpan(
          text: widget.videoUrl,
          style: defaultStyles.link,
        ),
      );
    } else if (_controller == null ||
        (_controller != null && !_controller!.value.isInitialized)) {
      return LayoutBuilder(
          builder: (context, constraints) {
        return Container(
          height: constraints.maxWidth * 9.0 / 16.0,
          color: Colors.black,
          child: Center(
              child: _hasError
                  ? const Icon(
                      Icons.heart_broken,
                      color: Colors.white,
                    )
                  : const CircularProgressIndicator(
                      color: Colors.white,
                    )),
        );
      });
    } else {
    return Container(
      key: videoContainerKey,
      child: InkWell(
        onTap: () {
          setState(() {
              _controller!.value.isPlaying
                  ? _controller!.pause()
                  : _controller!.play();
          });
        },
        child: Stack(alignment: Alignment.center, children: [
          Center(
              child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: VideoPlayer(_controller!),
          )),
            _controller!.value.isPlaying
              ? const SizedBox.shrink()
                : const SizedBox(
                    child: Icon(
                    Icons.play_arrow,
                    size: 40,
                    color: Colors.white,
                  ))
        ]),
      ),
    );
    }


  }

  @override
  void dispose() {
    super.dispose();
    _controller?.dispose();
  }
}
