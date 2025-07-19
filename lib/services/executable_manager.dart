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

  bool get isInitialized => _isInitialized;

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

  String get modelsDir {
    _checkInitialization();
    return _workingDirectory!.path;
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

    print('🔄 Инициализация ExecutableManager...');

    try {
      await _setupWorkingDirectory();
      await _extractFromAssets();
      await _makeExecutablesExecutable();

      // Устанавливаем флаг ДО валидации
      _isInitialized = true;
      print('✅ ExecutableManager базовая инициализация завершена');

      // Теперь можем безопасно валидировать
      await _validateExecutables();

      print('✅ ExecutableManager полностью инициализирован');
    } catch (e) {
      print('❌ Ошибка инициализации ExecutableManager: $e');
      _isInitialized = false;
      rethrow;
    }
  }

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

      // Извлекаем исполняемые файлы
      await _extractExecutable('ffmpeg');
      if (!Platform.isMacOS) {
        await _extractExecutable('ffprobe');
      }
      await _extractExecutable('waifu2x-ncnn-vulkan');

      // Извлекаем папки с моделями
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
      // Создаём папку для моделей
      final modelsDir =
          Directory(path.join(_workingDirectory!.path, folderName));
      await modelsDir.create(recursive: true);

      // Получаем список файлов в папке модели
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);

      // Фильтруем файлы по папке
      final modelFiles = manifestMap.keys
          .where((String key) =>
              key.startsWith('assets/executables/$_platform/$folderName/'))
          .where((String key) => !key.endsWith('/')) // Исключаем папки
          .toList();

      print('📁 Найдено файлов в $folderName: ${modelFiles.length}');

      // Извлекаем каждый файл
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

      // Если файлы не извлечены, пытаемся найти основные файлы
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
    // Основные файлы для каждой модели
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
        // Убираем quarantine атрибуты
        await Process.run('xattr', ['-c', filePath])
            .catchError((e) => ProcessResult(0, 0, '', ''));
      }

      // Устанавливаем права на выполнение
      await Process.run('chmod', ['+x', filePath]);
      print('✅ Права установлены для $fileName');
    } catch (e) {
      print('⚠️ Ошибка установки прав для ${path.basename(filePath)}: $e');
    }
  }

  Future<void> _validateExecutables() async {
    print('🔍 Проверка исполняемых файлов...');

    try {
      // Проверка FFmpeg
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

      // Проверка waifu2x
      final waifu2xPath = path.join(
          _workingDirectory!.path, 'waifu2x-ncnn-vulkan$_executableExtension');
      final waifu2xWorks = await _testExecutable(waifu2xPath, ['-h']);
      if (!waifu2xWorks) {
        print('⚠️ waifu2x может не работать корректно');
      }

      // Проверяем модели
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

  // НОВЫЕ МЕТОДЫ ДЛЯ ОПТИМИЗАЦИИ

  /// Получает оптимальные параметры waifu2x для данного железа
  List<String> getOptimalWaifu2xArgs({
    required String inputPath,
    required String outputPath,
    required String modelPath,
    required Map<String, dynamic> systemCapabilities,
    int scale = 2,
    int noise = 0,
    bool useGPU = true,
    bool enableTTA = false,
    String format = 'png',
  }) {
    final args = <String>[];

    // Входные и выходные пути
    args.addAll(['-i', inputPath, '-o', outputPath]);

    // Уровень шума и масштаб
    args.addAll(['-n', noise.toString(), '-s', scale.toString()]);

    // Путь к модели
    args.addAll(['-m', modelPath]);

    // GPU/CPU выбор
    final gpuId = _getOptimalGPUId(systemCapabilities, useGPU);
    args.addAll(['-g', gpuId.toString()]);

    // Размер тайла
    final tileSize = _getOptimalTileSize(systemCapabilities, scale);
    args.addAll(['-t', tileSize.toString()]);

    // Потоки
    final threadConfig = _getOptimalThreadConfig(systemCapabilities);
    args.addAll(['-j', threadConfig]);

    // TTA режим (для качества vs скорости)
    if (enableTTA) {
      args.add('-x');
    }

    // Формат вывода
    args.addAll(['-f', format]);

    // Verbose вывод
    args.add('-v');

    return args;
  }

  /// Определяет оптимальный GPU ID
  int _getOptimalGPUId(Map<String, dynamic> capabilities, bool useGPU) {
    if (!useGPU) return -1;

    final hasGPU = capabilities['has_vulkan'] as bool? ?? false;
    final gpuCount = (capabilities['available_gpus'] as List?)?.length ?? 0;

    if (hasGPU && gpuCount > 0) {
      return 0; // Используем первый GPU
    }

    return -1; // Fallback на CPU
  }

  /// Определяет оптимальный размер тайла
  int _getOptimalTileSize(Map<String, dynamic> capabilities, int scale) {
    final memoryInfo =
        capabilities['memory_info'] as Map<String, dynamic>? ?? {};
    final totalMemoryGB = memoryInfo['total_gb'] as int? ?? 8;
    final hasGPU = capabilities['has_vulkan'] as bool? ?? false;

    // Базовый размер тайла
    int baseTileSize = 32;

    if (hasGPU) {
      // Для GPU оптимизируем под память
      if (totalMemoryGB >= 32) {
        baseTileSize = 400;
      } else if (totalMemoryGB >= 16) {
        baseTileSize = 256;
      } else if (totalMemoryGB >= 8) {
        baseTileSize = 128;
      } else {
        baseTileSize = 64;
      }
    } else {
      // Для CPU меньшие тайлы
      if (totalMemoryGB >= 16) {
        baseTileSize = 128;
      } else if (totalMemoryGB >= 8) {
        baseTileSize = 64;
      } else {
        baseTileSize = 32;
      }
    }

    // Корректировка под масштаб
    if (scale >= 4) {
      baseTileSize = (baseTileSize * 0.7).round();
    }

    return baseTileSize;
  }

  /// Определяет оптимальную конфигурацию потоков
  String _getOptimalThreadConfig(Map<String, dynamic> capabilities) {
    final cpuCores = capabilities['cpu_cores'] as int? ?? 4;
    final hasGPU = capabilities['has_vulkan'] as bool? ?? false;

    int loadThreads, procThreads, saveThreads;

    if (hasGPU) {
      // Для GPU меньше потоков нужно
      loadThreads = (cpuCores * 0.25).round().clamp(1, 4);
      procThreads = (cpuCores * 0.5).round().clamp(1, 8);
      saveThreads = (cpuCores * 0.25).round().clamp(1, 4);
    } else {
      // Для CPU используем больше потоков
      loadThreads = (cpuCores * 0.3).round().clamp(1, 4);
      procThreads = (cpuCores * 0.6).round().clamp(2, 16);
      saveThreads = (cpuCores * 0.3).round().clamp(1, 4);
    }

    return '$loadThreads:$procThreads:$saveThreads';
  }

  /// Получает рекомендуемые настройки для видео
  Map<String, dynamic> getRecommendedVideoSettings({
    required int videoWidth,
    required int videoHeight,
    required double videoDuration,
    required Map<String, dynamic> systemCapabilities,
  }) {
    final totalPixels = videoWidth * videoHeight;
    final memoryInfo =
        systemCapabilities['memory_info'] as Map<String, dynamic>? ?? {};
    final memoryGB = memoryInfo['total_gb'] as int? ?? 8;
    final hasGPU = systemCapabilities['has_vulkan'] as bool? ?? false;

    // Определяем оптимальный масштаб
    int recommendedScale = 2;
    if (totalPixels <= 1920 * 1080 && memoryGB >= 16) {
      recommendedScale = 4; // 4K для Full HD и выше
    } else if (totalPixels <= 1280 * 720 && memoryGB >= 8) {
      recommendedScale = 4; // 4K для HD
    }

    // Определяем noise level
    int recommendedNoise = 0;
    if (totalPixels <= 1280 * 720) {
      recommendedNoise = 1; // Больше шумоподавления для низких разрешений
    }

    // Определяем формат
    String recommendedFormat = 'png';
    if (videoDuration > 30) {
      recommendedFormat = 'jpg'; // Для длинных видео - компрессия
    }

    return {
      'scale': recommendedScale,
      'noise': recommendedNoise,
      'format': recommendedFormat,
      'use_gpu': hasGPU,
      'enable_tta': false, // Отключено для скорости
      'estimated_time_minutes': _estimateProcessingTime(
        videoWidth * videoHeight,
        videoDuration,
        recommendedScale,
        systemCapabilities,
      ),
    };
  }

  /// Оценивает время обработки
  double _estimateProcessingTime(
    int totalPixels,
    double videoDuration,
    int scale,
    Map<String, dynamic> capabilities,
  ) {
    final hasGPU = capabilities['has_vulkan'] as bool? ?? false;
    final cpuCores = capabilities['cpu_cores'] as int? ?? 4;

    // Базовое время на пиксель (в микросекундах)
    double baseTimePerPixel = hasGPU ? 0.1 : 0.5;

    // Корректировка под масштаб
    baseTimePerPixel *= scale * scale;

    // Корректировка под CPU
    if (!hasGPU) {
      baseTimePerPixel /= (cpuCores / 4).clamp(0.5, 2.0);
    }

    // Общее время
    final totalTimeSeconds =
        (totalPixels * videoDuration * baseTimePerPixel) / 1000000;

    return totalTimeSeconds / 60; // Возвращаем в минутах
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
      // Проверяем основные файлы
      final waifu2xExists = await File(waifu2xPath).exists();
      final ffmpegExists = await File(ffmpegPath).exists();

      if (!waifu2xExists || !ffmpegExists) {
        return false;
      }

      // Проверяем модели
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
    };
  }
}
