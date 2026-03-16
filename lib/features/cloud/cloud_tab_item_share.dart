part of 'cloud_tab.dart';

enum _ShareExpireOption {
  days15,
  days30,
  unlimited,
}

class _ShareConfig {
  const _ShareConfig({
    required this.expireOption,
    required this.isPrivate,
  });

  final _ShareExpireOption expireOption;
  final bool isPrivate;

  int get minutes {
    switch (expireOption) {
      case _ShareExpireOption.days15:
        return 15 * 24 * 60;
      case _ShareExpireOption.days30:
        return 30 * 24 * 60;
      case _ShareExpireOption.unlimited:
        return -1;
    }
  }

  int get shareType => isPrivate ? 1 : 0;

  String get expireLabel {
    switch (expireOption) {
      case _ShareExpireOption.days15:
        return '15天';
      case _ShareExpireOption.days30:
        return '30天';
      case _ShareExpireOption.unlimited:
        return '不限时';
    }
  }

  String get privacyLabel => isPrivate ? '私密' : '公开';
}

extension _CloudTabItemShareExtension on _CloudTabState {
  Future<void> _shareItem(DriveMaterial item) async {
    final config = await _showShareConfigDialog(item);
    if (config == null || !mounted) {
      return;
    }

    try {
      final result = await widget.apiClient.createDriveLinkShare(
        cookie: widget.cookie,
        resId: item.id,
        minutes: config.minutes,
        shareType: config.shareType,
      );

      if (!mounted) {
        return;
      }

      await _showShareResultDialog(
        item: item,
        config: config,
        result: result,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享失败：$error')),
      );
    }
  }

  Future<_ShareConfig?> _showShareConfigDialog(DriveMaterial item) {
    var expireOption = _ShareExpireOption.days15;
    var isPrivate = false;

    return showDialog<_ShareConfig>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('分享设置'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '文件：${item.name}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    const Text('有效期'),
                    RadioListTile<_ShareExpireOption>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('15天'),
                      value: _ShareExpireOption.days15,
                      groupValue: expireOption,
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() => expireOption = value);
                      },
                    ),
                    RadioListTile<_ShareExpireOption>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('30天'),
                      value: _ShareExpireOption.days30,
                      groupValue: expireOption,
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() => expireOption = value);
                      },
                    ),
                    RadioListTile<_ShareExpireOption>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('不限时'),
                      value: _ShareExpireOption.unlimited,
                      groupValue: expireOption,
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() => expireOption = value);
                      },
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('私密分享（需密码）'),
                      value: isPrivate,
                      onChanged: (value) =>
                          setDialogState(() => isPrivate = value),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(
                      _ShareConfig(
                        expireOption: expireOption,
                        isPrivate: isPrivate,
                      ),
                    );
                  },
                  child: const Text('创建分享'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showShareResultDialog({
    required DriveMaterial item,
    required _ShareConfig config,
    required DriveLinkShareResult result,
  }) async {
    final shareUrl = result.shareUrl;
    final password = result.password;
    final combinedText =
        password == null ? shareUrl : '$shareUrl\n提取码：$password';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('分享创建成功'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text('类型：${config.privacyLabel}'),
                Text('有效期：${config.expireLabel}'),
                const SizedBox(height: 12),
                const Text('链接'),
                SelectableText(shareUrl),
                if (password != null) ...[
                  const SizedBox(height: 8),
                  const Text('提取码'),
                  SelectableText(password),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
            OutlinedButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: shareUrl));
                if (!mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制分享链接')),
                );
              },
              child: const Text('复制链接'),
            ),
            FilledButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: combinedText));
                if (!mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      password == null ? '已复制分享内容' : '已复制链接和提取码',
                    ),
                  ),
                );
              },
              child: const Text('复制全部'),
            ),
          ],
        );
      },
    );
  }
}
