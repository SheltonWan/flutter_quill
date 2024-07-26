import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player/video_player.dart';

import '../../utils/utils.dart';

abstract class MyVideoController {
  bool get isPlaying;
  bool get hasError;
  bool get isCompleted;
  bool get isInitialized;
  double get aspectRatio;
  Size get size;
  Duration get position;
  Duration get duration;

  Widget get videoPlayer;
  Widget get progressIndicator;

  Future<void> pause();
  Future<void> play();
  Future<void> stop();

  Future<void> init();
  void dispose();

  void addListener(VoidCallback callback);
  void removeListener(VoidCallback callback);
}

class MediaKitVideoController extends MyVideoController {
  MediaKitVideoController({required this.videoUrl}) {
    _player = Player(configuration: PlayerConfiguration(
      ready: () {
        _videoController = VideoController(_player);
      },
    ));
  }
  late Player _player;
  late VideoController _videoController;
  final String videoUrl;
  bool _initialized = false;
  bool _hasError = false;
  late StreamSubscription? _completedSubscription;
  late StreamSubscription? _errorSubscription;

  @override
  Future<void> init() async {
    if (isHttpBasedUrl(videoUrl)) {
      await _player.open(Media(videoUrl), play: false);
    } else {
      await _player.open(Media('file://$videoUrl'), play: false);
    }

    // Completer videoInitCompleter = Completer<bool>();

    // final videoSubscription = _player.stream.videoParams.listen((event) {
    //   videoInitCompleter.complete(true);
    // });

    // _initialized = await videoInitCompleter.future;
    // videoSubscription?.cancel();
    _initialized = true;
  }

  @override
  void addListener(VoidCallback callback) {
    _completedSubscription = _player.stream.completed.listen((event) {
      callback();
    });

    _errorSubscription = _player.stream.error.listen((event) {
      _hasError = event.isNotEmpty;
      callback();
    });
  }

  @override
  void removeListener(VoidCallback callback) {
    _completedSubscription?.cancel();
    _errorSubscription?.cancel();
  }

  ///因为有 控制器 大小限制，所以不能由原始比例控制，否则越界
  @override
  double get aspectRatio => /*_player.state.videoParams.aspect ??*/ 16.0 / 9.0;

  @override
  void dispose() {
    _player.dispose();
  }

  @override
  Duration get duration => _player.state.duration;

  @override
  bool get hasError => _hasError;

  @override
  bool get isCompleted => _player.state.completed;

  @override
  bool get isInitialized => _initialized;

  @override
  bool get isPlaying => _player.state.playing;

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> play() async {
    await _player.play();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
  }

  @override
  Duration get position => _player.state.position;

  @override
  Widget get progressIndicator => Container();

  @override
  Size get size => Size(_player.state.width?.toDouble() ?? 0,
      _player.state.height?.toDouble() ?? 0);

  @override
  Widget get videoPlayer => Video(controller: _videoController);
}

//支持ios、Android、macos
class PlatformVideoController extends MyVideoController {
  PlatformVideoController(String videoUrl) {
    if (!isHttpBasedUrl(videoUrl)) {
      final file = File(videoUrl);
      _controller = VideoPlayerController.file(file);
    } else {
      try {
        _controller = VideoPlayerController.networkUrl(
          Uri.parse(videoUrl),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
      } catch (e) {
        if (kDebugMode) {
          print(e.toString());
        }
      }
    }

    _controller?.setLooping(false);
  }
  VideoPlayerController? _controller;
  @override
  bool get isPlaying => _controller != null && _controller!.value.isPlaying;
  @override
  bool get hasError => _controller != null && _controller!.value.hasError;
  @override
  bool get isCompleted => _controller != null && _controller!.value.isCompleted;
  @override
  bool get isInitialized =>
      _controller != null && _controller!.value.isInitialized;
  @override
  double get aspectRatio =>
      isInitialized ? _controller!.value.aspectRatio : 16.0 / 9.0;
  @override
  Size get size => _controller!.value.size;
  @override
  Duration get position => _controller!.value.position;
  @override
  Duration get duration => _controller!.value.duration;

  @override
  Widget get videoPlayer => VideoPlayer(_controller!);
  @override
  Widget get progressIndicator => VideoProgressIndicator(_controller!,
      colors: const VideoProgressColors(playedColor: Colors.white),
      allowScrubbing: true);

  @override
  Future<void> pause() async => await _controller!.pause();
  @override
  Future<void> play() async => await _controller!.play();
  @override
  Future<void> stop() async {
    await _controller!.pause();
  }

  @override
  void addListener(VoidCallback callback) {
    _controller?.addListener(callback);
  }

  @override
  void removeListener(VoidCallback callback) {
    _controller?.removeListener(callback);
  }

  @override
  Future<void> init() async {
    try {
      await _controller?.initialize();
    } catch (e) {
      if (kDebugMode) {
        print(e.toString());
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
  }
}

class RemoteVideo extends StatefulWidget {
  const RemoteVideo(
      {required this.videoUrl,
      required this.navigatorObserver,
      super.key,
      this.allowPlay = true,
      this.autoPlay = false,
      this.useMediaKit = false,
      this.fullPlay = false});
  final String videoUrl;
  final bool allowPlay;
  final bool autoPlay;
  final bool useMediaKit;
  final bool fullPlay;
  final StreamController navigatorObserver;
  @override
  State<StatefulWidget> createState() => _RemoteVideoState();
}

class _RemoteVideoState extends State<RemoteVideo> with WidgetsBindingObserver {
  late MyVideoController _videoController;
  bool _hasError = false;
  StreamSubscription? _subscription;

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

    _overlayEntry = _createOverlayEntry(child: _videoWidget);
    Overlay.of(context).insert(_overlayEntry!);
    _isFullScreen = true;
    if (mounted) {
      setState(() {});
    }
  }

  void _closeFullScreen() {
    _overlayEntry?.remove();
    _isFullScreen = false;
    if (mounted) {
      setState(() {});
    }
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
        child: Container(
          color: Colors.black,
          child: child,
        ),
      ),
    );
  }

  Widget get _videoWidget => LayoutBuilder(builder: (context, constraints) {
        var width = MediaQuery.of(context).size.width;
        var height = width / _videoController.aspectRatio;
        if (constraints.maxHeight != double.infinity) {
          height = constraints.maxHeight;
          width = height * _videoController.aspectRatio;
        } else if (constraints.maxWidth != double.infinity) {
          width = constraints.maxWidth;
          height = width / _videoController.aspectRatio;
        }
        return Container(
            width: width,
            height: height,
            color: Colors.transparent,
            child: Center(
                child: Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: _videoController.aspectRatio,
                  child: FittedBox(
                    child: SizedBox(
                        width: width,
                        height: height,
                        child: Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            _videoController.videoPlayer,
                          ],
                        )),
                  ),
                ),
                if (_videoController is PlatformVideoController)
                  AspectRatio(
                      aspectRatio: _videoController.aspectRatio,
                      child: _ControlsOverlay(
                        controller: _videoController,
                        allowPlay: widget.allowPlay,
                        isFull: _isFullScreen,
                        fullPlay: widget.fullPlay,
                        onFullScreenTap: () {
                          if (!_isFullScreen) {
                            _showFullScreen();
                          } else {
                            _closeFullScreen();
                          }
                        },
                      )),
              ],
            )));
      });

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      print('initState ${widget.videoUrl}');
    }
    WidgetsBinding.instance.addObserver(this);

    _subscription = widget.navigatorObserver.stream.listen((event) {
      if (_videoController.isPlaying) {
        _videoController.pause();
        if (mounted) {
          setState(() {});
        }
      }
    });
    if (!widget.useMediaKit) {
      _videoController = PlatformVideoController(widget.videoUrl);
    } else {
      _videoController = MediaKitVideoController(videoUrl: widget.videoUrl);
    }

    if (widget.useMediaKit) {
      _videoController.addListener(update);
    }

    try {
      _videoController.init().then((_) {
        if (widget.autoPlay) {
          _videoController.play();
        }
        if (mounted) {
          setState(() {
            _hasError = _videoController.hasError;
          });
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  void update() {
    setState(() {});
  }

  @override
  void dispose() {
    if (kDebugMode) {
      print('dispose ${widget.videoUrl}');
    }
    if (widget.useMediaKit) {
      _videoController.removeListener(update);
    }
    _subscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (_videoController.isPlaying) {
      _videoController.stop();
    }
    _videoController.dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 处理应用生命周期变化事件
    switch (state) {
      case AppLifecycleState.resumed:
        // 应用进入前台
        break;
      case AppLifecycleState.inactive:
        // 应用进入非活跃状态，例如来电、弹窗等情况
        break;
      case AppLifecycleState.paused:

        // 应用进入后台
        //进入后台后，程序会被系统挂起，心跳信息是无法发送的
        if (_videoController.isPlaying) {
          _videoController.pause();
          if (mounted) {
            setState(() {});
          }
        }
        break;
      case AppLifecycleState.detached:
        // 应用被挂起
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }

  bool get _videoInitialized => _videoController.isInitialized;
  @override
  Widget build(BuildContext context) {
    return _videoInitialized
        ? (_isFullScreen ? Container() : _videoWidget)
        : LayoutBuilder(builder: (context, constraints) {
            var width = MediaQuery.of(context).size.width;
            var height = width / _videoController.aspectRatio;
            if (constraints.maxHeight != double.infinity) {
              height = constraints.maxHeight;
              width = height * _videoController.aspectRatio;
            } else if (constraints.maxWidth != double.infinity) {
              width = constraints.maxWidth;
              height = width / _videoController.aspectRatio;
            }
            return Container(
              width: width,
              height: height,
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
  }
}

class _ControlsOverlay extends StatefulWidget {
  const _ControlsOverlay(
      {required this.controller,
      required this.allowPlay,
      required this.onFullScreenTap,
      required this.isFull,
      required this.fullPlay});
  final MyVideoController controller;
  final bool allowPlay;
  final bool isFull;
  final bool fullPlay;
  final GestureTapCallback? onFullScreenTap;

  @override
  State<StatefulWidget> createState() => _ControlsOverlayState();
}

class _ControlsOverlayState extends State<_ControlsOverlay> {
  bool _showPannel = false;
  DateTime? _tapTime;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(update);
  }

  @override
  void dispose() {
    widget.controller.removeListener(update);
    super.dispose();
  }

  void update() {
    if (widget.controller.isCompleted) {
      if (mounted) {
        setState(() {});
      }
    }
  }

  void tryHide() {
    final now = DateTime.now();
    final diff = now.difference(_tapTime!);
    if (diff.inSeconds >= 5) {
      if (mounted) {
        setState(() {
          _showPannel = false;
        });
      }
    } else {
      final duration =
          _tapTime!.add(const Duration(seconds: 5)).difference(now);
      Future.delayed(duration, tryHide);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 50),
          reverseDuration: const Duration(milliseconds: 200),
          child: widget.controller.isPlaying
              ? const SizedBox.shrink()
              : ColoredBox(
                  color: Colors.transparent,
                  child: Center(
                    child: Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black38,
                        ),
                        width: 40,
                        height: 40,
                        child: const Center(
                            child: Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 32,
                        ))),
                  ),
                ),
        ),
        if (widget.allowPlay)
          GestureDetector(
            onTap: () {
              _tapTime = DateTime.now();
              if (!widget.isFull && widget.fullPlay) {
                widget.onFullScreenTap!();
              }
              if (!_showPannel) {
                if (mounted) {
                  setState(() {
                    _showPannel = true;
                  });
                }

                Future.delayed(const Duration(seconds: 5), tryHide);
              }

              if (widget.controller.isPlaying) {
                widget.controller.pause().then((_) {
                  if (mounted) {
                    setState(() {});
                  }
                });
              } else {
                widget.controller.play().then((_) {
                  if (mounted) {
                    setState(() {});
                  }
                });
              }
            },
          ),
        if (widget.allowPlay && _showPannel)
          Align(
            alignment: Alignment.bottomCenter,
            child: Row(children: [
              PlayTimeWidget(
                controller: widget.controller,
              ),
              Expanded(child: widget.controller.progressIndicator),
              const SizedBox(width: 8),
              GestureDetector(
                  onTap: () {
                    widget.onFullScreenTap!();
                    if (widget.isFull &&
                        widget.fullPlay &&
                        widget.controller.isPlaying) {
                      widget.controller.pause().then((_) {
                        if (mounted) {
                          setState(() {});
                        }
                      });
                    }
                  },
                  child: Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black38,
                      ),
                      width: 32,
                      height: 32,
                      child: Center(
                          child: Icon(
                        widget.isFull
                            ? Icons.fullscreen_exit
                            : Icons.fullscreen,
                        color: Colors.white,
                        size: 32,
                      )))),
              const SizedBox(width: 16),
            ]),
          ),
      ],
    );
  }
}

class PlayTimeWidget extends StatefulWidget {
  const PlayTimeWidget({required this.controller, super.key});
  final MyVideoController controller;

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

  String _formatTimeValue(Duration duration) {
    final timeString = '$duration';
    return timeString.substring(0, timeString.indexOf('.'));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        padding: const EdgeInsets.only(left: 20, right: 20),
        child: Text(
          _formatTimeValue(
              widget.controller.duration - widget.controller.position),
          style: const TextStyle(fontSize: 16, color: Colors.white),
        ));
  }
}
