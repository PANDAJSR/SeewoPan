part of 'cloud_tab.dart';

extension _CloudTabCapacityExtension on _CloudTabState {
  Widget _buildCapacitySection(BuildContext context) {
    if (_isLoadingCapacity && _materialsCapacity == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text('正在加载空间占用...'),
            ],
          ),
        ),
      );
    }

    if (_capacityError != null && _materialsCapacity == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            _capacityError!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
        ),
      );
    }

    final capacity = _materialsCapacity;
    if (capacity == null) {
      return const SizedBox.shrink();
    }

    final total = capacity.capacity;
    final appUsages = capacity.usedDetail.toList()
      ..sort((a, b) => b.totalUsed.compareTo(a.totalUsed));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '空间占用',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '已用 ${_formatCapacityBytes(capacity.used)} / ${_formatCapacityBytes(total)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            ...appUsages.map((item) {
              final ratio = total <= 0
                  ? 0.0
                  : (item.totalUsed / total).clamp(0.0, 1.0).toDouble();
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item.displayName} · ${_formatCapacityBytes(item.totalUsed)}',
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: ratio),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  String _formatCapacityBytes(int bytes) {
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
