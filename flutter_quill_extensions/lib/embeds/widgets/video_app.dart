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
  OverlayEntry? _overlayEntry;
  bool _isFullScreen = false;
  Rect? _widgetRect;

  void _getWidgetRect() {
    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    _widgetRect = offset & renderBox.size;
  }

  void _showFullScreen() {
    _getWidgetRect();
    _overlayEntry = _createOverlayEntry(child: videoPlayer);
    Overlay.of(context).insert(_overlayEntry!);
    setState(() {
      _isFullScreen = true;
    });
  }

  void _closeFullScreen() {
    _overlayEntry?.remove();
    setState(() {
      _isFullScreen = false;
    });
  }

  OverlayEntry _createOverlayEntry({required Widget child}) {
    return OverlayEntry(
      builder: (context) => AnimatedPositioned(
        duration: const Duration(milliseconds: 200),
        top: _isFullScreen ? 0 : _widgetRect!.top,
        left: _isFullScreen ? 0 : _widgetRect!.left,
        width: _isFullScreen
            ? MediaQuery.of(context).size.width
            : _widgetRect!.width,
        height: _isFullScreen
            ? MediaQuery.of(context).size.height
            : _widgetRect!.height,
        child: Material(
          color: Colors.transparent,
          child: child,
        ),
      ),
    );
  }

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

  Widget get videoPlayer => Container(
      color: Colors.black,
      child: Center(
          child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      VideoPlayer(_controller!),
                      Align(
                          alignment: Alignment.bottomRight,
                          child: PlayTimeWidget(
                            controller: _controller!,
                          )),
                      VideoProgressIndicator(_controller!,
                          allowScrubbing: true),
                    ],
                  )),
            ),
          ),
          AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: _ControlsOverlay(
                onDoubleTap: () {
                  if (!_isFullScreen) {
                    _showFullScreen();
                  } else {
                    _closeFullScreen();
                  }
                },
                controller: _controller!,
                allowPlay: true,
              )),
        ],
      )));

  // Widget get videoPlayer => Container(
  //       // key: videoContainerKey,
  //       child: GestureDetector(
  //         onDoubleTap: () {
  //           if (!_isFullScreen) {
  //             _showFullScreen();
  //           } else {
  //             _closeFullScreen();
  //           }
  //         },
  //         onTap: () {
  //           setState(() {
  //             _controller!.value.isPlaying
  //                 ? _controller!.pause()
  //                 : _controller!.play();
  //           });
  //         },
  //         child: Stack(alignment: Alignment.center, children: [
  //           Center(
  //               child: AspectRatio(
  //             aspectRatio: _controller!.value.aspectRatio,
  //             child: VideoPlayer(_controller!),
  //           )),
  //           _controller!.value.isPlaying
  //               ? const SizedBox.shrink()
  //               : const SizedBox(
  //                   child: Icon(
  //                   Icons.play_arrow,
  //                   size: 40,
  //                   color: Colors.white,
  //                 ))
  //         ]),
  //       ),
  //     );

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
      return LayoutBuilder(builder: (context, constraints) {
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
      return _isFullScreen ? Container() : videoPlayer;
    }
  }

  @override
  void dispose() {
    super.dispose();
    _controller?.dispose();
  }
}

class _ControlsOverlay extends StatefulWidget {
  const _ControlsOverlay(
      {required this.controller,
      required this.allowPlay,
      required this.onDoubleTap});
  final VideoPlayerController controller;
  final GestureTapCallback? onDoubleTap;
  final bool allowPlay;

  @override
  State<StatefulWidget> createState() => _ControlsOverlayState();
}

class _ControlsOverlayState extends State<_ControlsOverlay> {
  @override
  void initState() {
    widget.controller.addListener(update);
    super.initState();
  }

  void update() {
    if (widget.controller.value.isCompleted) {
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(update);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 50),
          reverseDuration: const Duration(milliseconds: 200),
          child: widget.controller.value.isPlaying
              ? const SizedBox.shrink()
              : const ColoredBox(
                  color: Colors.black12,
                  child: Center(
                    child: Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),
        ),
        if (widget.allowPlay)
          GestureDetector(
            onDoubleTap: widget.onDoubleTap,
            onTap: () {
              if (widget.controller.value.isPlaying) {
                widget.controller.pause().then((_) => setState(() {}));
              } else {
                widget.controller.play().then((_) => setState(() {}));
              }
            },
          ),
      ],
    );
  }
}

extension FormatTime on Duration {
  String formatTimeValue() {
    final timeString = '$this';
    return timeString.substring(0, timeString.indexOf('.'));
  }
}

class PlayTimeWidget extends StatefulWidget {
  const PlayTimeWidget({required this.controller, super.key});
  final VideoPlayerController controller;

  @override
  State<StatefulWidget> createState() => _PlayTimeWidgetState();
}

class _PlayTimeWidgetState extends State<PlayTimeWidget> {
  @override
  void initState() {
    widget.controller.addListener(update);
    super.initState();
  }

  void update() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(update);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      widget.controller.value.isPlaying
          ? widget.controller.value.position.formatTimeValue()
          : widget.controller.value.duration.formatTimeValue(),
      style: const TextStyle(fontSize: 32, color: Colors.white),
    );
  }
}

