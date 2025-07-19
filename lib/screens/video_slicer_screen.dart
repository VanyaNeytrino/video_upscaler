import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
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

class _VideoSlicerScreenState extends State<VideoSlicerScreen>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _cardAnimationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _cardScaleAnimation;

  String? _inputVideoPath;
  String? _outputDirectory;
  Map<String, dynamic>? _videoInfo;
  List<VideoSegment> _segments = [];

  bool _isProcessing = false;
  String _currentProgress = 'Готов к работе';
  double _progressPercentage = 0.0;

  // Настройки
  SlicingType _slicingType = SlicingType.equal2;
  double _baseDuration = 5.0;
  String _outputFormat = 'mp4';

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startAnimations();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _cardAnimationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    _cardScaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(
        parent: _cardAnimationController,
        curve: Curves.easeOutBack,
      ),
    );
  }

  void _startAnimations() {
    _animationController.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      _cardAnimationController.forward();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _cardAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Нарезка видео'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context)
                  .colorScheme
                  .secondaryContainer
                  .withOpacity(0.15),
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.tertiaryContainer.withOpacity(0.1),
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(24),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _buildAnimatedCard(_buildHeaderCard()),
                        const SizedBox(height: 20),
                        _buildAnimatedCard(_buildSlicingTypeSelector()),
                        const SizedBox(height: 20),
                        _buildAnimatedCard(_buildInputSection()),
                        const SizedBox(height: 20),
                        if (_videoInfo != null) ...[
                          _buildAnimatedCard(_buildVideoInfoCard()),
                          const SizedBox(height: 20),
                        ],
                        if (_segments.isNotEmpty) ...[
                          _buildAnimatedCard(_buildSegmentsPreview()),
                          const SizedBox(height: 20),
                        ],
                        _buildAnimatedCard(_buildSettingsSection()),
                        const SizedBox(height: 20),
                        _buildAnimatedCard(_buildProgressSection()),
                        const SizedBox(height: 20),
                        _buildAnimatedCard(_buildActionButtons()),
                        const SizedBox(height: 32),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedCard(Widget child) {
    return AnimatedBuilder(
      animation: _cardScaleAnimation,
      builder: (context, _) {
        return Transform.scale(
          scale: _cardScaleAnimation.value,
          child: child,
        );
      },
    );
  }

  Widget _buildHeaderCard() {
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
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.secondary,
                          Theme.of(context).colorScheme.secondaryContainer,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context)
                              .colorScheme
                              .secondary
                              .withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      _getSlicingTypeIcon(_slicingType),
                      color: Theme.of(context).colorScheme.onSecondary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Нарезка видео',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.3,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _slicingType.title,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
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
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _slicingType.description,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlicingTypeSelector() {
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
          padding: const EdgeInsets.all(24),
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
                      Icons.tune,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Тип нарезки',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildSlicingTypeGrid(),
              const SizedBox(height: 20),
              _buildSlicingVisualization(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlicingTypeGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.5,
      children: SlicingType.values.map((type) {
        final isSelected = _slicingType == type;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _isProcessing
                ? null
                : () {
                    setState(() {
                      _slicingType = type;
                      if (_videoInfo != null) {
                        _calculateSegments();
                      }
                    });
                  },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                color: isSelected
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline.withOpacity(0.2),
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _getSlicingTypeIcon(type),
                      color: isSelected
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      type.title,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInputSection() {
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
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.folder_open,
                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Выбор файлов',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildModernFileSelector(
                title: 'Входное видео',
                path: _inputVideoPath,
                placeholder: 'Выберите видео для нарезки',
                icon: Icons.video_file,
                onTap: _selectInputVideo,
              ),
              const SizedBox(height: 16),
              _buildModernFileSelector(
                title: 'Папка для сохранения',
                path: _outputDirectory,
                placeholder: 'Выберите папку для частей',
                icon: Icons.folder,
                onTap: _selectOutputDirectory,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernFileSelector({
    required String title,
    required String? path,
    required String placeholder,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final hasFile = path != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isProcessing ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: hasFile
                ? Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withOpacity(0.3)
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasFile
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                  : Theme.of(context).colorScheme.outline.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: hasFile
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: hasFile
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
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
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
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
      ),
    );
  }

  Widget _buildVideoInfoCard() {
    final duration = _videoInfo!['duration'] as double;
    final width = _videoInfo!['width'] as int;
    final height = _videoInfo!['height'] as int;
    final fps = _videoInfo!['fps'] as double;

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
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.info,
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Информация о видео',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _buildVideoStat(
                      'Длительность',
                      _formatDuration(duration),
                      Icons.schedule,
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Expanded(
                    child: _buildVideoStat(
                      'Разрешение',
                      '${width}x${height}',
                      Icons.aspect_ratio,
                      Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                  Expanded(
                    child: _buildVideoStat(
                      'FPS',
                      fps.toStringAsFixed(1),
                      Icons.speed,
                      Theme.of(context).colorScheme.tertiary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoStat(
      String label, String value, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: color,
            size: 24,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentsPreview() {
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
          padding: const EdgeInsets.all(24),
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
                      Icons.preview,
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
                          'Предварительный просмотр',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        Text(
                          '${_segments.length} ${_slicingType.title.toLowerCase()}',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
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
              ..._segments.asMap().entries.map((entry) {
                final index = entry.key;
                final segment = entry.value;
                return _buildModernSegmentCard(index + 1, segment);
              }).toList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernSegmentCard(int index, VideoSegment segment) {
    final color = _getSegmentColor(index);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, color.withOpacity(0.7)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                '$index',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              segment.fileName,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
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
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.settings,
                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Настройки',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_slicingType == SlicingType.overlapping) ...[
                Row(
                  children: [
                    Expanded(
                      child: _buildModernTextField(
                        label: 'Базовая длительность (сек)',
                        value: _baseDuration.toString(),
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
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildModernDropdown(),
                    ),
                  ],
                ),
              ] else ...[
                _buildModernDropdown(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernTextField({
    required String label,
    required String value,
    required Function(String) onChanged,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        TextField(
          enabled: !_isProcessing,
          keyboardType: keyboardType,
          controller: TextEditingController(text: value),
          onChanged: onChanged,
          decoration: InputDecoration(
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
      ],
    );
  }

  Widget _buildModernDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Формат вывода',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _outputFormat,
          decoration: InputDecoration(
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.all(16),
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
    );
  }

  Widget _buildProgressSection() {
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
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.timeline,
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Прогресс',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              LinearProgressIndicator(
                value: _progressPercentage / 100,
                borderRadius: BorderRadius.circular(8),
                minHeight: 8,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _currentProgress,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_progressPercentage.toStringAsFixed(1)}%',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    final canProcess = _inputVideoPath != null &&
        _outputDirectory != null &&
        _segments.isNotEmpty &&
        !_isProcessing;

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
          padding: const EdgeInsets.all(24),
          child: Column(
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
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
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
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      foregroundColor: Theme.of(context).colorScheme.error,
                      side: BorderSide(
                          color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Остальные методы остаются такими же...
  IconData _getSlicingTypeIcon(SlicingType type) {
    // Изменено: возвращаем IconData
    switch (type) {
      case SlicingType.overlapping:
        return Icons.layers; // Убираем Icon(), оставляем только IconData
      case SlicingType.equal2:
        return Icons.vertical_split;
      case SlicingType.equal3:
        return Icons.view_column;
      case SlicingType.equal4:
        return Icons.grid_view;
    }
  }

  Widget _buildSlicingVisualization() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Схема нарезки:',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          switch (_slicingType) {
            SlicingType.overlapping => _buildOverlappingVisualization(),
            SlicingType.equal2 => _buildEqualPartsVisualization(2),
            SlicingType.equal3 => _buildEqualPartsVisualization(3),
            SlicingType.equal4 => _buildEqualPartsVisualization(4),
          },
        ],
      ),
    );
  }

  Widget _buildOverlappingVisualization() {
    return Column(
      children: [
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
      children: List.generate(parts, (index) {
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
            height: 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: MediaQuery.of(context).size.width * 0.4 * offset,
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.4 * width,
                    height: 28,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color, color.withOpacity(0.7)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: color.withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        time,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
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

  // Сохраняем все остальные методы без изменений...
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

  void _calculateEqualParts(double duration, int parts) {
    final partDuration = duration / parts;

    setState(() {
      _segments = List.generate(parts, (index) {
        final startTime = partDuration * index;
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
  }

  // Остальные методы остаются без изменений...
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
      _showErrorDialog('Ошибка нарезки', e.toString());
    }
  }

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

      final result =
          await Process.run(ffmpegPath, args, runInShell: Platform.isWindows);

      if (result.exitCode != 0) {
        throw Exception('Ошибка нарезки сегмента ${i + 1}: ${result.stderr}');
      }

      final outputFile = File(outputPath);
      if (!await outputFile.exists()) {
        throw Exception('Файл сегмента ${i + 1} не был создан: $outputPath');
      }
    }
  }

  Future<void> _sliceIndividualParts(String ffmpegPath) async {
    for (int i = 0; i < _segments.length; i++) {
      final segment = _segments[i];
      final outputPath = path.join(_outputDirectory!, segment.fileName);

      setState(() {
        _currentProgress = 'Нарезка части ${i + 1} из ${_segments.length}...';
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

      final result =
          await Process.run(ffmpegPath, args, runInShell: Platform.isWindows);

      if (result.exitCode != 0) {
        throw Exception('Ошибка нарезки части ${i + 1}: ${result.stderr}');
      }

      final outputFile = File(outputPath);
      if (!await outputFile.exists()) {
        throw Exception('Файл части ${i + 1} не был создан: $outputPath');
      }
    }
  }

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

  Color _getSegmentColor(int index) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
    ];
    return colors[(index - 1) % colors.length];
  }

  String _formatDuration(double seconds) {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '${minutes}:${remainingSeconds.toStringAsFixed(2).padLeft(5, '0')}';
  }

  String _formatFFmpegTime(double seconds) {
    final hours = (seconds / 3600).floor();
    final minutes = ((seconds % 3600) / 60).floor();
    final remainingSeconds = seconds % 60;
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
