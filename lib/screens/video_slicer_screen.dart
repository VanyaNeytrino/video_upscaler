import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:video_upscaler/services/executable_manager.dart';

// Перечисление типов нарезки
enum SlicingType {
  overlapping('Перекрывающиеся сегменты', 'Для анализа с перекрытиями'),
  equal2('2 равные части', 'Разделить видео пополам'),
  equal3('3 равные части', 'Разделить на три части'),
  equal4('4 равные части', 'Разделить на четыре части');

  const SlicingType(this.title, this.description);
  final String title;
  final String description;
}

class VideoSlicerScreen extends StatefulWidget {
  @override
  _VideoSlicerScreenState createState() => _VideoSlicerScreenState();
}

class _VideoSlicerScreenState extends State<VideoSlicerScreen> {
  String? _inputVideoPath;
  String? _outputDirectory;
  Map<String, dynamic>? _videoInfo;
  List<VideoSegment> _segments = [];

  bool _isProcessing = false;
  String _currentProgress = 'Готов к работе';
  double _progressPercentage = 0.0;

  // Настройки
  SlicingType _slicingType =
      SlicingType.equal2; // ИЗМЕНЕНО: по умолчанию 2 части
  double _baseDuration = 5.0;
  String _outputFormat = 'mp4';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Нарезка видео'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderCard(),
                const SizedBox(height: 20),
                _buildSlicingTypeSelector(),
                const SizedBox(height: 20),
                _buildInputSection(),
                const SizedBox(height: 20),
                if (_videoInfo != null) _buildVideoInfoCard(),
                if (_videoInfo != null) const SizedBox(height: 20),
                if (_segments.isNotEmpty) _buildSegmentsPreview(),
                if (_segments.isNotEmpty) const SizedBox(height: 20),
                _buildSettingsSection(),
                const SizedBox(height: 20),
                _buildProgressSection(),
                const SizedBox(height: 20),
                _buildActionButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
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
                  child: _getSlicingTypeIcon(_slicingType),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Нарезка видео',
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      Text(
                        _slicingType.title,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
          ],
        ),
      ),
    );
  }

  Widget _buildSlicingTypeSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Тип нарезки',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<SlicingType>(
                segments: SlicingType.values.map((type) {
                  return ButtonSegment<SlicingType>(
                    value: type,
                    label: Text(
                      type.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12),
                    ),
                    icon: _getSlicingTypeIcon(type),
                  );
                }).toList(),
                selected: {_slicingType},
                onSelectionChanged: _isProcessing
                    ? null
                    : (value) {
                        setState(() {
                          _slicingType = value.first;
                          if (_videoInfo != null) {
                            _calculateSegments();
                          }
                        });
                      },
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  selectedForegroundColor:
                      Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _slicingType.description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            _buildSlicingVisualization(),
          ],
        ),
      ),
    );
  }

  Icon _getSlicingTypeIcon(SlicingType type) {
    switch (type) {
      case SlicingType.overlapping:
        return Icon(Icons.layers, size: 16);
      case SlicingType.equal2:
        return Icon(Icons.vertical_split, size: 16);
      case SlicingType.equal3:
        return Icon(Icons.view_column, size: 16);
      case SlicingType.equal4:
        return Icon(Icons.grid_view, size: 16);
    }
  }

  Widget _buildSlicingVisualization() {
    switch (_slicingType) {
      case SlicingType.overlapping:
        return _buildOverlappingVisualization();
      case SlicingType.equal2:
        return _buildEqualPartsVisualization(2);
      case SlicingType.equal3:
        return _buildEqualPartsVisualization(3);
      case SlicingType.equal4:
        return _buildEqualPartsVisualization(4);
    }
  }

  Widget _buildOverlappingVisualization() {
    return Column(
      children: [
        Text(
          'Схема с перекрытиями (для 5-сек видео):',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        _buildTimelineSegment(
            'Сегмент 1', '0:00 → 0:02', Colors.blue, 0.4, 0.0),
        const SizedBox(height: 4),
        _buildTimelineSegment(
            'Сегмент 2', '0:02 → 0:04', Colors.green, 0.4, 0.2),
        const SizedBox(height: 4),
        _buildTimelineSegment(
            'Сегмент 3', '0:03 → 0:05', Colors.orange, 0.4, 0.3),
      ],
    );
  }

  Widget _buildEqualPartsVisualization(int parts) {
    final colors = [Colors.blue, Colors.green, Colors.orange, Colors.purple];
    final partDuration = 5.0 / parts;

    return Column(
      children: [
        Text(
          'Схема равных частей (для 5-сек видео):',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        ...List.generate(parts, (index) {
          final startTime = partDuration * index;
          final endTime = partDuration * (index + 1);
          final offset = (1.0 / parts) * index;

          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _buildTimelineSegment(
              'Часть ${index + 1}',
              '${_formatDuration(startTime)} → ${_formatDuration(endTime)}',
              colors[index % colors.length],
              1.0 / parts,
              offset,
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTimelineSegment(
      String name, String time, Color color, double width, double offset) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            name,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
        ),
        Expanded(
          child: Container(
            height: 24,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: MediaQuery.of(context).size.width * 0.4 * offset,
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.4 * width,
                    height: 24,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color, width: 2),
                    ),
                    child: Center(
                      child: Text(
                        time,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInputSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Выбор файлов',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            _buildFileSelector(
              title: 'Входное видео',
              path: _inputVideoPath,
              placeholder: 'Выберите видео для нарезки',
              icon: Icons.video_file,
              onTap: _selectInputVideo,
            ),
            const SizedBox(height: 16),
            _buildFileSelector(
              title: 'Папка для сохранения',
              path: _outputDirectory,
              placeholder: 'Выберите папку для частей',
              icon: Icons.folder,
              onTap: _selectOutputDirectory,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileSelector({
    required String title,
    required String? path,
    required String placeholder,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final hasFile = path != null;

    return InkWell(
      onTap: _isProcessing ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: hasFile
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: hasFile
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasFile
                        ? path.split(Platform.pathSeparator).last
                        : placeholder,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: hasFile
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoInfoCard() {
    final duration = _videoInfo!['duration'] as double;
    final width = _videoInfo!['width'] as int;
    final height = _videoInfo!['height'] as int;
    final fps = _videoInfo!['fps'] as double;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.info,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Информация о видео',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                    child: _buildVideoStat(
                        'Длительность', _formatDuration(duration))),
                Expanded(
                    child: _buildVideoStat('Разрешение', '${width}x${height}')),
                Expanded(child: _buildVideoStat('FPS', fps.toStringAsFixed(1))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoStat(String label, String value) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentsPreview() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Предварительный просмотр ${_slicingType.title.toLowerCase()}',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            ..._segments.asMap().entries.map((entry) {
              final index = entry.key;
              final segment = entry.value;
              return _buildSegmentCard(index + 1, segment);
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentCard(int index, VideoSegment segment) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _getSegmentColor(index).withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '$index',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _getSegmentColor(index),
                    ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _slicingType == SlicingType.overlapping
                      ? 'Сегмент $index'
                      : 'Часть $index',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatDuration(segment.startTime)} → ${_formatDuration(segment.endTime)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                Text(
                  'Длительность: ${_formatDuration(segment.duration)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              segment.fileName,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Настройки',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            if (_slicingType == SlicingType.overlapping) ...[
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Базовая длительность (сек)',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          enabled: !_isProcessing,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            hintText: '5.0',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onChanged: (value) {
                            final duration = double.tryParse(value);
                            if (duration != null && duration > 0) {
                              setState(() {
                                _baseDuration = duration;
                                if (_videoInfo != null) {
                                  _calculateSegments();
                                }
                              });
                            }
                          },
                          controller: TextEditingController(
                              text: _baseDuration.toString()),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Формат вывода',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _outputFormat,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          items: ['mp4', 'mov', 'avi', 'mkv'].map((format) {
                            return DropdownMenuItem(
                              value: format,
                              child: Text(format.toUpperCase()),
                            );
                          }).toList(),
                          onChanged: _isProcessing
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setState(() => _outputFormat = value);
                                  }
                                },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Формат вывода',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _outputFormat,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          items: ['mp4', 'mov', 'avi', 'mkv'].map((format) {
                            return DropdownMenuItem(
                              value: format,
                              child: Text(format.toUpperCase()),
                            );
                          }).toList(),
                          onChanged: _isProcessing
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setState(() => _outputFormat = value);
                                  }
                                },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: SizedBox()),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProgressSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.timeline,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Прогресс',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: _progressPercentage / 100,
              borderRadius: BorderRadius.circular(8),
              minHeight: 8,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _currentProgress,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Text(
                  '${_progressPercentage.toStringAsFixed(1)}%',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    final canProcess = _inputVideoPath != null &&
        _outputDirectory != null &&
        _segments.isNotEmpty &&
        !_isProcessing;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: canProcess ? _startSlicing : null,
            icon: _isProcessing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.content_cut),
            label: Text(
              _isProcessing ? 'Нарезка...' : 'Начать нарезку',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
        if (_isProcessing) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _stopSlicing,
              icon: const Icon(Icons.stop),
              label: const Text('Остановить'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ИСПРАВЛЕННЫЕ МЕТОДЫ РАСЧЕТА И НАРЕЗКИ

  void _calculateSegments() {
    if (_videoInfo == null) return;

    final duration = _videoInfo!['duration'] as double;

    switch (_slicingType) {
      case SlicingType.overlapping:
        _calculateOverlappingSegments(duration);
        break;
      case SlicingType.equal2:
        _calculateEqualParts(duration, 2);
        break;
      case SlicingType.equal3:
        _calculateEqualParts(duration, 3);
        break;
      case SlicingType.equal4:
        _calculateEqualParts(duration, 4);
        break;
    }
  }

  void _calculateOverlappingSegments(double duration) {
    final scaleFactor = duration / _baseDuration;
    final segmentDuration = 2.0 * scaleFactor;

    setState(() {
      _segments = [
        VideoSegment(
          startTime: 0.0,
          endTime: segmentDuration,
          fileName: 'segment_01.$_outputFormat',
        ),
        VideoSegment(
          startTime: segmentDuration * 0.5,
          endTime: segmentDuration * 1.5,
          fileName: 'segment_02.$_outputFormat',
        ),
        VideoSegment(
          startTime: segmentDuration,
          endTime: min(segmentDuration * 2, duration),
          fileName: 'segment_03.$_outputFormat',
        ),
      ];
    });
  }

  // ИСПРАВЛЕН: расчет равных частей с точной арифметикой
  void _calculateEqualParts(double duration, int parts) {
    final partDuration = duration / parts;

    setState(() {
      _segments = List.generate(parts, (index) {
        final startTime = partDuration * index;
        // ИСПРАВЛЕНО: последняя часть точно заканчивается на конце видео
        final endTime =
            (index == parts - 1) ? duration : partDuration * (index + 1);

        return VideoSegment(
          startTime: startTime,
          endTime: endTime,
          fileName:
              'part_${(index + 1).toString().padLeft(2, '0')}.$_outputFormat',
        );
      });
    });

    // Лог для отладки
    print('=== РАСЧЕТ РАВНЫХ ЧАСТЕЙ ===');
    print('Общая длительность: ${_formatDuration(duration)}');
    print('Количество частей: $parts');
    print('Длительность части: ${_formatDuration(partDuration)}');
    for (int i = 0; i < _segments.length; i++) {
      final segment = _segments[i];
      print(
          'Часть ${i + 1}: ${_formatDuration(segment.startTime)} → ${_formatDuration(segment.endTime)} (${_formatDuration(segment.duration)})');
    }
    print('==============================');
  }

  // ИСПРАВЛЕН: основной метод нарезки
  Future<void> _startSlicing() async {
    if (_segments.isEmpty ||
        _inputVideoPath == null ||
        _outputDirectory == null) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _progressPercentage = 0.0;
    });

    try {
      final executableManager = ExecutableManager.instance;
      final ffmpegPath = executableManager.ffmpegPath;

      // ВСЕГДА используем индивидуальную нарезку каждой части
      switch (_slicingType) {
        case SlicingType.overlapping:
          await _sliceOverlapping(ffmpegPath);
          break;
        case SlicingType.equal2:
        case SlicingType.equal3:
        case SlicingType.equal4:
          await _sliceIndividualParts(ffmpegPath);
          break;
      }

      setState(() {
        _currentProgress = 'Нарезка завершена успешно!';
        _progressPercentage = 100.0;
        _isProcessing = false;
      });

      // Проверяем что все файлы созданы
      final createdFiles = <String>[];
      for (final segment in _segments) {
        final filePath = path.join(_outputDirectory!, segment.fileName);
        if (await File(filePath).exists()) {
          createdFiles.add(segment.fileName);
        }
      }

      _showSuccessDialog(
        'Успех!',
        'Видео успешно нарезано на ${_segments.length} частей.\n'
            'Создано файлов: ${createdFiles.length}\n'
            'Файлы: ${createdFiles.join(', ')}\n'
            'Папка: $_outputDirectory',
      );
    } catch (e) {
      setState(() {
        _currentProgress = 'Ошибка нарезки: $e';
        _progressPercentage = 0.0;
        _isProcessing = false;
      });
      print('❌ Полная ошибка нарезки: $e');
      _showErrorDialog('Ошибка нарезки', e.toString());
    }
  }

  // ИСПРАВЛЕН: нарезка перекрывающихся сегментов
  Future<void> _sliceOverlapping(String ffmpegPath) async {
    for (int i = 0; i < _segments.length; i++) {
      final segment = _segments[i];
      final outputPath = path.join(_outputDirectory!, segment.fileName);

      setState(() {
        _currentProgress =
            'Нарезка сегмента ${i + 1} из ${_segments.length}...';
        _progressPercentage = (i / _segments.length) * 100;
      });

      final args = [
        '-ss',
        _formatFFmpegTime(segment.startTime),
        '-i',
        _inputVideoPath!,
        '-t',
        _formatFFmpegTime(segment.duration),
        '-c:v',
        'libx264',
        '-c:a',
        'aac',
        '-avoid_negative_ts',
        'make_zero',
        '-reset_timestamps',
        '1',
        '-y',
        outputPath,
      ];

      print('FFmpeg команда сегмент ${i + 1}: ${args.join(' ')}');

      final result = await Process.run(
        ffmpegPath,
        args,
        runInShell: Platform.isWindows,
      );

      if (result.exitCode != 0) {
        print('FFmpeg stderr: ${result.stderr}');
        throw Exception('Ошибка нарезки сегмента ${i + 1}: ${result.stderr}');
      }

      // Проверяем что файл создался
      final outputFile = File(outputPath);
      if (!await outputFile.exists()) {
        throw Exception('Файл сегмента ${i + 1} не был создан: $outputPath');
      }

      print(
          '✅ Создан сегмент ${i + 1}: ${segment.fileName} (${_formatDuration(segment.duration)})');
    }
  }

  // ИСПРАВЛЕН: нарезка равных частей
  Future<void> _sliceIndividualParts(String ffmpegPath) async {
    for (int i = 0; i < _segments.length; i++) {
      final segment = _segments[i];
      final outputPath = path.join(_outputDirectory!, segment.fileName);

      setState(() {
        _currentProgress = 'Нарезка части ${i + 1} из ${_segments.length}...';
        _progressPercentage = (i / _segments.length) * 100;
      });

      // ИСПРАВЛЕНЫ аргументы FFmpeg для точной нарезки
      final args = [
        '-ss', _formatFFmpegTime(segment.startTime),
        '-i', _inputVideoPath!,
        '-t', _formatFFmpegTime(segment.duration),
        '-c:v', 'libx264', // Перекодируем для точности
        '-c:a', 'aac',
        '-avoid_negative_ts', 'make_zero',
        '-reset_timestamps', '1', // Сбрасываем временные метки
        '-y',
        outputPath,
      ];

      print('FFmpeg команда часть ${i + 1}: ${args.join(' ')}');

      final result = await Process.run(
        ffmpegPath,
        args,
        runInShell: Platform.isWindows,
      );

      if (result.exitCode != 0) {
        print('FFmpeg stderr: ${result.stderr}');
        throw Exception('Ошибка нарезки части ${i + 1}: ${result.stderr}');
      }

      // ДОБАВЛЕНО: проверяем что файл создался
      final outputFile = File(outputPath);
      if (!await outputFile.exists()) {
        throw Exception('Файл части ${i + 1} не был создан: $outputPath');
      }

      print(
          '✅ Создана часть ${i + 1}: ${segment.fileName} (${_formatDuration(segment.duration)})');
    }
  }

  // Методы для работы с файлами
  Future<void> _selectInputVideo() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        dialogTitle: 'Выберите видео для нарезки',
      );

      if (result != null && result.files.single.path != null) {
        final videoPath = result.files.single.path!;
        setState(() => _inputVideoPath = videoPath);
        await _analyzeVideo(videoPath);
      }
    } catch (e) {
      _showErrorDialog('Ошибка выбора файла', e.toString());
    }
  }

  Future<void> _selectOutputDirectory() async {
    try {
      String? result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Выберите папку для сохранения частей',
      );

      if (result != null) {
        setState(() => _outputDirectory = result);
      }
    } catch (e) {
      _showErrorDialog('Ошибка выбора папки', e.toString());
    }
  }

  Future<void> _analyzeVideo(String videoPath) async {
    try {
      setState(() {
        _currentProgress = 'Анализ видео...';
        _progressPercentage = 10.0;
      });

      final executableManager = ExecutableManager.instance;
      final ffmpegPath = executableManager.ffmpegPath;

      final result = await Process.run(
        ffmpegPath,
        ['-i', videoPath, '-hide_banner'],
        runInShell: Platform.isWindows,
      );

      final output = result.stderr.toString();

      final durationRegex =
          RegExp(r'Duration: (\d{2}):(\d{2}):(\d{2})\.(\d{2})');
      final resolutionRegex = RegExp(r'(\d{3,})x(\d{3,})');
      final fpsRegex = RegExp(r'(\d+(?:\.\d+)?)\s*fps');

      final durationMatch = durationRegex.firstMatch(output);
      final resolutionMatch = resolutionRegex.firstMatch(output);
      final fpsMatch = fpsRegex.firstMatch(output);

      double duration = 0.0;
      if (durationMatch != null) {
        final hours = int.parse(durationMatch.group(1)!);
        final minutes = int.parse(durationMatch.group(2)!);
        final seconds = int.parse(durationMatch.group(3)!);
        final centiseconds = int.parse(durationMatch.group(4)!);
        duration =
            (hours * 3600) + (minutes * 60) + seconds + (centiseconds / 100);
      }

      final width =
          resolutionMatch != null ? int.parse(resolutionMatch.group(1)!) : 1920;
      final height =
          resolutionMatch != null ? int.parse(resolutionMatch.group(2)!) : 1080;
      final fps = fpsMatch != null ? double.parse(fpsMatch.group(1)!) : 30.0;

      setState(() {
        _videoInfo = {
          'duration': duration,
          'width': width,
          'height': height,
          'fps': fps,
        };
        _currentProgress = 'Видео проанализировано';
        _progressPercentage = 100.0;
      });

      _calculateSegments();
    } catch (e) {
      setState(() {
        _currentProgress = 'Ошибка анализа видео';
        _progressPercentage = 0.0;
      });
      _showErrorDialog('Ошибка анализа видео', e.toString());
    }
  }

  void _stopSlicing() {
    setState(() {
      _isProcessing = false;
      _currentProgress = 'Операция остановлена';
      _progressPercentage = 0.0;
    });
  }

  // Вспомогательные методы
  Color _getSegmentColor(int index) {
    final colors = [Colors.blue, Colors.green, Colors.orange, Colors.purple];
    return colors[(index - 1) % colors.length];
  }

  String _formatDuration(double seconds) {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '${minutes}:${remainingSeconds.toStringAsFixed(2).padLeft(5, '0')}';
  }

  // ИСПРАВЛЕН: более точное форматирование времени для FFmpeg
  String _formatFFmpegTime(double seconds) {
    final hours = (seconds / 3600).floor();
    final minutes = ((seconds % 3600) / 60).floor();
    final remainingSeconds = seconds % 60;

    // Используем 3 знака после запятой для большей точности
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toStringAsFixed(3).padLeft(6, '0')}';
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (Platform.isWindows) {
                Process.run('explorer', [_outputDirectory!]);
              } else if (Platform.isMacOS) {
                Process.run('open', [_outputDirectory!]);
              } else {
                Process.run('xdg-open', [_outputDirectory!]);
              }
            },
            child: const Text('Открыть папку'),
          ),
        ],
      ),
    );
  }
}

// Модель сегмента видео
class VideoSegment {
  final double startTime;
  final double endTime;
  final String fileName;

  VideoSegment({
    required this.startTime,
    required this.endTime,
    required this.fileName,
  });

  double get duration => endTime - startTime;
}
