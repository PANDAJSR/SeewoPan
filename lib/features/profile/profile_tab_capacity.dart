part of 'profile_tab.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _ProfileTabCapacityExtension on _ProfileTabState {
  void _resetCapacity() {
    _capacity = null;
    _capacityError = null;
  }

  Future<void> _fetchCapacity({bool forceRefresh = false}) async {
    final cookie = _cookieController.text.trim();
    if (cookie.isEmpty) {
      setState(() {
        _capacityError = '请先填写 Cookie。';
      });
      return;
    }

    setState(() {
      _isLoadingCapacity = true;
      _capacityError = null;
    });

    try {
      final capacity = await widget.apiClient.getDriveMaterialsCapacity(
        cookie: cookie,
        forceRefresh: forceRefresh,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingCapacity = false;
        _capacity = capacity;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingCapacity = false;
        _capacity = null;
        _capacityError = '获取空间占用失败：$error';
      });
    }
  }

  List<_UsageSegment> _buildUsageSegments() {
    final data = _capacity;
    if (data == null || data.capacity <= 0) {
      return const <_UsageSegment>[];
    }

    final palette = <Color>[
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.red,
      Colors.teal,
      Colors.indigo,
      Colors.cyan,
      Colors.brown,
    ];

    final details = data.usedDetail.toList()
      ..sort((a, b) => b.totalUsed.compareTo(a.totalUsed));

    return details.asMap().entries.map((entry) {
      final ratio = (entry.value.totalUsed / data.capacity).clamp(0.0, 1.0);
      return _UsageSegment(
        appName: entry.value.displayName,
        usedBytes: entry.value.totalUsed,
        ratio: ratio.toDouble(),
        color: palette[entry.key % palette.length],
      );
    }).toList(growable: false);
  }
}

class _CapacityCard extends StatelessWidget {
  const _CapacityCard({
    required this.capacity,
    required this.isLoading,
    required this.error,
    required this.segments,
  });

  final DriveMaterialsCapacity? capacity;
  final bool isLoading;
  final String? error;
  final List<_UsageSegment> segments;

  @override
  Widget build(BuildContext context) {
    if (isLoading && capacity == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text('正在获取空间占用...'),
            ],
          ),
        ),
      );
    }

    if (error != null && capacity == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            error!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
        ),
      );
    }

    final data = capacity;
    if (data == null) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('空间占用', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '总已用 ${_formatBytes(data.used)} / ${_formatBytes(data.capacity)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            _StackedUsageBar(segments: segments),
            const SizedBox(height: 12),
            ...segments.map(
              (segment) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: segment.color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${segment.appName} · ${_formatBytes(segment.usedBytes)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }

    const units = ['KB', 'MB', 'GB', 'TB'];
    double value = bytes / 1024;
    var unitIndex = 0;

    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex += 1;
    }

    return '${value.toStringAsFixed(2)} ${units[unitIndex]}';
  }
}

class _StackedUsageBar extends StatelessWidget {
  const _StackedUsageBar({required this.segments});

  final List<_UsageSegment> segments;

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        key: const Key('capacity_stacked_bar'),
        width: double.infinity,
        height: 12,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final children = <Widget>[
              SizedBox(
                width: constraints.maxWidth,
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ),
            ];
            for (final segment in segments) {
              final width = constraints.maxWidth * segment.ratio;
              if (width <= 0) {
                continue;
              }
              children.add(
                SizedBox(
                  width: width,
                  child: ColoredBox(color: segment.color),
                ),
              );
            }
            final activeChildren = children.sublist(1);
            if (activeChildren.isEmpty) {
              return Row(children: [children.first]);
            }
            return Stack(children: [children.first, Row(children: activeChildren)]);
          },
        ),
      ),
    );
  }
}

class _UsageSegment {
  const _UsageSegment({
    required this.appName,
    required this.usedBytes,
    required this.ratio,
    required this.color,
  });

  final String appName;
  final int usedBytes;
  final double ratio;
  final Color color;
}
