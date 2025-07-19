import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class ExecutableManager {
  static ExecutableManager? _instance;
  static ExecutableManager get instance {
    _instance ??= ExecutableManager._internal();
    return _instance!;
  }

  ExecutableManager._internal();

  Directory? _workingDirectory;
  bool _isInitialized = false;
  bool _useSystemFFmpeg = false;
  Map<String, dynamic>? _hardwareProfile;

  bool get isInitialized => _isInitialized;

  String get modelsDir {
    _checkInitialization();
    return _workingDirectory!.path;
  }

  String get _platform {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    return 'linux';
  }

  String get _executableExtension => Platform.isWindows ? '.exe' : '';

  String get waifu2xPath {
    if (!_isInitialized || _workingDirectory == null) {
      throw Exception('ExecutableManager не инициализирован!');
    }
    return path.join(
        _workingDirectory!.path, 'waifu2x-ncnn-vulkan$_executableExtension');
  }

  String get ffmpegPath {
    if (!_isInitialized || _workingDirectory == null) {
      throw Exception('ExecutableManager не инициализирован!');
    }

    if (_useSystemFFmpeg) {
      return _getSystemFFmpegPath();
    }
    return path.join(_workingDirectory!.path, 'ffmpeg$_executableExtension');
  }

  String get ffprobePath {
    if (!_isInitialized || _workingDirectory == null) {
      throw Exception('ExecutableManager не инициализирован!');
    }
    return path.join(_workingDirectory!.path, 'ffprobe$_executableExtension');
  }

  String getModelPath(String modelType) {
    _checkInitialization();
    final modelFolders = {
      'cunet': 'models-cunet',
      'anime': 'models-upconv_7_anime_style_art_rgb',
      'photo': 'models-upconv_7_photo',
    };

    final modelFolder = modelFolders[modelType] ?? 'models-cunet';
    return path.join(_workingDirectory!.path, modelFolder);
  }

  Future<void> initializeExecutables() async {
    if (_isInitialized) {
      print('✅ ExecutableManager уже инициализирован');
      return;
    }

    print('🔄 Инициализация высокопроизводительного ExecutableManager...');

    try {
      await _setupWorkingDirectory();
      await _detectHardwareProfile(); // НОВОЕ: детекция железа
      await _extractFromAssets();
      await _makeExecutablesExecutable();

      _isInitialized = true;
      print('✅ ExecutableManager базовая инициализация завершена');

      await _validateExecutables();
      await _optimizeForHardware(); // НОВОЕ: железо-специфичная оптимизация

      print(
          '✅ ExecutableManager полностью оптимизирован для высокопроизводительного железа');
    } catch (e) {
      print('❌ Ошибка инициализации ExecutableManager: $e');
      _isInitialized = false;
      rethrow;
    }
  }

  // НОВЫЙ МЕТОД: Детекция конфигурации железа
  Future<void> _detectHardwareProfile() async {
    print('🔍 Анализ железа для максимальной производительности...');

    try {
      Map<String, dynamic> profile = {
        'cpu_cores': Platform.numberOfProcessors,
        'platform': _platform,
        'memory_gb': 16, // Предполагаем 16GB
        'gpu_type': 'unknown',
        'gpu_memory_gb': 8, // RTX 3070 = 8GB
        'is_high_performance': false,
      };

      if (Platform.isWindows) {
        profile = await _detectWindowsHardware(profile);
      } else if (Platform.isMacOS) {
        profile = await _detectMacHardware(profile);
      }

      // Определяем профиль производительности
      final cpuCores = profile['cpu_cores'] as int;
      final gpuMemory = profile['gpu_memory_gb'] as int;

      profile['is_high_performance'] = cpuCores >= 8 && gpuMemory >= 6;
      profile['performance_tier'] = _getPerformanceTier(cpuCores, gpuMemory);

      _hardwareProfile = profile;

      print('🚀 Железо обнаружено: ${profile['performance_tier']} tier');
      print(
          '💾 CPU: ${cpuCores} ядер, GPU: ${gpuMemory}GB, RAM: ${profile['memory_gb']}GB');
    } catch (e) {
      print(
          '⚠️ Не удалось определить железо, используем консервативные настройки: $e');
      _hardwareProfile = {
        'cpu_cores': Platform.numberOfProcessors,
        'platform': _platform,
        'memory_gb': 8,
        'gpu_memory_gb': 4,
        'is_high_performance': false,
        'performance_tier': 'conservative',
      };
    }
  }

  Future<Map<String, dynamic>> _detectWindowsHardware(
      Map<String, dynamic> profile) async {
    try {
      // Детекция GPU через wmic
      final gpuResult = await Process.run('wmic', [
        'path',
        'win32_VideoController',
        'get',
        'name,AdapterRAM',
        '/format:csv'
      ]);

      final gpuOutput = gpuResult.stdout.toString();
      print('🔍 GPU обнаружено: ${gpuOutput.split('\n').take(3).join(' | ')}');

      // Парсим RTX 3070
      if (gpuOutput.toLowerCase().contains('rtx 3070') ||
          gpuOutput.toLowerCase().contains('rtx 30')) {
        profile['gpu_type'] = 'rtx_3070';
        profile['gpu_memory_gb'] = 8;
        print(
            '🎮 Обнаружен RTX 3070 - включаем максимальную производительность!');
      } else if (gpuOutput.toLowerCase().contains('rtx') ||
          gpuOutput.toLowerCase().contains('gtx')) {
        profile['gpu_type'] = 'nvidia_gpu';
        profile['gpu_memory_gb'] = 6; // Консервативная оценка
      }

      // Детекция RAM
      final memResult = await Process.run(
          'wmic', ['computersystem', 'get', 'TotalPhysicalMemory', '/value']);

      final memOutput = memResult.stdout.toString();
      final memMatch =
          RegExp(r'TotalPhysicalMemory=(\d+)').firstMatch(memOutput);

      if (memMatch != null) {
        final totalBytes = int.tryParse(memMatch.group(1) ?? '0') ?? 0;
        profile['memory_gb'] = (totalBytes / 1024 / 1024 / 1024).round();
      }

      return profile;
    } catch (e) {
      print('⚠️ Ошибка детекции Windows железа: $e');
      return profile;
    }
  }

  Future<Map<String, dynamic>> _detectMacHardware(
      Map<String, dynamic> profile) async {
    try {
      // Детекция через system_profiler
      final result =
          await Process.run('system_profiler', ['SPHardwareDataType', '-json']);

      final jsonData = json.decode(result.stdout);
      final hardware = jsonData['SPHardwareDataType'][0];

      final chipName =
          hardware['chip_type'] ?? hardware['cpu_type'] ?? 'Unknown';
      final memoryStr = hardware['physical_memory'] ?? '16 GB';

      print('🍎 Mac обнаружен: $chipName, RAM: $memoryStr');

      // Парсим память
      final memMatch = RegExp(r'(\d+)\s*GB').firstMatch(memoryStr);
      if (memMatch != null) {
        profile['memory_gb'] = int.tryParse(memMatch.group(1) ?? '16') ?? 16;
      }

      // Определяем тип чипа
      if (chipName.toLowerCase().contains('m1') ||
          chipName.toLowerCase().contains('m2') ||
          chipName.toLowerCase().contains('m3')) {
        profile['gpu_type'] = 'apple_silicon';
        profile['gpu_memory_gb'] = profile['memory_gb']; // Unified memory
      }

      return profile;
    } catch (e) {
      print('⚠️ Ошибка детекции Mac железа: $e');
      return profile;
    }
  }

  String _getPerformanceTier(int cpuCores, int gpuMemory) {
    if (cpuCores >= 12 && gpuMemory >= 8) {
      return 'BEAST_MODE'; // i9 + RTX 3070
    } else if (cpuCores >= 8 && gpuMemory >= 6) {
      return 'HIGH_PERFORMANCE';
    } else if (cpuCores >= 6 && gpuMemory >= 4) {
      return 'MEDIUM_PERFORMANCE';
    } else {
      return 'CONSERVATIVE';
    }
  }

  // НОВЫЙ МЕТОД: Оптимизация под конкретное железо
  Future<void> _optimizeForHardware() async {
    if (_hardwareProfile == null) return;

    final tier = _hardwareProfile!['performance_tier'] as String;
    print('⚡ Применяем оптимизацию уровня: $tier');

    switch (tier) {
      case 'BEAST_MODE':
        await _applyBeastModeOptimizations();
        break;
      case 'HIGH_PERFORMANCE':
        await _applyHighPerformanceOptimizations();
        break;
      default:
        await _applyConservativeOptimizations();
    }
  }

  Future<void> _applyBeastModeOptimizations() async {
    print('🔥 BEAST MODE активирован для i9 + RTX 3070!');

    // Предзагрузка шейдеров Vulkan
    await _precompileVulkanShaders();

    // Оптимизация системных настроек
    if (Platform.isWindows) {
      await _optimizeWindowsForPerformance();
    }

    print('🚀 BEAST MODE оптимизации применены');
  }

  Future<void> _precompileVulkanShaders() async {
    try {
      print('🔧 Предкомпиляция Vulkan шейдеров...');

      // Создаем тестовый кадр
      final testImagePath =
          path.join(_workingDirectory!.path, 'test_frame.png');
      final testOutputPath =
          path.join(_workingDirectory!.path, 'test_output.png');

      // Создаем простой черный PNG 256x256
      await _createTestImage(testImagePath);

      // Запускаем waifu2x для прогрева
      final process = await Process.start(waifu2xPath, [
        '-i',
        testImagePath,
        '-o',
        testOutputPath,
        '-n',
        '0',
        '-s',
        '2',
        '-m',
        getModelPath('cunet'),
        '-t',
        '512',
        '-g',
        '0',
        '-v'
      ]);

      await process.exitCode.timeout(Duration(seconds: 30));

      // Удаляем тестовые файлы
      await File(testImagePath).delete().catchError((_) {});
      await File(testOutputPath).delete().catchError((_) {});

      print('✅ Vulkan шейдеры предкомпилированы');
    } catch (e) {
      print('⚠️ Предкомпиляция шейдеров не удалась: $e');
    }
  }

  Future<void> _createTestImage(String imagePath) async {
    // Создаем простейший PNG программно
    const width = 256;
    const height = 256;

    final bytes = Uint8List(width * height * 3); // RGB
    // Заполняем серым цветом
    for (int i = 0; i < bytes.length; i += 3) {
      bytes[i] = 128; // R
      bytes[i + 1] = 128; // G
      bytes[i + 2] = 128; // B
    }

    // Простейший способ - используем FFmpeg для создания тестового изображения
    try {
      await Process.run(ffmpegPath, [
        '-f',
        'lavfi',
        '-i',
        'color=gray:size=256x256:duration=1',
        '-vframes',
        '1',
        '-y',
        imagePath
      ]);
    } catch (e) {
      print('⚠️ Не удалось создать тестовое изображение: $e');
    }
  }

  Future<void> _optimizeWindowsForPerformance() async {
    try {
      print('🔧 Оптимизация Windows для максимальной производительности...');

      // Устанавливаем высокий приоритет процесса
      await Process.run('wmic', [
        'process',
        'where',
        'name="flutter.exe"',
        'CALL',
        'setpriority',
        '128'
      ]).catchError((_) {}); // Игнорируем ошибки

      print('✅ Windows оптимизации применены');
    } catch (e) {
      print('⚠️ Windows оптимизации не удались: $e');
    }
  }

  Future<void> _applyHighPerformanceOptimizations() async {
    print('⚡ Применяем HIGH_PERFORMANCE оптимизации');
    // Менее агрессивные оптимизации
  }

  Future<void> _applyConservativeOptimizations() async {
    print('🐌 Применяем консервативные оптимизации');
    // Базовые настройки
  }

  /// МАКСИМАЛЬНО ОПТИМИЗИРОВАННЫЕ параметры waifu2x для мощного железа
  List<String> getOptimalWaifu2xArgs({
    required String inputPath,
    required String outputPath,
    required String modelPath,
    required Map<String, dynamic> systemCapabilities,
    int scale = 2,
    int noise = 0,
    bool useGPU = true,
    bool enableTTA = false,
    String format = 'jpg', // JPG по умолчанию для скорости
  }) {
    final args = <String>[];

    // Входные и выходные пути
    args.addAll(['-i', inputPath, '-o', outputPath]);

    // Уровень шума и масштаб
    args.addAll(['-n', noise.toString(), '-s', scale.toString()]);

    // Путь к модели
    args.addAll(['-m', modelPath]);

    // АГРЕССИВНАЯ оптимизация под мощное железо
    final profile = _hardwareProfile ?? systemCapabilities;
    final tier = profile['performance_tier'] as String? ?? 'CONSERVATIVE';

    switch (tier) {
      case 'BEAST_MODE':
        args.addAll(_getBeastModeArgs(scale));
        break;
      case 'HIGH_PERFORMANCE':
        args.addAll(_getHighPerformanceArgs(scale));
        break;
      default:
        args.addAll(_getConservativeArgs(scale));
    }

    // Отключение TTA для максимальной скорости (если не требуется качество)
    if (!enableTTA) {
      args.add('-x');
    }

    // Формат вывода (JPG быстрее PNG)
    args.addAll(['-f', format]);

    // Verbose вывод
    args.add('-v');

    return args;
  }

  List<String> _getBeastModeArgs(int scale) {
    // МАКСИМАЛЬНАЯ производительность для i9 + RTX 3070
    return [
      '-g', '0', // GPU принудительно
      '-t', scale >= 4 ? '768' : '1024', // ОГРОМНЫЕ тайлы для RTX 3070 8GB
      '-j', '4:12:4', // Максимальное использование 12 ядер i9
    ];
  }

  List<String> _getHighPerformanceArgs(int scale) {
    // Высокая производительность
    return [
      '-g',
      '0',
      '-t',
      scale >= 4 ? '512' : '768',
      '-j',
      '3:8:3',
    ];
  }

  List<String> _getConservativeArgs(int scale) {
    // Консервативные настройки
    return [
      '-g',
      '0',
      '-t',
      scale >= 4 ? '256' : '384',
      '-j',
      '2:4:2',
    ];
  }

  /// АГРЕССИВНЫЕ рекомендуемые настройки для мощного железа
  Map<String, dynamic> getRecommendedVideoSettings({
    required int videoWidth,
    required int videoHeight,
    required double videoDuration,
    required Map<String, dynamic> systemCapabilities,
  }) {
    final totalPixels = videoWidth * videoHeight;
    final profile = _hardwareProfile ?? systemCapabilities;
    final tier = profile['performance_tier'] as String? ?? 'CONSERVATIVE';

    // Агрессивные настройки для мощного железа
    int recommendedScale = 2;
    int recommendedNoise = 0;
    String recommendedFormat = 'jpg'; // Быстрее PNG

    switch (tier) {
      case 'BEAST_MODE':
        // i9 + RTX 3070 может обрабатывать 4K без проблем
        if (totalPixels <= 2560 * 1440) {
          recommendedScale = 4; // 4K для 1440p и ниже
        }
        if (totalPixels <= 1920 * 1080) {
          recommendedNoise = 1; // Можем позволить шумоподавление
        }
        break;

      case 'HIGH_PERFORMANCE':
        if (totalPixels <= 1920 * 1080) {
          recommendedScale = 4;
        }
        if (totalPixels <= 1280 * 720) {
          recommendedNoise = 1;
        }
        break;

      default:
        // Консервативные настройки остаются как есть
        break;
    }

    // Для очень длинных видео используем более быстрый формат
    if (videoDuration > 60) {
      recommendedFormat = 'jpg';
      recommendedNoise = 0; // Убираем шумоподавление для скорости
    }

    return {
      'scale': recommendedScale,
      'noise': recommendedNoise,
      'format': recommendedFormat,
      'use_gpu': true,
      'enable_tta': false, // Отключено для максимальной скорости
      'estimated_time_minutes': _estimateProcessingTimeOptimized(
        totalPixels,
        videoDuration,
        recommendedScale,
        profile,
      ),
      'performance_tier': tier,
    };
  }

  /// ОПТИМИЗИРОВАННАЯ оценка времени для мощного железа
  double _estimateProcessingTimeOptimized(
    int totalPixels,
    double videoDuration,
    int scale,
    Map<String, dynamic> capabilities,
  ) {
    final tier = capabilities['performance_tier'] as String? ?? 'CONSERVATIVE';
    final cpuCores = capabilities['cpu_cores'] as int? ?? 4;
    final gpuMemory = capabilities['gpu_memory_gb'] as int? ?? 4;

    // Базовое время на пиксель для разных уровней производительности
    double baseTimePerPixel;

    switch (tier) {
      case 'BEAST_MODE':
        // RTX 3070 + i9: ОЧЕНЬ быстро
        baseTimePerPixel = 0.02; // В 5 раз быстрее обычного GPU
        break;
      case 'HIGH_PERFORMANCE':
        baseTimePerPixel = 0.05;
        break;
      default:
        baseTimePerPixel = 0.1;
        break;
    }

    // Корректировка под масштаб (менее пенализирующая для мощного железа)
    double scaleMultiplier;
    switch (scale) {
      case 4:
        scaleMultiplier = tier == 'BEAST_MODE'
            ? 2.5
            : 4.0; // Меньше штрафа за 4x на мощном железе
        break;
      case 2:
        scaleMultiplier = 1.0;
        break;
      default:
        scaleMultiplier = 0.8;
    }

    baseTimePerPixel *= scaleMultiplier;

    // Общее время с учетом количества кадров
    final fps = 30; // Предполагаем 30 fps
    final totalFrames = videoDuration * fps;
    final totalTimeSeconds =
        (totalPixels * totalFrames * baseTimePerPixel) / 1000000;

    final estimatedMinutes = totalTimeSeconds / 60;

    print(
        '⏱️ Оценочное время обработки ($tier): ${estimatedMinutes.toStringAsFixed(1)} минут');

    return estimatedMinutes;
  }

  // Остальные методы остаются без изменений...
  Future<void> _setupWorkingDirectory() async {
    final cacheDir = await getTemporaryDirectory();
    _workingDirectory =
        Directory(path.join(cacheDir.path, 'video_upscaler_executables'));

    if (!await _workingDirectory!.exists()) {
      await _workingDirectory!.create(recursive: true);
    }

    print('📁 Рабочая директория: ${_workingDirectory!.path}');
  }

  Future<void> _extractFromAssets() async {
    try {
      print('📥 Извлечение исполняемых файлов из assets для $_platform...');

      await _extractExecutable('ffmpeg');
      if (!Platform.isMacOS) {
        await _extractExecutable('ffprobe');
      }
      await _extractExecutable('waifu2x-ncnn-vulkan');

      await _extractModelFolder('models-cunet');
      await _extractModelFolder('models-upconv_7_anime_style_art_rgb');
      await _extractModelFolder('models-upconv_7_photo');

      print('✅ Все файлы успешно извлечены');
    } catch (e) {
      print('❌ Ошибка извлечения файлов: $e');
      throw Exception('Не удалось извлечь исполняемые файлы: $e');
    }
  }

  Future<void> _extractExecutable(String fileName) async {
    try {
      final assetPath =
          'assets/executables/$_platform/$fileName$_executableExtension';
      final targetPath =
          path.join(_workingDirectory!.path, '$fileName$_executableExtension');

      print('📦 Извлечение $fileName...');

      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();

      await File(targetPath).writeAsBytes(bytes);

      final sizeMB = (bytes.length / 1024 / 1024).toStringAsFixed(1);
      print('✅ $fileName извлечен: $sizeMB MB');
    } catch (e) {
      print('❌ Ошибка извлечения $fileName: $e');
      throw Exception('Не удалось извлечь $fileName: $e');
    }
  }

  Future<void> _extractModelFolder(String folderName) async {
    try {
      final modelsDir =
          Directory(path.join(_workingDirectory!.path, folderName));
      await modelsDir.create(recursive: true);

      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);

      final modelFiles = manifestMap.keys
          .where((String key) =>
              key.startsWith('assets/executables/$_platform/$folderName/'))
          .where((String key) => !key.endsWith('/'))
          .toList();

      print('📁 Найдено файлов в $folderName: ${modelFiles.length}');

      int extractedCount = 0;
      for (final assetPath in modelFiles) {
        try {
          final fileName = path.basename(assetPath);
          final targetPath = path.join(modelsDir.path, fileName);

          final data = await rootBundle.load(assetPath);
          final bytes = data.buffer.asUint8List();

          await File(targetPath).writeAsBytes(bytes);

          final sizeMB = (bytes.length / 1024 / 1024).toStringAsFixed(1);
          print('📄 Извлечён: $fileName ($sizeMB MB)');
          extractedCount++;
        } catch (e) {
          print('❌ Ошибка извлечения ${path.basename(assetPath)}: $e');
        }
      }

      if (extractedCount == 0) {
        print('🔄 Fallback - ищем базовые файлы модели $folderName...');
        await _extractBasicModelFiles(folderName, modelsDir);
      }

      print('✅ Папка $folderName успешно извлечена: $extractedCount файлов');
    } catch (e) {
      print('❌ Ошибка извлечения папки $folderName: $e');
      throw Exception('Не удалось извлечь папку $folderName: $e');
    }
  }

  Future<void> _extractBasicModelFiles(
      String folderName, Directory modelsDir) async {
    final baseFiles = [
      'noise0_scale2.0x_model.bin',
      'noise0_scale2.0x_model.param',
      'noise1_scale2.0x_model.bin',
      'noise1_scale2.0x_model.param',
      'noise2_scale2.0x_model.bin',
      'noise2_scale2.0x_model.param',
      'noise3_scale2.0x_model.bin',
      'noise3_scale2.0x_model.param',
      'scale2.0x_model.bin',
      'scale2.0x_model.param',
      'noise0_model.bin',
      'noise0_model.param',
      'noise1_model.bin',
      'noise1_model.param',
      'noise2_model.bin',
      'noise2_model.param',
      'noise3_model.bin',
      'noise3_model.param',
    ];

    bool foundAny = false;

    for (final baseFile in baseFiles) {
      try {
        final assetPath = 'assets/executables/$_platform/$folderName/$baseFile';
        final data = await rootBundle.load(assetPath);
        final bytes = data.buffer.asUint8List();

        final targetPath = path.join(modelsDir.path, baseFile);
        await File(targetPath).writeAsBytes(bytes);

        final sizeMB = (bytes.length / 1024 / 1024).toStringAsFixed(1);
        print('📄 Найден базовый файл: $baseFile ($sizeMB MB)');
        foundAny = true;
      } catch (e) {
        // Файл не найден, продолжаем
      }
    }

    if (!foundAny) {
      print('⚠️ Не найдены .bin файлы для $folderName');
    }
  }

  Future<void> _makeExecutablesExecutable() async {
    if (Platform.isWindows) {
      print('ℹ️ Windows: права доступа устанавливаются автоматически');
      return;
    }

    try {
      print('🔧 Установка прав на выполнение...');

      final executables = [
        path.join(_workingDirectory!.path,
            'waifu2x-ncnn-vulkan$_executableExtension'),
        path.join(_workingDirectory!.path, 'ffmpeg$_executableExtension'),
      ];

      if (!Platform.isMacOS) {
        executables.add(
            path.join(_workingDirectory!.path, 'ffprobe$_executableExtension'));
      }

      for (final execPath in executables) {
        if (await File(execPath).exists()) {
          await _makeExecutableFile(execPath);
        }
      }

      print('✅ Права на выполнение установлены');
    } catch (e) {
      print('❌ Ошибка при установке прав доступа: $e');
    }
  }

  Future<void> _makeExecutableFile(String filePath) async {
    try {
      final fileName = path.basename(filePath);

      if (Platform.isMacOS) {
        await Process.run('xattr', ['-c', filePath])
            .catchError((e) => ProcessResult(0, 0, '', ''));
      }

      await Process.run('chmod', ['+x', filePath]);
      print('✅ Права установлены для $fileName');
    } catch (e) {
      print('⚠️ Ошибка установки прав для ${path.basename(filePath)}: $e');
    }
  }

  Future<void> _validateExecutables() async {
    print('🔍 Проверка исполняемых файлов...');

    try {
      final ffmpegPath =
          path.join(_workingDirectory!.path, 'ffmpeg$_executableExtension');
      final ffmpegWorks = await _testExecutable(ffmpegPath, ['-version']);

      if (!ffmpegWorks && (Platform.isMacOS || Platform.isLinux)) {
        print('⚠️ Локальный FFmpeg не работает, проверяем системный...');

        final systemFFmpeg = _getSystemFFmpegPath();
        if (await File(systemFFmpeg).exists()) {
          final systemWorks = await _testExecutable(systemFFmpeg, ['-version']);
          if (systemWorks) {
            _useSystemFFmpeg = true;
            print('✅ Используется системный FFmpeg: $systemFFmpeg');
          }
        }
      }

      final waifu2xPath = path.join(
          _workingDirectory!.path, 'waifu2x-ncnn-vulkan$_executableExtension');
      final waifu2xWorks = await _testExecutable(waifu2xPath, ['-h']);
      if (!waifu2xWorks) {
        print('⚠️ waifu2x может не работать корректно');
      }

      await _validateModels();

      print('✅ Валидация исполняемых файлов завершена');
    } catch (e) {
      print('⚠️ Ошибка валидации: $e');
    }
  }

  Future<void> _validateModels() async {
    print('🔍 Проверка моделей ИИ...');

    final modelDirs = [
      'models-cunet',
      'models-upconv_7_anime_style_art_rgb',
      'models-upconv_7_photo'
    ];

    for (final modelDir in modelDirs) {
      final modelPath = path.join(_workingDirectory!.path, modelDir);
      final dir = Directory(modelPath);

      if (!await dir.exists()) {
        print('❌ Папка модели не найдена: $modelDir');
        continue;
      }

      final files = await dir.list().toList();
      final binFiles = files.where((f) => f.path.endsWith('.bin')).toList();
      final paramFiles = files.where((f) => f.path.endsWith('.param')).toList();

      print(
          '📁 $modelDir: .bin=${binFiles.length}, .param=${paramFiles.length}');

      if (binFiles.isEmpty && paramFiles.isNotEmpty) {
        print('⚠️ Отсутствуют .bin файлы в $modelDir - только .param файлы');
      } else if (binFiles.isNotEmpty && paramFiles.isNotEmpty) {
        print('✅ $modelDir: найдены и .bin, и .param файлы');
      } else {
        print('❌ $modelDir: модели не найдены');
      }
    }
  }

  Future<bool> _testExecutable(String execPath, List<String> args) async {
    try {
      if (!await File(execPath).exists()) {
        return false;
      }

      final result = await Process.run(execPath, args)
          .timeout(const Duration(seconds: 10));

      return result.exitCode == 0 || result.exitCode == 1;
    } catch (e) {
      return false;
    }
  }

  String _getSystemFFmpegPath() {
    final systemPaths = [
      '/opt/homebrew/bin/ffmpeg',
      '/usr/local/bin/ffmpeg',
      '/usr/bin/ffmpeg',
    ];

    for (final systemPath in systemPaths) {
      if (File(systemPath).existsSync()) {
        return systemPath;
      }
    }

    return path.join(_workingDirectory!.path, 'ffmpeg$_executableExtension');
  }

  Future<void> cleanupExecutables() async {
    if (_workingDirectory != null && await _workingDirectory!.exists()) {
      await _workingDirectory!.delete(recursive: true);
      _isInitialized = false;
      _useSystemFFmpeg = false;
      print('🧹 Временные файлы очищены: ${_workingDirectory!.path}');
    }
  }

  void _checkInitialization() {
    if (!_isInitialized) {
      throw Exception(
          'ExecutableManager не инициализирован! Вызовите initializeExecutables() сначала.');
    }
  }

  Future<bool> validateInstallation() async {
    if (!_isInitialized) return false;

    try {
      final waifu2xExists = await File(waifu2xPath).exists();
      final ffmpegExists = await File(ffmpegPath).exists();

      if (!waifu2xExists || !ffmpegExists) {
        return false;
      }

      final modelDirs = [
        'models-cunet',
        'models-upconv_7_anime_style_art_rgb',
        'models-upconv_7_photo'
      ];

      for (final modelDir in modelDirs) {
        final modelPath = path.join(_workingDirectory!.path, modelDir);
        final dir = Directory(modelPath);

        if (!await dir.exists()) {
          return false;
        }

        final files = await dir.list().toList();
        final modelFiles = files
            .where((f) => f.path.endsWith('.bin') || f.path.endsWith('.param'))
            .toList();

        if (modelFiles.isEmpty) {
          return false;
        }
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  Map<String, dynamic> getConfigurationInfo() {
    return {
      'isInitialized': _isInitialized,
      'useSystemFFmpeg': _useSystemFFmpeg,
      'workingDirectory': _workingDirectory?.path,
      'platform': _platform,
      'ffmpegPath': _isInitialized ? ffmpegPath : null,
      'waifu2xPath': _isInitialized ? waifu2xPath : null,
      'hardwareProfile': _hardwareProfile,
    };
  }
}
