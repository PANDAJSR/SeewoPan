part of 'cloud_tab.dart';

extension _CloudTabPreviewExtension on _CloudTabState {
  Future<void> _previewMaterial(DriveMaterial item) async {
    if (!_isPreviewableImage(item)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前仅支持图片预览。')),
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
                    child: Text('加载图片预览失败：${snapshot.error ?? '未知错误'}'),
                  );
                }

                return InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4,
                  child: Center(
                    child: _buildPreviewImage(snapshot.data!.previewUrl),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  bool _isPreviewableImage(DriveMaterial item) {
    final mimeType = item.mimeType.trim().toLowerCase();
    if (mimeType.startsWith('image/')) {
      return true;
    }

    final name = item.name.trim().toLowerCase();
    return name.endsWith('.png') ||
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.webp') ||
        name.endsWith('.gif') ||
        name.endsWith('.bmp');
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
