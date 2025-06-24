import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:video_upscaler/services/executable_manager.dart';
import 'package:video_upscaler/services/video_processing_service.dart';
import 'package:video_upscaler/services/system_info_service.dart';
import 'package:video_upscaler/models/processing_config.dart';

void main() {
  runApp(VideoUpscalerApp());
}

class VideoUpscalerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Upscaler Pro',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.light,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: VideoUpscalerHome(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class VideoUpscalerHome extends StatefulWidget {
  @override
  _VideoUpscalerHomeState createState() => _VideoUpscalerHomeState();
}

class _VideoUpscalerHomeState extends State<VideoUpscalerHome>
    with TickerProviderStateMixin {
  final VideoProcessingService _processingService = VideoProcessingService();
  late TabController _tabController;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // State variables
  String? _inputVideoPath;
  String? _outputVideoPath;
  bool _isInitialized = false;
  String _currentProgress = 'Запуск приложения...';
  double _progressPercentage = 0.0;
  Map<String, dynamic>? _systemInfo;
  Map<String, dynamic>? _videoInfo;

  // Settings - ОБНОВЛЕНЫ с валидацией
  int _scaleFactor = 2;
  int _scaleNoise = 1;
  String _modelType = 'cunet';
  int _framerate = 30;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _initializeApp();
    _setupStreamListeners();
  }

  void _setupStreamListeners() {
    _processingService.progressStream.listen((progress) {
      if (mounted) {
        setState(() {
          _currentProgress = progress;
        });
      }
    });

    _processingService.percentageStream.listen((percentage) {
      if (mounted) {
        setState(() {
          _progressPercentage = percentage;
        });
      }
    });
  }

  Future<void> _initializeApp() async {
    try {
      setState(() {
        _currentProgress = 'Инициализация ExecutableManager...';
        _progressPercentage = 10.0;
      });

      await ExecutableManager().initializeExecutables();

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

      _animationController.forward();

      // НОВОЕ: автоматически применяем оптимальные настройки под железо
      _applyOptimalSettings();

      print('=== ПОЛНАЯ ИНФОРМАЦИЯ О СИСТЕМЕ ===');
      print('Основная: ${systemDetails['system_details']}');
      print('Железо: ${systemDetails['hardware_details']}');
      print('Оптимальные настройки: ${systemDetails['optimal_settings']}');
      print('===================================');
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

  // НОВЫЙ МЕТОД: Применение оптимальных настроек
  void _applyOptimalSettings() {
    final optimalSettings =
        _systemInfo?['optimal_settings'] as Map<String, dynamic>?;
    if (optimalSettings != null) {
      setState(() {
        // Применяем только валидные значения
        if (ProcessingConfig.validScaleFactors.contains(2)) {
          _scaleFactor = 2; // Безопасное значение по умолчанию
        }

        if (ProcessingConfig.validNoiselevels.contains(1)) {
          _scaleNoise = 1; // Безопасное значение по умолчанию
        }

        print(
            '✅ Применены оптимальные настройки: scale=${_scaleFactor}x, noise=$_scaleNoise');
      });
    }
  }

  // Система info tab - без изменений
  Widget _buildSystemInfoTab() {
    if (_systemInfo == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          _buildSystemOverviewCard(),
          const SizedBox(height: 16),
          _buildCPUInfoCard(),
          const SizedBox(height: 16),
          _buildMemoryInfoCard(),
          const SizedBox(height: 16),
          _buildGPUInfoCard(),
          const SizedBox(height: 16),
          _buildHardwareDetailsCard(),
          const SizedBox(height: 16),
          _buildOptimalSettingsCard(),
        ],
      ),
    );
  }

  Widget _buildSystemOverviewCard() {
    final systemDetails =
        _systemInfo!['system_details'] as Map<String, dynamic>;
    final cpuInfo = _systemInfo!['cpu_info'] as Map<String, dynamic>;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
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
                    Icons.computer,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Обзор системы',
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      Text(
                        _systemInfo!['platform']?.toString() ?? 'Unknown',
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
            const SizedBox(height: 20),
            _buildInfoRow(
                'Компьютер', systemDetails['computer_name'] ?? 'Unknown'),
            _buildInfoRow('Процессор', cpuInfo['name'] ?? 'Unknown CPU'),
            _buildInfoRow('Архитектура', cpuInfo['architecture'] ?? 'Unknown'),
            _buildInfoRow('Ядер процессора', '${_systemInfo!['cpu_cores']}'),
            if (systemDetails['product_name'] != null)
              _buildInfoRow('Продукт', systemDetails['product_name']),
          ],
        ),
      ),
    );
  }

  Widget _buildCPUInfoCard() {
    final cpuInfo = _systemInfo!['cpu_info'] as Map<String, dynamic>;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
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
                    Icons.memory,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  'Процессор',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildInfoRow('Название', cpuInfo['name'] ?? 'Unknown'),
            _buildInfoRow('Производитель', cpuInfo['vendor'] ?? 'Unknown'),
            _buildInfoRow(
                'Ядра', '${cpuInfo['cores'] ?? _systemInfo!['cpu_cores']}'),
            _buildInfoRow('Архитектура', cpuInfo['architecture'] ?? 'Unknown'),
            if (cpuInfo['frequency'] != null && cpuInfo['frequency'] != 0)
              _buildInfoRow('Частота', '${cpuInfo['frequency']} MHz'),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoryInfoCard() {
    final memoryInfo = _systemInfo!['memory_info'] as Map<String, dynamic>;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
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
                    Icons.storage,
                    color: Theme.of(context).colorScheme.onTertiaryContainer,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  'Память',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (memoryInfo['total_gb'] != null) ...[
              _buildInfoRow('Общая память', '${memoryInfo['total_gb']} GB'),
              if (memoryInfo['usage_percent'] != null)
                _buildMemoryProgressRow(
                    'Использование', memoryInfo['usage_percent']),
            ] else ...[
              _buildInfoRow('Статус', 'Информация недоступна'),
            ],
            if (memoryInfo['total_physical'] != null)
              _buildInfoRow('Физическая память',
                  '${(memoryInfo['total_physical'] / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB'),
          ],
        ),
      ),
    );
  }

  Widget _buildGPUInfoCard() {
    final availableGPUs = _systemInfo!['available_gpus'] as List;
    final hasVulkan = _systemInfo!['has_vulkan'] as bool;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.videogame_asset,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  'Графика',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildInfoRow('Vulkan поддержка', hasVulkan ? 'Да' : 'Нет'),
            _buildInfoRow('GPU устройств', '${availableGPUs.length}'),
            if (availableGPUs.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Доступные GPU:',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              ...availableGPUs.map((gpu) => Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 4),
                    child: Text(
                      '• $gpu',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHardwareDetailsCard() {
    final hardwareDetails =
        _systemInfo?['hardware_details'] as Map<String, dynamic>?;

    if (hardwareDetails?['error'] != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              Icon(Icons.info_outline,
                  size: 48, color: Theme.of(context).colorScheme.secondary),
              const SizedBox(height: 16),
              Text(
                'Детальная информация о железе недоступна',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Основная информация о системе загружена',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final bios = hardwareDetails?['bios'] as Map<String, dynamic>?;
    final motherboard =
        hardwareDetails?['motherboard'] as Map<String, dynamic>?;
    final system = hardwareDetails?['system'] as Map<String, dynamic>?;
    final isVirtualized = hardwareDetails?['virtualization'] as bool?;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.hardware,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  'Детальная информация о железе',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (isVirtualized != null)
              _buildInfoRow('Виртуализация', isVirtualized ? 'Да' : 'Нет'),
            if (bios != null) ...[
              const SizedBox(height: 16),
              Text(
                'BIOS',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              _buildInfoRow('Производитель', bios['vendor'] ?? 'Unknown'),
              _buildInfoRow('Версия', bios['version'] ?? 'Unknown'),
              _buildInfoRow('Дата выпуска', bios['release_date'] ?? 'Unknown'),
            ],
            if (motherboard != null) ...[
              const SizedBox(height: 16),
              Text(
                'Материнская плата',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              _buildInfoRow(
                  'Продукт', motherboard['product_name'] ?? 'Unknown'),
              _buildInfoRow(
                  'Производитель', motherboard['manufacturer'] ?? 'Unknown'),
              _buildInfoRow('Версия', motherboard['version'] ?? 'Unknown'),
            ],
            if (system != null) ...[
              const SizedBox(height: 16),
              Text(
                'Система',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              _buildInfoRow('Семейство', system['family'] ?? 'Unknown'),
              _buildInfoRow('Продукт', system['product_name'] ?? 'Unknown'),
              _buildInfoRow(
                  'Производитель', system['manufacturer'] ?? 'Unknown'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOptimalSettingsCard() {
    final optimalSettings =
        _systemInfo?['optimal_settings'] as Map<String, dynamic>?;

    if (optimalSettings == null) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
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
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  'Рекомендуемые настройки',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildInfoRow(
                'Размер тайла', '${optimalSettings['recommended_tile_size']}'),
            _buildInfoRow(
                'Потоки', '${optimalSettings['recommended_threads']}'),
            _buildInfoRow(
                'Использовать GPU', optimalSettings['use_gpu'] ? 'Да' : 'Нет'),
            _buildInfoRow('GPU устройство', '${optimalSettings['gpu_device']}'),
            _buildInfoRow('Память', '${optimalSettings['memory_gb']} GB'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryProgressRow(String label, int percentage) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              Text(
                '$percentage%',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: percentage / 100.0,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(
              percentage > 80
                  ? Theme.of(context).colorScheme.error
                  : percentage > 60
                      ? Colors.orange
                      : Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  // СОВРЕМЕННАЯ секция выбора файлов с анализом видео
  Widget _buildFilesTab() {
    return Column(
      children: [
        _buildFileCard(
          title: 'Входное видео',
          icon: Icons.video_file,
          path: _inputVideoPath,
          placeholder: 'Видео не выбрано',
          onTap: _selectInputVideo,
        ),
        const SizedBox(height: 16),

        // НОВОЕ: Информация о выбранном видео
        if (_videoInfo != null) _buildVideoInfoCard(),

        const SizedBox(height: 16),
        _buildFileCard(
          title: 'Выходное видео',
          icon: Icons.save,
          path: _outputVideoPath,
          placeholder: 'Путь не выбран',
          onTap: _selectOutputPath,
        ),
      ],
    );
  }

  // НОВЫЙ МЕТОД: Карточка с информацией о видео
  Widget _buildVideoInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
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
                    Icons.movie,
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
                    child: _buildVideoStat('Разрешение',
                        '${_videoInfo!['width']}x${_videoInfo!['height']}')),
                Expanded(
                    child: _buildVideoStat('FPS', '${_videoInfo!['fps']}')),
                Expanded(
                    child: _buildVideoStat(
                        'Битрейт', '${_videoInfo!['bitrate']} kb/s')),
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

  Widget _buildFileCard({
    required String title,
    required IconData icon,
    required String? path,
    required String placeholder,
    required VoidCallback onTap,
  }) {
    final hasFile = path != null;

    return Card(
      child: InkWell(
        onTap: _processingService.isProcessing ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: hasFile
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon,
                        color: hasFile
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          hasFile
                              ? path.split(Platform.pathSeparator).last
                              : placeholder,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
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
            ],
          ),
        ),
      ),
    );
  }

  // ОБНОВЛЕННАЯ секция настроек с валидацией
  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Настройки обработки',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 24),

              // ОБНОВЛЕНО: Масштаб - только валидные значения
              _buildDiscreteSelector(
                'Масштаб',
                _scaleFactor,
                ProcessingConfig.validScaleFactors,
                (value) => setState(() => _scaleFactor = value),
                (value) => '${value}x',
              ),

              // ОБНОВЛЕНО: Шумоподавление - только валидные значения
              _buildDiscreteSelector(
                'Шумоподавление',
                _scaleNoise,
                ProcessingConfig.validNoiselevels,
                (value) => setState(() => _scaleNoise = value),
                (value) => value == -1 ? 'Нет' : value.toString(),
              ),

              // Модель
              _buildModelSelector(),

              // FPS
              _buildSettingSlider(
                'FPS',
                _framerate.toDouble(),
                24,
                60,
                6,
                _framerate.toString(),
                (value) => setState(() => _framerate = value.toInt()),
              ),

              // НОВОЕ: Статус конфигурации
              const SizedBox(height: 20),
              _buildConfigStatusCard(),
            ],
          ),
        ),
      ),
    );
  }

  // НОВЫЙ МЕТОД: Селектор дискретных значений
  Widget _buildDiscreteSelector<T>(
    String label,
    T currentValue,
    List<T> validValues,
    ValueChanged<T> onChanged,
    String Function(T) displayText,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  displayText(currentValue),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: validValues.map((value) {
              final isSelected = value == currentValue;
              return FilterChip(
                label: Text(displayText(value)),
                selected: isSelected,
                onSelected: _processingService.isProcessing
                    ? null
                    : (selected) {
                        if (selected) onChanged(value);
                      },
                selectedColor: Theme.of(context).colorScheme.primaryContainer,
                checkmarkColor:
                    Theme.of(context).colorScheme.onPrimaryContainer,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildModelSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Модель ИИ',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'cunet', label: Text('CUNet')),
              ButtonSegment(value: 'anime', label: Text('Anime')),
              ButtonSegment(value: 'photo', label: Text('Photo')),
            ],
            selected: {_modelType},
            onSelectionChanged: _processingService.isProcessing
                ? null
                : (value) {
                    setState(() => _modelType = value.first);
                  },
          ),
          const SizedBox(height: 8),
          Text(
            ModelTypes.getDescription(_modelType),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingSlider(
    String label,
    double value,
    double min,
    double max,
    int divisions,
    String displayValue,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
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
                  displayValue,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: _processingService.isProcessing ? null : onChanged,
          ),
        ],
      ),
    );
  }

  // НОВЫЙ МЕТОД: Карточка статуса конфигурации
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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isValid && isCompatible
            ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
            : Theme.of(context).colorScheme.errorContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isValid && isCompatible
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.error,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isValid && isCompatible ? Icons.check_circle : Icons.warning,
            color: isValid && isCompatible
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isValid && isCompatible
                      ? 'Конфигурация валидна'
                      : 'Проблемы с конфигурацией',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isValid && isCompatible
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.error,
                      ),
                ),
                if (!isValid || !isCompatible)
                  Text(
                    'Некорректные параметры будут исправлены автоматически',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
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

  // Современная секция прогресса
  Widget _buildProgressTab() {
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
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
                        color:
                            Theme.of(context).colorScheme.onSecondaryContainer,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Прогресс обработки',
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
                    Text(
                      '${_progressPercentage.toStringAsFixed(1)}%',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: (!_isInitialized || _processingService.isProcessing)
                ? null
                : _startProcessing,
            icon: _processingService.isProcessing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(
              _processingService.isProcessing
                  ? 'Обработка...'
                  : 'Начать обработку',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
        if (_processingService.isProcessing) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _processingService.stopProcessing(),
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

  // ОБНОВЛЕННЫЕ методы выбора файлов
  Future<void> _selectInputVideo() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        dialogTitle: 'Выберите видео для обработки',
      );

      if (result != null && result.files.single.path != null) {
        final videoPath = result.files.single.path!;
        setState(() => _inputVideoPath = videoPath);

        // НОВОЕ: анализируем выбранное видео
        try {
          final videoInfo = await _processingService.getVideoInfo(videoPath);
          setState(() => _videoInfo = videoInfo);
          print('Информация о выбранном видео: $videoInfo');
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

  // ОБНОВЛЕННЫЙ метод запуска обработки с валидацией
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
      final config = ProcessingConfig(
        inputVideoPath: _inputVideoPath!,
        outputPath: _outputVideoPath!,
        scaleNoise: _scaleNoise,
        scaleFactor: _scaleFactor,
        framerate: _framerate,
        modelType: _modelType,
      );

      // НОВОЕ: Проверяем валидность конфигурации
      final errors = ConfigValidator.validateConfig(config);
      if (errors.isNotEmpty) {
        _showErrorDialog('Ошибка конфигурации', errors.join('\n'));
        return;
      }

      print('✅ Конфигурация валидна: $config');

      final outputPath = await _processingService.processVideo(config);

      if (mounted) {
        _showSuccessDialog('Успех!', 'Видео успешно обработано:\n$outputPath');
      }
    } catch (e) {
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
  Widget build(BuildContext context) {
    return Scaffold(
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
          child: Column(
            children: [
              // Современный AppBar
              Container(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.video_settings,
                        color: Theme.of(context).colorScheme.onPrimary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Video Upscaler Pro',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Text(
                          'AI-powered video enhancement',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Табы
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: Theme.of(context).colorScheme.onPrimary,
                  unselectedLabelColor:
                      Theme.of(context).colorScheme.onSurfaceVariant,
                  tabs: const [
                    Tab(text: 'Система'),
                    Tab(text: 'Файлы'),
                    Tab(text: 'Настройки'),
                    Tab(text: 'Прогресс'),
                  ],
                ),
              ),

              // Контент табов
              Expanded(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildSystemInfoTab(),
                        _buildFilesTab(),
                        _buildSettingsTab(),
                        _buildProgressTab(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _processingService.dispose();
    _tabController.dispose();
    _animationController.dispose();
    super.dispose();
  }
}
