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
    _player = Player(
        configuration: PlayerConfiguration(
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
  late StreamSubscription? _subscription;
  late StreamSubscription? _errorSubscription;

  @override
  Future<void> init() async {
    if (isHttpBasedUrl(videoUrl)) {
      await _player.open(Media(videoUrl), play: false);
    } else {
      await _player.open(Media('file://$videoUrl'), play: false);
    }
    
    _initialized = true;
  }

  @override
  void addListener(VoidCallback callback) {
    _subscription = _player.stream.completed.listen((event) {
      callback();
    });

    _errorSubscription = _player.stream.error.listen((event) {
      _hasError = event.isNotEmpty;
      callback();
    });
  }

  @override
  void removeListener(VoidCallback callback) {
    _subscription?.cancel();
    _errorSubscription?.cancel();
  }

  @override
  double get aspectRatio => _player.state.videoParams.aspect ?? 16.0 / 9.0;

  @override
  void dispose() {
    //_videoController.dispose();
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
  double get aspectRatio => _controller!.value.aspectRatio;
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
      {required this.videoUrl, required this.navigatorObserver, super.key,
      this.allowPlay = true,
      this.autoPlay = false});
  final String videoUrl;
  final bool allowPlay;
  final bool autoPlay;
  final StreamController navigatorObserver;
  @override
  State<StatefulWidget> createState() => _RemoteVideoState();
}

class _RemoteVideoState extends State<RemoteVideo> with WidgetsBindingObserver {
  late MyVideoController _videoController;
  bool _hasError = false;
  StreamSubscription? _subscription;
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _subscription = widget.navigatorObserver.stream.listen((event) {
      if (_videoController.isPlaying) {
        _videoController.pause();
        if (mounted) {
          setState(() {});
        }
      }
    });
    if (Platform.isAndroid || Platform.isIOS) {
      _videoController = PlatformVideoController(widget.videoUrl);
    } else {
      _videoController = MediaKitVideoController(videoUrl: widget.videoUrl);
    }

    _videoController.addListener(update);
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
    if (_videoController.isCompleted) {
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (_videoController.isPlaying) {
      _videoController.stop();
    }
    _videoController..removeListener(update)
    ..dispose();

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
        ? LayoutBuilder(
            builder: (context, constraints) {
            return Container(
                width: constraints.maxHeight!=double.infinity? constraints.maxHeight * _videoController.aspectRatio:constraints.maxWidth,
                height: constraints.maxWidth!=double.infinity? constraints.maxWidth / _videoController.aspectRatio:constraints.maxHeight,
                color: Colors.transparent,
                child: Center(
                    child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AspectRatio(
                      aspectRatio: _videoController.aspectRatio,
                      child: FittedBox(
                        child: SizedBox(
                            width: _videoController is PlatformVideoController
                                ? _videoController.size.width
                                : (constraints.maxHeight!=double.infinity? constraints.maxHeight * _videoController.aspectRatio:constraints.maxWidth),
                            height: _videoController is PlatformVideoController
                                ? _videoController.size.height
                                : (constraints.maxWidth!=double.infinity? constraints.maxWidth / _videoController.aspectRatio:constraints.maxHeight),
                            child: Stack(
                              alignment: Alignment.bottomCenter,
                              children: [
                                _videoController.videoPlayer,
                                if (_videoController is PlatformVideoController)
                                  Align(
                                      alignment: Alignment.bottomRight,
                                      child: PlayTimeWidget(
                                        controller: _videoController,
                                      )),
                                if (widget.allowPlay)
                                  _videoController.progressIndicator,
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
                          )),
                  ],
                )));
          })
        : LayoutBuilder(
            builder: (context, constraints) {
            return Container(
              width: constraints.maxWidth!=double.infinity?constraints.maxWidth: constraints.maxHeight / (9.0 / 16.0),
              height: constraints.maxHeight!=double.infinity?constraints.maxHeight : constraints.maxWidth/(16.0/9.0),
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
  const _ControlsOverlay({required this.controller, required this.allowPlay});
  final MyVideoController controller;
  final bool allowPlay;

  @override
  State<StatefulWidget> createState() => _ControlsOverlayState();
}

class _ControlsOverlayState extends State<_ControlsOverlay> {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 50),
          reverseDuration: const Duration(milliseconds: 200),
          child: widget.controller.isPlaying
              ? const SizedBox.shrink()
              : const ColoredBox(
                  color: Colors.transparent,
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
            onTap: () {
              if (widget.controller.isPlaying) {
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
    return Text(
      widget.controller.isPlaying
          ? _formatTimeValue(widget.controller.position)
          : _formatTimeValue(widget.controller.duration),
      style: const TextStyle(fontSize: 32, color: Colors.white),
    );
  }
}
