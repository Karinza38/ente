import "dart:async";
import "dart:io";

import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:media_kit/media_kit.dart";
import "package:media_kit_video/media_kit_video.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/guest_view_event.dart";
import "package:photos/events/pause_video_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/models/file/file.dart";
import "package:photos/services/files_service.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";
import "package:photos/utils/debouncer.dart";
import "package:photos/utils/dialog_util.dart";
import "package:photos/utils/file_util.dart";
import "package:photos/utils/toast_util.dart";

class VideoWidgetMediaKitNew extends StatefulWidget {
  final EnteFile file;
  final String? tagPrefix;
  final Function(bool)? playbackCallback;
  final bool isFromMemories;
  const VideoWidgetMediaKitNew(
    this.file, {
    this.tagPrefix,
    this.playbackCallback,
    this.isFromMemories = false,
    super.key,
  });

  @override
  State<VideoWidgetMediaKitNew> createState() => _VideoWidgetMediaKitNewState();
}

class _VideoWidgetMediaKitNewState extends State<VideoWidgetMediaKitNew>
    with WidgetsBindingObserver {
  final Logger _logger = Logger("VideoWidgetMediaKitNew");
  static const verticalMargin = 72.0;
  late final player = Player();
  VideoController? controller;
  final _progressNotifier = ValueNotifier<double?>(null);
  late StreamSubscription<bool> playingStreamSubscription;
  bool _isAppInFG = true;
  late StreamSubscription<PauseVideoEvent> pauseVideoSubscription;
  bool isGuestView = false;
  late final StreamSubscription<GuestViewEvent> _guestViewEventSubscription;

  @override
  void initState() {
    _logger.info(
      'initState for ${widget.file.generatedID} with tag ${widget.file.tag} and name ${widget.file.displayName}',
    );
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.file.isRemoteFile) {
      _loadNetworkVideo();
      _setFileSizeIfNull();
    } else if (widget.file.isSharedMediaToAppSandbox) {
      final localFile = File(getSharedMediaFilePath(widget.file));
      if (localFile.existsSync()) {
        _setVideoController(localFile.path);
      } else if (widget.file.uploadedFileID != null) {
        _loadNetworkVideo();
      }
    } else {
      widget.file.getAsset.then((asset) async {
        if (asset == null || !(await asset.exists)) {
          if (widget.file.uploadedFileID != null) {
            _loadNetworkVideo();
          }
        } else {
          // ignore: unawaited_futures
          asset.getMediaUrl().then((url) {
            _setVideoController(
              url ??
                  'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4',
            );
          });
        }
      });
    }
    playingStreamSubscription = player.stream.playing.listen((event) {
      if (widget.playbackCallback != null && mounted) {
        widget.playbackCallback!(event);
      }
    });

    pauseVideoSubscription = Bus.instance.on<PauseVideoEvent>().listen((event) {
      player.pause();
    });
    _guestViewEventSubscription =
        Bus.instance.on<GuestViewEvent>().listen((event) {
      setState(() {
        isGuestView = event.isGuestView;
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isAppInFG = true;
    } else {
      _isAppInFG = false;
    }
  }

  @override
  void dispose() {
    _guestViewEventSubscription.cancel();
    pauseVideoSubscription.cancel();
    removeCallBack(widget.file);
    _progressNotifier.dispose();
    WidgetsBinding.instance.removeObserver(this);
    playingStreamSubscription.cancel();
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: controller != null
          ? Video(
              controller: controller!,
              controls: (state) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    PlayPauseButtonMediaKit(controller),
                    Positioned(
                      bottom: verticalMargin,
                      right: 0,
                      left: 0,
                      child: SafeArea(
                        top: false,
                        left: false,
                        right: false,
                        child: Padding(
                          padding: EdgeInsets.only(
                            bottom: widget.isFromMemories ? 32 : 0,
                          ),
                          child: _SeekBarAndDuration(
                            controller: controller,
                            // showControls: _showControls,
                            // isSeeking: _isSeeking,
                          ),
                          // child: const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ],
                );
              },
            )
          : _getLoadingWidget(),
    );
  }

  void _loadNetworkVideo() {
    getFileFromServer(
      widget.file,
      progressCallback: (count, total) {
        if (!mounted) {
          return;
        }
        _progressNotifier.value = count / (widget.file.fileSize ?? total);
        if (_progressNotifier.value == 1) {
          if (mounted) {
            showShortToast(context, S.of(context).decryptingVideo);
          }
        }
      },
    ).then((file) {
      if (file != null) {
        _setVideoController(file.path);
      }
    }).onError((error, stackTrace) {
      showErrorDialog(
        context,
        S.of(context).error,
        S.of(context).failedToDownloadVideo,
      );
    });
  }

  void _setFileSizeIfNull() {
    if (widget.file.fileSize == null && widget.file.canEditMetaInfo) {
      FilesService.instance
          .getFileSize(widget.file.uploadedFileID!)
          .then((value) {
        widget.file.fileSize = value;
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  void _setVideoController(String url) {
    if (mounted) {
      setState(() {
        player.setPlaylistMode(PlaylistMode.single);
        controller = VideoController(player);
        player.open(Media(url), play: _isAppInFG);
      });
    }
  }

  Widget _getLoadingWidget() {
    return Stack(
      children: [
        _getThumbnail(),
        Container(
          color: Colors.black12,
          constraints: const BoxConstraints.expand(),
        ),
        Center(
          child: SizedBox.fromSize(
            size: const Size.square(20),
            child: ValueListenableBuilder(
              valueListenable: _progressNotifier,
              builder: (BuildContext context, double? progress, _) {
                return progress == null || progress == 1
                    ? const CupertinoActivityIndicator(
                        color: Colors.white,
                      )
                    : CircularProgressIndicator(
                        backgroundColor: Colors.black,
                        value: progress,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color.fromRGBO(45, 194, 98, 1.0),
                        ),
                      );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _getThumbnail() {
    return Container(
      color: Colors.black,
      constraints: const BoxConstraints.expand(),
      child: ThumbnailWidget(
        widget.file,
        fit: BoxFit.contain,
      ),
    );
  }
}

class PlayPauseButtonMediaKit extends StatefulWidget {
  final VideoController? controller;
  const PlayPauseButtonMediaKit(
    this.controller, {
    super.key,
  });

  @override
  State<PlayPauseButtonMediaKit> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<PlayPauseButtonMediaKit> {
  bool _isPlaying = true;
  late final StreamSubscription<bool>? isPlayingStreamSubscription;

  @override
  void initState() {
    super.initState();

    isPlayingStreamSubscription =
        widget.controller?.player.stream.playing.listen((isPlaying) {
      setState(() {
        _isPlaying = isPlaying;
      });
    });
  }

  @override
  void dispose() {
    isPlayingStreamSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (widget.controller?.player.state.playing ?? false) {
          widget.controller?.player.pause();
        } else {
          widget.controller?.player.play();
        }
      },
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3),
          shape: BoxShape.circle,
          border: Border.all(
            color: strokeFaintDark,
            width: 1,
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return ScaleTransition(scale: animation, child: child);
          },
          switchInCurve: Curves.easeInOutQuart,
          switchOutCurve: Curves.easeInOutQuart,
          child: _isPlaying
              ? const Icon(
                  Icons.pause,
                  size: 32,
                  key: ValueKey("pause"),
                  color: Colors.white,
                )
              : const Icon(
                  Icons.play_arrow,
                  size: 36,
                  key: ValueKey("play"),
                  color: Colors.white,
                ),
        ),
      ),
    );
  }
}

class _SeekBarAndDuration extends StatelessWidget {
  final VideoController? controller;
  // final ValueNotifier<bool> showControls;
  // final ValueNotifier<bool> isSeeking;

  const _SeekBarAndDuration({
    required this.controller,
    // required this.showControls,
    // required this.isSeeking,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      // valueListenable: showControls,
      valueListenable: ValueNotifier(true),

      builder: (
        BuildContext context,
        bool value,
        _,
      ) {
        return AnimatedOpacity(
          duration: const Duration(
            milliseconds: 200,
          ),
          curve: Curves.easeInQuad,
          opacity: value ? 1 : 0,
          child: IgnorePointer(
            ignoring: !value,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(
                  16,
                  4,
                  16,
                  4,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: const BorderRadius.all(
                    Radius.circular(8),
                  ),
                  border: Border.all(
                    color: strokeFaintDark,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    // AnimatedSize(
                    //   duration: const Duration(
                    //     seconds: 5,
                    //   ),
                    //   curve: Curves.easeInOut,
                    //   child: ValueListenableBuilder(
                    //     valueListenable: controller!.onPlaybackPositionChanged,
                    //     builder: (
                    //       BuildContext context,
                    //       int value,
                    //       _,
                    //     ) {
                    //       return Text(
                    //         _secondsToDuration(
                    //           value,
                    //         ),
                    //         style: getEnteTextTheme(
                    //           context,
                    //         ).mini.copyWith(
                    //               color: textBaseDark,
                    //             ),
                    //       );
                    //     },
                    //   ),
                    // ),
                    StreamBuilder(
                      stream: controller?.player.stream.position,
                      builder: (context, snapshot) {
                        if (snapshot.data == null) {
                          return Text(
                            "0:00",
                            style: getEnteTextTheme(
                              context,
                            ).mini.copyWith(
                                  color: textBaseDark,
                                ),
                          );
                        }
                        return Text(
                          _secondsToDuration(snapshot.data!.inSeconds),
                          style: getEnteTextTheme(
                            context,
                          ).mini.copyWith(
                                color: textBaseDark,
                              ),
                        );
                      },
                    ),
                    Expanded(
                      child: _SeekBar(
                        controller!,

                        // isSeeking,
                      ),
                    ),
                    Text(
                      _secondsToDuration(
                        controller!.player.state.duration.inSeconds,
                      ),
                      style: getEnteTextTheme(
                        context,
                      ).mini.copyWith(
                            color: textBaseDark,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Returns the duration in the format "h:mm:ss" or "m:ss".
  String _secondsToDuration(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(1, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(1, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  /// Returns the duration in seconds from the format "h:mm:ss" or "m:ss".
  int? _durationToSeconds(String? duration) {
    if (duration == null) {
      return null;
    }
    final parts = duration.split(':');
    int seconds = 0;

    if (parts.length == 3) {
      // Format: "h:mm:ss"
      seconds += int.parse(parts[0]) * 3600; // Hours to seconds
      seconds += int.parse(parts[1]) * 60; // Minutes to seconds
      seconds += int.parse(parts[2]); // Seconds
    } else if (parts.length == 2) {
      // Format: "m:ss"
      seconds += int.parse(parts[0]) * 60; // Minutes to seconds
      seconds += int.parse(parts[1]); // Seconds
    } else {
      throw FormatException('Invalid duration format: $duration');
    }

    return seconds;
  }
}

class _SeekBar extends StatefulWidget {
  final VideoController controller;
  // final ValueNotifier<bool> isSeeking;
  const _SeekBar(
    this.controller,
  );

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  final _positionNotifer = ValueNotifier<double>(0.0);
  final _debouncer = Debouncer(
    const Duration(milliseconds: 100),
    executionInterval: const Duration(milliseconds: 325),
  );
  @override
  void initState() {
    super.initState();

    // widget.controller.onPlaybackStatusChanged.addListener(
    //   _onPlaybackStatusChanged,
    // );
    // widget.controller.onPlaybackPositionChanged.addListener(
    //   _onPlaybackPositionChanged,
    // );

    // _startMovingSeekbar();
    widget.controller.player.stream.position.listen((event) {
      _positionNotifer.value = event.inMilliseconds /
          widget.controller.player.state.duration.inMilliseconds;
    });
  }

  @override
  void dispose() {
    // widget.controller.onPlaybackStatusChanged.removeListener(
    //   _onPlaybackStatusChanged,
    // );
    // widget.controller.onPlaybackPositionChanged.removeListener(
    //   _onPlaybackPositionChanged,
    // );
    _debouncer.cancelDebounceTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 1.0,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
        activeTrackColor: colorScheme.primary300,
        inactiveTrackColor: fillMutedDark,
        thumbColor: backgroundElevatedLight,
        overlayColor: fillMutedDark,
      ),
      child: ValueListenableBuilder(
        valueListenable: _positionNotifer,
        builder: (BuildContext context, double value, _) {
          return Slider(
            min: 0.0,
            max: 1.0,
            value: value,
            onChangeStart: (value) {
              // widget.isSeeking.value = true;
            },
            onChanged: (value) {
              // setState(() {
              //   _animationController.value = value;
              // });
              // _seekTo(value);
            },
            divisions: 4500,
            onChangeEnd: (value) {
              // setState(() {
              //   _animationController.value = value;
              // });
              // _seekTo(value);
              // widget.isSeeking.value = false;
            },
            allowedInteraction: SliderInteraction.tapAndSlide,
          );
        },
      ),
    );
  }

  void _seekTo(double value) {
    _debouncer.run(() async {
      // unawaited(
      //   widget.controller.seekTo((value * widget.duration!).round()),
      // );
    });
  }

  // void _startMovingSeekbar() {
  //   //Video starts playing after a slight delay. This delay is to ensure that
  //   //the seek bar animation starts after the video starts playing.
  //   Future.delayed(const Duration(milliseconds: 700), () {
  //     if (!mounted) {
  //       return;
  //     }
  //     if (widget.duration != null) {
  //       unawaited(
  //         _animationController.animateTo(
  //           (1 / widget.duration!),
  //           duration: const Duration(seconds: 1),
  //         ),
  //       );
  //     } else {
  //       unawaited(
  //         _animationController.animateTo(
  //           0,
  //           duration: const Duration(seconds: 1),
  //         ),
  //       );
  //     }
  //   });
  // }

  void _onPlaybackStatusChanged() {
    // if (widget.controller.playbackInfo?.status == PlaybackStatus.paused) {
    //   _animationController.stop();
    // }
  }

  void _onPlaybackPositionChanged() async {
    // if (widget.controller.playbackInfo?.status == PlaybackStatus.paused ||
    //     (widget.controller.playbackInfo?.status == PlaybackStatus.stopped &&
    //         widget.controller.playbackInfo?.positionFraction != 0)) {
    //   return;
    // }
    // final target = widget.controller.playbackInfo?.positionFraction ?? 0;

    // //To immediately set the position to 0 when the video ends
    // if (_prevPositionFraction == 1.0 && target == 0.0) {
    //   setState(() {
    //     _animationController.value = 0;
    //   });
    //   if (!localSettings.shouldLoopVideo()) {
    //     return;
    //   }
    // }

    // //There is a slight delay (around 350 ms) for the event being listened to
    // //by this listener on the next target (target that comes after 0). Adding
    // //this buffer to keep the seek bar animation smooth.
    // if (target == 0) {
    //   await Future.delayed(const Duration(milliseconds: 450));
    // }

    // if (widget.duration != null) {
    //   unawaited(
    //     _animationController.animateTo(
    //       target + (1 / widget.duration!),
    //       duration: const Duration(seconds: 1),
    //     ),
    //   );
    // } else {
    //   unawaited(
    //     _animationController.animateTo(
    //       target,
    //       duration: const Duration(seconds: 1),
    //     ),
    //   );
    // }

    // _prevPositionFraction = target;
  }
}
