part of 'cloud_tab.dart';

class _MediaPreviewPlayer extends StatefulWidget {
  const _MediaPreviewPlayer({
    required this.previewUrl,
    required this.isVideo,
  });

  final String previewUrl;
  final bool isVideo;

  @override
  State<_MediaPreviewPlayer> createState() => _MediaPreviewPlayerState();
}

class _MediaPreviewPlayerState extends State<_MediaPreviewPlayer> {
  VideoPlayerController? _videoController;
  AudioPlayer? _audioPlayer;
  Object? _error;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.previewUrl),
      );
      _videoController = controller;
      unawaited(
        controller.initialize().then((_) async {
          if (!mounted) {
            return;
          }
          setState(() {});
          await controller.play();
        }).catchError((Object error) {
          if (!mounted) {
            return;
          }
          setState(() {
            _error = error;
          });
        }),
      );
      return;
    }

    final player = AudioPlayer();
    _audioPlayer = player;
    unawaited(
      player.setUrl(widget.previewUrl).then((_) async {
        if (!mounted) {
          return;
        }
        setState(() {});
        await player.play();
      }).catchError((Object error) {
        if (!mounted) {
          return;
        }
        setState(() {
          _error = error;
        });
      }),
    );
  }

  @override
  void dispose() {
    _videoController?.dispose();
    unawaited(_audioPlayer?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text('加载媒体失败：$_error'));
    }

    if (widget.isVideo) {
      final controller = _videoController;
      if (controller == null || !controller.value.isInitialized) {
        return const Center(child: CircularProgressIndicator());
      }

      return Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
      );
    }

    final player = _audioPlayer;
    if (player == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Center(
      child: SizedBox(
        width: 360,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StreamBuilder<bool>(
                  stream: player.playingStream,
                  initialData: player.playing,
                  builder: (context, snapshot) {
                    final playing = snapshot.data ?? false;
                    return IconButton.filled(
                      onPressed: () {
                        if (playing) {
                          unawaited(player.pause());
                        } else {
                          unawaited(player.play());
                        }
                      },
                      icon: Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      tooltip: playing ? '暂停' : '播放',
                    );
                  },
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: StreamBuilder<Duration?>(
                    stream: player.durationStream,
                    initialData: player.duration,
                    builder: (context, durationSnapshot) {
                      final duration = durationSnapshot.data ?? Duration.zero;
                      return StreamBuilder<Duration>(
                        stream: player.positionStream,
                        initialData: player.position,
                        builder: (context, positionSnapshot) {
                          final position =
                              positionSnapshot.data ?? Duration.zero;
                          final maxSeconds = math.max(
                            duration.inMilliseconds / 1000,
                            1.0,
                          );
                          final seconds = math.min(
                            position.inMilliseconds / 1000,
                            maxSeconds,
                          );

                          return Slider(
                            value: seconds,
                            max: maxSeconds,
                            onChanged: duration == Duration.zero
                                ? null
                                : (value) {
                                    unawaited(
                                      player.seek(
                                        Duration(
                                          milliseconds: (value * 1000).round(),
                                        ),
                                      ),
                                    );
                                  },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModelPreviewViewer extends StatefulWidget {
  const _ModelPreviewViewer({required this.previewUrl});

  final String previewUrl;

  @override
  State<_ModelPreviewViewer> createState() => _ModelPreviewViewerState();
}

class _ModelPreviewViewerState extends State<_ModelPreviewViewer> {
  final Flutter3DController _controller = Flutter3DController();
  String? _error;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned.fill(
          child: Flutter3DViewer(
            controller: _controller,
            src: widget.previewUrl,
            activeGestureInterceptor: true,
            enableTouch: true,
            progressBarColor: colorScheme.primary,
            onLoad: (_) {
              if (!mounted) {
                return;
              }
              setState(() {
                _error = null;
              });
            },
            onError: (error) {
              if (!mounted) {
                return;
              }
              setState(() {
                _error = error;
              });
            },
          ),
        ),
        if (_error != null)
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(
                    '加载 3D 模型失败：$_error',
                    style: TextStyle(color: colorScheme.onErrorContainer),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _OfficePreviewLoader extends StatelessWidget {
  const _OfficePreviewLoader({required this.previewUrl});

  final String previewUrl;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<http.Response>(
      future: http.get(Uri.parse(previewUrl)),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return Center(
            child: Text('加载 Office 文件失败：${snapshot.error ?? '未知错误'}'),
          );
        }

        final response = snapshot.data!;
        if (response.statusCode < 200 || response.statusCode >= 300) {
          return Center(
            child: Text('加载 Office 文件失败：HTTP ${response.statusCode}'),
          );
        }

        return buildOfficePreviewView(response.bodyBytes);
      },
    );
  }
}
