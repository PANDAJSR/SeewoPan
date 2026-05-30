part of 'cloud_tab.dart';

extension _CloudTabPreviewExtension on _CloudTabState {
  Future<void> _previewMaterial(DriveMaterial item) async {
    final previewType = _detectPreviewType(item);
    if (previewType == _PreviewType.unsupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂不支持预览此文件类型。')),
      );
      return;
    }

    final previewFuture = widget.apiClient.getMaterialPreview(
      cookie: widget.cookie,
      materialId: item.id,
    );

    await showDialog<void>(
      context: context,
      builder: (context) {
        final viewport = MediaQuery.sizeOf(context);
        final width = math.min(viewport.width * 0.88, 920.0);
        final height = math.min(viewport.height * 0.72, 680.0);

        return AlertDialog(
          title: Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          content: SizedBox(
            width: width,
            height: height,
            child: FutureBuilder<DriveMaterialPreview>(
              future: previewFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError || !snapshot.hasData) {
                  return Center(
                    child: Text('加载预览失败：${snapshot.error ?? '未知错误'}'),
                  );
                }

                return _buildPreviewContent(
                  previewType: previewType,
                  previewUrl: snapshot.data!.previewUrl,
                );
              },
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                final snapshot = previewFuture;
                final messenger = ScaffoldMessenger.of(context);
                unawaited(
                  snapshot.then(
                    (preview) => _copyText(preview.previewUrl, '已复制文件地址'),
                    onError: (Object error) {
                      if (!mounted) {
                        return;
                      }
                      messenger.showSnackBar(
                        SnackBar(content: Text('复制地址失败：$error')),
                      );
                    },
                  ),
                );
              },
              icon: const Icon(Icons.link_rounded),
              label: const Text('复制地址'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPreviewContent({
    required _PreviewType previewType,
    required String previewUrl,
  }) {
    final child = switch (previewType) {
      _PreviewType.image => _buildPreviewImage(previewUrl),
      _PreviewType.video => _MediaPreviewPlayer(
          previewUrl: previewUrl,
          isVideo: true,
        ),
      _PreviewType.audio => _MediaPreviewPlayer(
          previewUrl: previewUrl,
          isVideo: false,
        ),
      _PreviewType.office => _OfficePreviewLoader(previewUrl: previewUrl),
      _PreviewType.unsupported => const SizedBox.shrink(),
    };

    if (previewType == _PreviewType.image) {
      return _buildContextMenuRegion(
        previewUrl: previewUrl,
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: Center(child: child),
        ),
      );
    }

    return _buildContextMenuRegion(
      previewUrl: previewUrl,
      child: child,
    );
  }

  Widget _buildContextMenuRegion({
    required String previewUrl,
    required Widget child,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) => _showPreviewContextMenu(
        position: details.globalPosition,
        previewUrl: previewUrl,
      ),
      onLongPressStart: (details) => _showPreviewContextMenu(
        position: details.globalPosition,
        previewUrl: previewUrl,
      ),
      child: child,
    );
  }

  Future<void> _showPreviewContextMenu({
    required Offset position,
    required String previewUrl,
  }) async {
    final selected = await showMenu<_PreviewImageMenuAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: const [
        PopupMenuItem(
          value: _PreviewImageMenuAction.copyAddress,
          child: Text('复制文件地址'),
        ),
      ],
    );

    if (selected == null || !mounted) {
      return;
    }

    switch (selected) {
      case _PreviewImageMenuAction.copyAddress:
        await _copyText(previewUrl, '已复制文件地址');
        break;
    }
  }

  _PreviewType _detectPreviewType(DriveMaterial item) {
    final mimeType = item.mimeType.trim().toLowerCase();
    if (mimeType.startsWith('image/')) {
      return _PreviewType.image;
    }
    if (mimeType.startsWith('video/')) {
      return _PreviewType.video;
    }
    if (mimeType.startsWith('audio/')) {
      return _PreviewType.audio;
    }

    final name = item.name.trim().toLowerCase();
    if (name.endsWith('.png') ||
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.webp') ||
        name.endsWith('.gif') ||
        name.endsWith('.bmp')) {
      return _PreviewType.image;
    }
    if (name.endsWith('.mp4') ||
        name.endsWith('.m4v') ||
        name.endsWith('.mov') ||
        name.endsWith('.webm') ||
        name.endsWith('.mkv') ||
        name.endsWith('.avi')) {
      return _PreviewType.video;
    }
    if (name.endsWith('.mp3') ||
        name.endsWith('.m4a') ||
        name.endsWith('.aac') ||
        name.endsWith('.wav') ||
        name.endsWith('.flac') ||
        name.endsWith('.ogg')) {
      return _PreviewType.audio;
    }
    if (name.endsWith('.docx') ||
        name.endsWith('.xlsx') ||
        name.endsWith('.pptx')) {
      return _PreviewType.office;
    }
    return _PreviewType.unsupported;
  }

  Widget _buildPreviewImage(String previewUrl) {
    final dataUriMatch =
        RegExp(r'^data:image/[^;]+;base64,(.+)$').firstMatch(previewUrl.trim());
    if (dataUriMatch != null) {
      return Image.memory(
        base64Decode(dataUriMatch.group(1)!),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Text('加载图片失败：$error');
        },
      );
    }

    return Image.network(
      previewUrl,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }
        return const Center(child: CircularProgressIndicator());
      },
      errorBuilder: (context, error, stackTrace) {
        return Text('加载图片失败：$error');
      },
    );
  }
}

enum _PreviewImageMenuAction {
  copyAddress,
}

enum _PreviewType {
  image,
  video,
  audio,
  office,
  unsupported,
}

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
  late final Player _player;
  late final VideoController _controller;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    unawaited(_player.open(Media(widget.previewUrl)));
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: widget.isVideo ? 16 / 9 : 16 / 4,
        child: ColoredBox(
          color: Colors.black,
          child: Video(controller: _controller),
        ),
      ),
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
              child: Text('加载 Office 文件失败：HTTP ${response.statusCode}'));
        }

        return buildOfficePreviewView(response.bodyBytes);
      },
    );
  }
}
