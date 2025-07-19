import 'package:flutter/material.dart';
import '../services/resource_monitor.dart';

class ResourceMonitorWidget extends StatefulWidget {
  @override
  _ResourceMonitorWidgetState createState() => _ResourceMonitorWidgetState();
}

class _ResourceMonitorWidgetState extends State<ResourceMonitorWidget> {
  double _cpuUsage = 0.0;
  double _memoryUsage = 0.0;
  ProcessingProgress? _progress;

  @override
  void initState() {
    super.initState();
    _setupListeners();
  }

  void _setupListeners() {
    ResourceMonitor.instance.cpuUsageStream.listen((usage) {
      if (mounted) {
        setState(() => _cpuUsage = usage);
      }
    });

    ResourceMonitor.instance.memoryUsageStream.listen((usage) {
      if (mounted) {
        setState(() => _memoryUsage = usage);
      }
    });

    ResourceMonitor.instance.progressStream.listen((progress) {
      if (mounted) {
        setState(() => _progress = progress);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.shadow.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.monitor_heart,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Мониторинг системы',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        if (_progress != null)
                          Text(
                            _progress!.currentStage,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // CPU Usage
              _buildUsageRow(
                'CPU',
                _cpuUsage,
                Icons.memory,
                Colors.blue,
              ),
              const SizedBox(height: 12),

              // Memory Usage
              _buildUsageRow(
                'Память',
                _memoryUsage,
                Icons.storage,
                Colors.green,
              ),

              // Processing Progress
              if (_progress != null) ...[
                const SizedBox(height: 20),
                _buildProgressSection(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUsageRow(
      String label, double usage, IconData icon, Color color) {
    return Row(
      children: [
        Icon(
          icon,
          color: color,
          size: 20,
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
        ),
        Expanded(
          child: LinearProgressIndicator(
            value: (usage / 100).clamp(0.0, 1.0),
            backgroundColor: color.withOpacity(0.2),
            valueColor:
                AlwaysStoppedAnimation<Color>(_getUsageColor(usage, color)),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _getUsageColor(usage, color).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${usage.toStringAsFixed(1)}%',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: _getUsageColor(usage, color),
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Обработка кадров',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              Text(
                'ETA: ${_progress!.eta}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: _progress!.percentage / 100,
            backgroundColor:
                Theme.of(context).colorScheme.outline.withOpacity(0.2),
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).colorScheme.primary,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _progress!.progressText,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                '${_progress!.percentage.toStringAsFixed(1)}%',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ],
          ),
          if (_progress!.currentFile != null) ...[
            const SizedBox(height: 8),
            Text(
              'Файл: ${_progress!.currentFile}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Color _getUsageColor(double usage, Color baseColor) {
    if (usage > 80) {
      return Colors.red;
    } else if (usage > 60) {
      return Colors.orange;
    } else {
      return baseColor;
    }
  }
}
