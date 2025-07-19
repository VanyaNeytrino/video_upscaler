import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:video_upscaler/services/executable_manager.dart';
import 'package:video_upscaler/services/video_processing_service.dart';
import 'package:video_upscaler/services/system_info_service.dart';
import 'package:video_upscaler/models/processing_config.dart';
import 'package:video_upscaler/services/resource_monitor.dart';
import 'package:video_upscaler/widgets/resource_monitor_widget.dart';
import 'package:video_upscaler/services/file_validator.dart';

class VideoUpscalerScreen extends StatefulWidget {
  const VideoUpscalerScreen({Key? key}) : super(key: key);

  @override
  State<VideoUpscalerScreen> createState() => _VideoUpscalerScreenState();
}

class _VideoUpscalerScreenState extends State<VideoUpscalerScreen>
    with TickerProviderStateMixin {
  final VideoProcessingService _processingService = VideoProcessingService();
  late TabController _tabController;
  late AnimationController _animationController;
  late AnimationController _cardAnimationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _cardScaleAnimation;
  late Animation<double> _rotationAnimation;

  // State variables
  String? _inputVideoPath;
  String? _outputVideoPath;
  bool _isInitialized = false;
  String _currentProgress = 'Запуск приложения...';
  double _progressPercentage = 0.0;
  Map<String, dynamic>? _systemInfo;
  Map<String, dynamic>? _videoInfo;

  // Settings
  int _scaleFactor = 2;
  int _scaleNoise = 1;
  String _modelType = 'cunet';
  int _framerate = 30;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initializeApp();
    _setupStreamListeners();
  }

  void _setupAnimations() {
    _tabController = TabController(length: 4, vsync: this);

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    );

    _cardAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOutExpo),
    ));

    _cardScaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(
        parent: _cardAnimationController,
        curve: Curves.elasticOut,
      ),
    );

    _rotationAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _setupStreamListeners() {
    _processingService.progressStream.listen((progress) {
      if (mounted) {
        setState(() => _currentProgress = progress);
      }
    });

    _processingService.percentageStream.listen((percentage) {
      if (mounted) {
        setState(() => _progressPercentage = percentage);
      }
    });
  }

  Future<void> _initializeApp() async {
    try {
      setState(() {
        _currentProgress = 'Инициализация ExecutableManager...';
        _progressPercentage = 10.0;
      });

      await ExecutableManager.instance.initializeExecutables();

      setState(() {
        _currentProgress = 'Анализ системы и железа...';
        _progressPercentage = 50.0;
      });

      final systemDetails = await SystemInfoService.getSystemDetails();

      setState(() {
        _currentProgress = 'Приложение готово к работе';
        _progressPercentage = 100.0;
        _isInitialized = true;
        _systemInfo = systemDetails;
      });

      // Запускаем анимации
      _animationController.forward();
      await Future.delayed(const Duration(milliseconds: 300));
      _cardAnimationController.forward();

      _applyOptimalSettings();
    } catch (e) {
      setState(() {
        _currentProgress = 'Ошибка инициализации: $e';
        _progressPercentage = 0.0;
        _isInitialized = false;
      });
      if (mounted) {
        _showErrorDialog('Ошибка инициализации', e.toString());
      }
    }
  }

  void _applyOptimalSettings() {
    final optimalSettings =
        _systemInfo?['optimal_settings'] as Map<String, dynamic>?;
    if (optimalSettings != null) {
      setState(() {
        if (ProcessingConfig.validScaleFactors.contains(2)) {
          _scaleFactor = 2;
        }
        if (ProcessingConfig.validNoiselevels.contains(1)) {
          _scaleNoise = 1;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primaryContainer.withOpacity(0.08),
              Theme.of(context).colorScheme.surface,
              Theme.of(context)
                  .colorScheme
                  .secondaryContainer
                  .withOpacity(0.05),
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Column(
                children: [
                  _buildModernAppBar(),
                  _buildModernTabBar(),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _cardScaleAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _cardScaleAnimation.value,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: TabBarView(
                              controller: _tabController,
                              physics: const BouncingScrollPhysics(),
                              children: [
                                _buildSystemInfoTab(),
                                _buildFilesTab(),
                                _buildSettingsTab(),
                                _buildProgressTab(),
                              ],
                            ),
                          ),
                        );
                      },
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

  Widget _buildModernAppBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: Row(
        children: [
          // Кнопка назад с современным дизайном
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.shadow.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              onPressed: () => Navigator.of(context).pop(),
              style: IconButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),
          // Заголовок с иконкой
          Expanded(
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: _rotationAnimation,
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: _rotationAnimation.value * 0.1,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Theme.of(context).colorScheme.primary,
                              Theme.of(context).colorScheme.primaryContainer,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.auto_fix_high,
                          color: Theme.of(context).colorScheme.onPrimary,
                          size: 24,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Video Upscaler',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.5,
                              ),
                    ),
                    Text(
                      'AI Enhancement Studio',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Индикатор статуса
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _isInitialized
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _isInitialized
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.error,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _isInitialized ? 'Готов' : 'Загрузка',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: _isInitialized
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : Theme.of(context).colorScheme.onErrorContainer,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.primaryContainer,
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: const EdgeInsets.all(4),
        dividerColor: Colors.transparent,
        labelColor: Theme.of(context).colorScheme.onPrimary,
        unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
        tabs: const [
          Tab(text: 'Система'),
          Tab(text: 'Файлы'),
          Tab(text: 'Настройки'),
          Tab(text: 'Прогресс'),
        ],
      ),
    );
  }

  Widget _buildSystemInfoTab() {
    if (_systemInfo == null) {
      return _buildLoadingState();
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          _buildSystemOverviewCard(),
          const SizedBox(height: 16),
          _buildSystemStatsGrid(),
          const SizedBox(height: 16),
          _buildOptimalSettingsCard(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
            ),
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Анализ системы...',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Определение оптимальных настроек',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemOverviewCard() {
    return _buildModernCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildCardIcon(
                  Icons.computer, Theme.of(context).colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Обзор системы',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _systemInfo!['platform']?.toString() ?? 'Unknown',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSystemInfoGrid(),
        ],
      ),
    );
  }

  Widget _buildSystemInfoGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.5,
      children: [
        _buildInfoItem('Компьютер', 'Mac Studio', Icons.desktop_mac),
        _buildInfoItem('Процессор', 'Apple M1', Icons.memory),
        _buildInfoItem('Архитектура', 'ARM64', Icons.architecture),
        _buildInfoItem('Ядра', '8', Icons.developer_board),
      ],
    );
  }

  Widget _buildInfoItem(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: Theme.of(context).colorScheme.primary,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemStatsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard('GPU', '1 устройство', Icons.videogame_asset,
            Colors.green, 'Vulkan ✓'),
        _buildStatCard(
            'Память', '16 GB', Icons.storage, Colors.blue, 'Доступна'),
        _buildStatCard(
            'Статус',
            _isInitialized ? 'Готов' : 'Загрузка',
            Icons.check_circle,
            _isInitialized ? Colors.green : Colors.orange,
            _isInitialized ? 'Инициализирован' : 'Ожидание'),
        _buildStatCard('Качество', 'Высокое', Icons.high_quality, Colors.purple,
            'AI Enhanced'),
      ],
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color, String subtitle) {
    return _buildModernCard(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildOptimalSettingsCard() {
    return _buildModernCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildCardIcon(
                  Icons.tune, Theme.of(context).colorScheme.secondary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Оптимальные настройки',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Рекомендуемые для вашего железа',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildSettingsGrid(),
        ],
      ),
    );
  }

  Widget _buildSettingsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2,
      children: [
        _buildSettingItem('Tile Size', '256', Icons.grid_view),
        _buildSettingItem('Threads', '4', Icons.settings),
        _buildSettingItem('GPU', 'Включен', Icons.memory),
        _buildSettingItem('Память', '16 GB', Icons.storage),
      ],
    );
  }

  Widget _buildSettingItem(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: Theme.of(context).colorScheme.secondary,
            size: 20,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.secondary,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilesTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          _buildModernFileCard(
            title: 'Входное видео',
            subtitle: 'Выберите видео для улучшения',
            icon: Icons.video_file,
            path: _inputVideoPath,
            placeholder: 'Нажмите для выбора видео',
            onTap: _selectInputVideo,
            gradientColors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.primaryContainer,
            ],
          ),
          const SizedBox(height: 20),
          if (_videoInfo != null) ...[
            _buildVideoInfoCard(),
            const SizedBox(height: 20),
          ],
          _buildModernFileCard(
            title: 'Выходное видео',
            subtitle: 'Куда сохранить результат',
            icon: Icons.save_alt,
            path: _outputVideoPath,
            placeholder: 'Нажмите для выбора пути',
            onTap: _selectOutputPath,
            gradientColors: [
              Theme.of(context).colorScheme.secondary,
              Theme.of(context).colorScheme.secondaryContainer,
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildModernFileCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required String? path,
    required String placeholder,
    required VoidCallback onTap,
    required List<Color> gradientColors,
  }) {
    final hasFile = path != null;

    return _buildModernCard(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _processingService.isProcessing ? null : onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: gradientColors),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: gradientColors.first.withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        icon,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
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
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: hasFile
                        ? gradientColors.first.withOpacity(0.1)
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: hasFile
                        ? Border.all(
                            color: gradientColors.first.withOpacity(0.3))
                        : null,
                  ),
                  child: Text(
                    hasFile
                        ? path!.split(Platform.pathSeparator).last
                        : placeholder,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: hasFile
                              ? gradientColors.first
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight:
                              hasFile ? FontWeight.w600 : FontWeight.normal,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoInfoCard() {
    return _buildModernCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildCardIcon(
                  Icons.movie, Theme.of(context).colorScheme.tertiary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Информация о видео',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Технические параметры',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildVideoStat(
                  'Разрешение',
                  '${_videoInfo!['width']}x${_videoInfo!['height']}',
                  Icons.aspect_ratio,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildVideoStat(
                  'FPS',
                  '${_videoInfo!['fps']}',
                  Icons.speed,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildVideoStat(
                  'Битрейт',
                  '${_videoInfo!['bitrate']} kb/s',
                  Icons.timeline,
                  Colors.orange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVideoStat(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
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
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          _buildModernCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildCardIcon(
                        Icons.settings, Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Настройки обработки',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Настройте параметры ИИ',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
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
                const SizedBox(height: 24),
                _buildModernSelector(
                  'Масштаб',
                  _scaleFactor,
                  ProcessingConfig.validScaleFactors,
                  (value) => setState(() => _scaleFactor = value),
                  (value) => '${value}x',
                  Icons.zoom_in,
                ),
                const SizedBox(height: 20),
                _buildModernSelector(
                  'Шумоподавление',
                  _scaleNoise,
                  ProcessingConfig.validNoiselevels,
                  (value) => setState(() => _scaleNoise = value),
                  (value) => value == -1 ? 'Выкл' : 'Ур. $value',
                  Icons.auto_fix_high,
                ),
                const SizedBox(height: 20),
                _buildModernModelSelector(),
                const SizedBox(height: 20),
                _buildModernSlider(
                  'Частота кадров',
                  _framerate.toDouble(),
                  24,
                  60,
                  (value) => setState(() => _framerate = value.toInt()),
                  '$_framerate FPS',
                  Icons.video_settings,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildConfigStatusCard(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildModernSelector<T>(
    String label,
    T currentValue,
    List<T> validValues,
    ValueChanged<T> onChanged,
    String Function(T) displayText,
    IconData icon,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.primaryContainer,
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color:
                        Theme.of(context).colorScheme.primary.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                displayText(currentValue),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: validValues.map((value) {
            final isSelected = value == currentValue;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _processingService.isProcessing
                    ? null
                    : () => onChanged(value),
                borderRadius: BorderRadius.circular(20),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context)
                              .colorScheme
                              .outline
                              .withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    displayText(value),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isSelected
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildModernModelSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.psychology,
              color: Theme.of(context).colorScheme.secondary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Модель ИИ',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'cunet',
                label: Text('CUNet'),
                icon: Icon(Icons.all_inclusive, size: 16),
              ),
              ButtonSegment(
                value: 'anime',
                label: Text('Anime'),
                icon: Icon(Icons.animation, size: 16),
              ),
              ButtonSegment(
                value: 'photo',
                label: Text('Photo'),
                icon: Icon(Icons.photo, size: 16),
              ),
            ],
            selected: {_modelType},
            onSelectionChanged: _processingService.isProcessing
                ? null
                : (value) {
                    setState(() => _modelType = value.first);
                  },
            style: SegmentedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.surface,
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              selectedBackgroundColor: Theme.of(context).colorScheme.primary,
              selectedForegroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            ModelTypes.getDescription(_modelType),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildModernSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
    String displayValue,
    IconData icon,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              color: Theme.of(context).colorScheme.tertiary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                displayValue,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
            activeTrackColor: Theme.of(context).colorScheme.primary,
            inactiveTrackColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            thumbColor: Theme.of(context).colorScheme.primary,
            overlayColor:
                Theme.of(context).colorScheme.primary.withOpacity(0.2),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: (max - min).toInt(),
            onChanged: _processingService.isProcessing ? null : onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildConfigStatusCard() {
    final tempConfig = ProcessingConfig(
      inputVideoPath: _inputVideoPath ?? '',
      outputPath: _outputVideoPath ?? '',
      scaleFactor: _scaleFactor,
      scaleNoise: _scaleNoise,
      modelType: _modelType,
      framerate: _framerate,
    );

    final isValid = tempConfig.isValidConfiguration;
    final isCompatible = tempConfig.isModelCompatible();

    return _buildModernCard(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isValid && isCompatible
                  ? Colors.green.withOpacity(0.1)
                  : Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isValid && isCompatible ? Icons.check_circle : Icons.warning,
              color: isValid && isCompatible ? Colors.green : Colors.orange,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isValid && isCompatible
                      ? 'Конфигурация готова'
                      : 'Требуется настройка',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isValid && isCompatible
                            ? Colors.green
                            : Colors.orange,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  isValid && isCompatible
                      ? 'Все параметры корректны'
                      : 'Проверьте настройки модели',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          ResourceMonitorWidget(),
          const SizedBox(height: 20),
          _buildModernCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildCardIcon(
                        Icons.timeline, Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Прогресс обработки',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Отслеживание процесса',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).colorScheme.primary,
                            Theme.of(context).colorScheme.primaryContainer,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '${_progressPercentage.toStringAsFixed(1)}%',
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: FractionallySizedBox(
                    widthFactor: _progressPercentage / 100,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).colorScheme.primary,
                            Theme.of(context).colorScheme.primaryContainer,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _currentProgress,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildActionButtons(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: (!_isInitialized || _processingService.isProcessing)
                ? null
                : _startProcessing,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: _processingService.isProcessing
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  )
                : const Icon(Icons.play_arrow, size: 24),
            label: Text(
              _processingService.isProcessing
                  ? 'Обработка видео...'
                  : 'Начать обработку',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (_processingService.isProcessing) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _processingService.stopProcessing(),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(
                  color: Theme.of(context).colorScheme.error,
                  width: 2,
                ),
              ),
              icon: const Icon(Icons.stop, size: 24),
              label: const Text(
                'Остановить обработку',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // Вспомогательные методы для UI
  Widget _buildModernCard({required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.08),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: child,
      ),
    );
  }

  Widget _buildCardIcon(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.7)],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        icon,
        color: Colors.white,
        size: 20,
      ),
    );
  }

  // Методы для работы с файлами и обработкой
  Future<void> _selectInputVideo() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        dialogTitle: 'Выберите видео для обработки',
      );

      if (result != null && result.files.single.path != null) {
        final videoPath = result.files.single.path!;

        final validation = FileValidator.validateVideoFile(videoPath);

        if (!validation.isValid) {
          _showErrorDialog('Ошибка файла', validation.errors.join('\n'));
          return;
        }

        if (validation.warnings.isNotEmpty) {
          _showWarningDialog('Предупреждение', validation.warnings.join('\n'));
        }

        setState(() => _inputVideoPath = videoPath);

        if (validation.fileSizeMB != null) {
          final recommendations =
              FileValidator.getRecommendations(validation.fileSizeMB!);
          print('💡 Рекомендации: $recommendations');
        }

        try {
          final videoInfo = await _processingService.getVideoInfo(videoPath);
          setState(() => _videoInfo = videoInfo);
        } catch (e) {
          print('Не удалось получить информацию о видео: $e');
        }
      }
    } catch (e) {
      _showErrorDialog('Ошибка выбора файла', e.toString());
    }
  }

  Future<void> _selectOutputPath() async {
    try {
      String? result = await FilePicker.platform.saveFile(
        dialogTitle: 'Выберите путь для сохранения',
        fileName: 'upscaled_video.mp4',
        type: FileType.video,
      );

      if (result != null) {
        setState(() => _outputVideoPath = result);
      }
    } catch (e) {
      _showErrorDialog('Ошибка выбора пути', e.toString());
    }
  }

  Future<void> _startProcessing() async {
    if (!_isInitialized) {
      _showErrorDialog('Ошибка', 'Приложение не инициализировано');
      return;
    }

    if (_inputVideoPath == null || _outputVideoPath == null) {
      _showErrorDialog('Ошибка', 'Выберите входной и выходной файлы');
      return;
    }

    try {
      ResourceMonitor.instance.startMonitoring();

      final config = ProcessingConfig(
        inputVideoPath: _inputVideoPath!,
        outputPath: _outputVideoPath!,
        scaleNoise: _scaleNoise,
        scaleFactor: _scaleFactor,
        framerate: _framerate,
        modelType: _modelType,
      );

      final errors = ConfigValidator.validateConfig(config);
      if (errors.isNotEmpty) {
        _showErrorDialog('Ошибка конфигурации', errors.join('\n'));
        return;
      }

      final outputPath = await _processingService.processVideo(config);

      ResourceMonitor.instance.stopMonitoring();

      if (mounted) {
        _showSuccessDialog('Успех!', 'Видео успешно обработано:\n$outputPath');
      }
    } catch (e) {
      ResourceMonitor.instance.stopMonitoring();

      if (mounted) {
        _showErrorDialog('Ошибка обработки', e.toString());
      }
    }
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

  void _showWarningDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
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
        ],
      ),
    );
  }

  @override
  void dispose() {
    _processingService.dispose();
    _tabController.dispose();
    _animationController.dispose();
    _cardAnimationController.dispose();
    super.dispose();
  }
}

// Заглушки для классов
class ModelTypes {
  static String getDescription(String modelType) {
    switch (modelType) {
      case 'cunet':
        return 'Универсальная модель для любого контента';
      case 'anime':
        return 'Оптимизирована для аниме и рисованного контента';
      case 'photo':
        return 'Специально для фотографий и реалистичного контента';
      default:
        return 'Неизвестная модель';
    }
  }
}

class ConfigValidator {
  static List<String> validateConfig(ProcessingConfig config) {
    List<String> errors = [];

    if (config.inputVideoPath.isEmpty) {
      errors.add('Не выбран входной видеофайл');
    }

    if (config.outputPath.isEmpty) {
      errors.add('Не выбран путь для сохранения');
    }

    if (!ProcessingConfig.validScaleFactors.contains(config.scaleFactor)) {
      errors.add('Неподдерживаемый масштаб: ${config.scaleFactor}x');
    }

    if (!ProcessingConfig.validNoiselevels.contains(config.scaleNoise)) {
      errors
          .add('Неподдерживаемый уровень шумоподавления: ${config.scaleNoise}');
    }

    return errors;
  }
}
