import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:path/path.dart' as path;
import 'package:video_upscaler/models/processing_config.dart';
import 'package:video_upscaler/services/executable_manager.dart';
import 'package:video_upscaler/services/system_info_service.dart';

class VideoProcessingService {
  final StreamController<String> _progressController =
      StreamController<String>.broadcast();
  final StreamController<double> _percentageController =
      StreamController<double>.broadcast();

  Stream<String> get progressStream => _progressController.stream;
  Stream<double> get percentageStream => _percentageController.stream;

  bool _isProcessing = false;
  String? _tempBasePath;

  bool get isProcessing => _isProcessing;

  Future<String> processVideo(ProcessingConfig config) async {
    if (_isProcessing) {
      throw Exception('Уже выполняется обработка видео');
    }

    _isProcessing = true;

    try {
      _updateProgress('Проверка инициализации ExecutableManager...', 0.0);
      final executableManager = ExecutableManager();

      if (!await executableManager.validateInstallation()) {
        throw Exception(
            'ExecutableManager не инициализирован или файлы отсутствуют.');
      }

      _updateProgress('Анализ системы и оптимизация параметров...', 5.0);
      final systemInfo = await SystemInfoService.analyzeSystem();

      // Получаем информацию о входном видео
      final videoInfo = await _analyzeInputVideo(config.inputVideoPath);

      // Оптимизируем параметры под железо и разрешение
      final optimizedParams =
          await _getOptimizedParameters(systemInfo, videoInfo, config);

      print('=== ОПТИМИЗИРОВАННЫЕ ПАРАМЕТРЫ ===');
      print('Система: ${systemInfo.systemSummary}');
      print(
          'Входное видео: ${videoInfo['width']}x${videoInfo['height']} @ ${videoInfo['fps']}fps');
      print(
          'Выходное разрешение: ${optimizedParams['output_width']}x${optimizedParams['output_height']}');
      print('Оптимизация: $optimizedParams');

      _updateProgress('Создание временных директорий...', 10.0);
      final tempDir = await _createTempDirectories();

      _updateProgress('Извлечение кадров из видео...', 15.0);
      await _extractFrames(
          config.inputVideoPath, tempDir['frames']!, optimizedParams);

      _updateProgress('Извлечение аудиодорожки...', 25.0);
      final hasAudio =
          await _extractAudio(config.inputVideoPath, tempDir['audio']!);

      _updateProgress('AI апскейлинг кадров...', 30.0);
      await _upscaleFrames(tempDir['frames']!, tempDir['scaled']!, config,
          systemInfo, optimizedParams);

      _updateProgress('Сборка финального видео...', 85.0);
      final outputPath = await _assembleVideo(tempDir['scaled']!,
          tempDir['audio']!, config, hasAudio, optimizedParams);

      _updateProgress('Очистка временных файлов...', 95.0);
      await _cleanupTempFiles();

      _updateProgress('Обработка завершена успешно!', 100.0);
      return outputPath;
    } catch (e) {
      _updateProgress('Ошибка: $e', 0.0);
      await _cleanupTempFiles();
      rethrow;
    } finally {
      _isProcessing = false;
    }
  }

  // Анализ входного видео для оптимизации
  Future<Map<String, dynamic>> _analyzeInputVideo(String videoPath) async {
    final executableManager = ExecutableManager();
    final ffmpegPath = executableManager.ffmpegPath;

    print('🎬 Анализ видео: $videoPath');

    final result = await Process.run(
        ffmpegPath,
        [
          '-i',
          videoPath,
          '-hide_banner',
        ],
        runInShell: Platform.isWindows);

    final output = result.stderr.toString();
    print('📹 FFmpeg вывод: $output');

    // УЛУЧШЕННЫЙ парсинг информации о видео
    final RegExp resolutionRegex =
        RegExp(r'(\d{2,})x(\d{2,})'); // Минимум 2 цифры
    final RegExp fpsRegex = RegExp(r'(\d+(?:\.\d+)?)\s*fps');
    final RegExp bitrateRegex = RegExp(r'(\d+)\s*kb/s');

    final resolutionMatch = resolutionRegex.firstMatch(output);
    final fpsMatch = fpsRegex.firstMatch(output);
    final bitrateMatch = bitrateRegex.firstMatch(output);

    final width =
        resolutionMatch != null ? int.parse(resolutionMatch.group(1)!) : 1920;
    final height =
        resolutionMatch != null ? int.parse(resolutionMatch.group(2)!) : 1080;
    final fps = fpsMatch != null ? double.parse(fpsMatch.group(1)!) : 30.0;
    final bitrate =
        bitrateMatch != null ? int.parse(bitrateMatch.group(1)!) : 5000;

    print(
        '📐 Обнаружено разрешение: ${width}x${height} @ ${fps}fps, битрейт: ${bitrate}kb/s');

    return {
      'width': width,
      'height': height,
      'fps': fps,
      'bitrate': bitrate,
      'raw_info': output,
    };
  }

  // Получение оптимизированных параметров под железо
  Future<Map<String, dynamic>> _getOptimizedParameters(
      SystemCapabilities systemInfo,
      Map<String, dynamic> videoInfo,
      ProcessingConfig config) async {
    final inputWidth = videoInfo['width'] as int;
    final inputHeight = videoInfo['height'] as int;
    final inputFPS = videoInfo['fps'] as double;
    final scaleFactor = config.scaleFactor;

    final outputWidth = inputWidth * scaleFactor;
    final outputHeight = inputHeight * scaleFactor;
    final totalPixels = outputWidth * outputHeight;

    // Параметры waifu2x на основе железа
    Map<String, dynamic> waifu2xParams =
        _getWaifu2xParameters(systemInfo, scaleFactor);

    // Параметры FFmpeg на основе разрешения и железа
    Map<String, dynamic> ffmpegParams = _getFFmpegParameters(
        systemInfo,
        inputWidth,
        inputHeight,
        outputWidth,
        outputHeight,
        inputFPS,
        scaleFactor);

    return {
      'output_width': outputWidth,
      'output_height': outputHeight,
      'total_pixels': totalPixels,
      'waifu2x': waifu2xParams,
      'ffmpeg': ffmpegParams,
    };
  }

  // УНИВЕРСАЛЬНЫЕ параметры waifu2x для всех платформ
  Map<String, dynamic> _getWaifu2xParameters(
      SystemCapabilities systemInfo, int scaleFactor) {
    final memoryGB = systemInfo.totalMemoryGB;
    final cpuCores = systemInfo.cpuCores;
    final platform = systemInfo.platform;

    // ИСПРАВЛЯЕМ scale factor - только 1, 2, 4 поддерживаются!
    int validScaleFactor = scaleFactor;
    if (![1, 2, 4].contains(validScaleFactor)) {
      if (validScaleFactor == 3) {
        validScaleFactor = 2; // 3x не поддерживается
        print('⚠️ Масштаб 3x не поддерживается, используем 2x');
      } else if (validScaleFactor > 4) {
        validScaleFactor = 4; // Максимум 4x
        print('⚠️ Масштаб больше 4x не поддерживается, используем 4x');
      } else {
        validScaleFactor = 2; // По умолчанию 2x
        print('⚠️ Неподдерживаемый масштаб, используем 2x');
      }
    }

    int tileSize = 0; // auto по умолчанию
    int threads = (cpuCores / 2).round().clamp(1, 4);
    int gpuDevice = 0; // По умолчанию GPU

    // Платформо-специфичные настройки
    if (platform == 'macos') {
      // Apple Silicon - ОЧЕНЬ консервативно
      gpuDevice = 0;
      if (validScaleFactor >= 4) {
        tileSize = 32; // МИНИМАЛЬНЫЙ для 4x
      } else if (validScaleFactor >= 2) {
        tileSize = 64; // Маленький для 2x
      } else {
        tileSize = 0; // auto для 1x
      }
      print(
          '🍎 Apple Silicon: GPU=0, tileSize=$tileSize для ${validScaleFactor}x');
    } else if (platform == 'windows' || platform == 'linux') {
      // Для других платформ
      if (systemInfo.supportsGPU && systemInfo.availableGPUs.isNotEmpty) {
        gpuDevice = 0;
        if (memoryGB >= 16) {
          tileSize = validScaleFactor >= 4 ? 200 : 400;
        } else if (memoryGB >= 8) {
          tileSize = validScaleFactor >= 4 ? 100 : 200;
        } else {
          tileSize = 100;
        }
      } else {
        // CPU fallback
        gpuDevice = -1;
        tileSize = validScaleFactor >= 4 ? 50 : 100;
        threads = cpuCores.clamp(1, 8);
      }
    }

    return {
      'tile_size': tileSize,
      'threads': threads,
      'gpu_device': gpuDevice,
      'use_gpu': gpuDevice >= 0,
      'valid_scale_factor': validScaleFactor,
    };
  }

  // Оптимизированные параметры FFmpeg
  Map<String, dynamic> _getFFmpegParameters(
      SystemCapabilities systemInfo,
      int inputWidth,
      int inputHeight,
      int outputWidth,
      int outputHeight,
      double inputFPS,
      int scaleFactor) {
    final totalPixels = outputWidth * outputHeight;
    final memoryGB = systemInfo.totalMemoryGB;

    // Выбор кодека на основе разрешения
    String videoCodec = 'libx264';
    String preset = 'medium';
    int crf = 23;
    String pixFormat = 'yuv420p';

    // Для высоких разрешений используем H.265
    if (totalPixels >= 3840 * 2160) {
      // 4K и выше
      videoCodec = 'libx265';
      crf = 18; // Высокое качество для 4K
      preset = memoryGB >= 16 ? 'slow' : 'medium';
      pixFormat = 'yuv420p10le'; // 10-bit для лучшего качества
    } else if (totalPixels >= 2560 * 1440) {
      // 1440p
      videoCodec = 'libx264';
      crf = 20;
      preset = memoryGB >= 8 ? 'slow' : 'medium';
    } else {
      // 1080p и ниже
      crf = 23;
      preset = 'medium';
    }

    // Расчет оптимального битрейта
    final bitrate = _calculateOptimalBitrate(
        outputWidth, outputHeight, inputFPS, scaleFactor);
    final maxrate = (bitrate * 1.5).round();
    final bufsize = maxrate * 2;

    return {
      'video_codec': videoCodec,
      'preset': preset,
      'crf': crf,
      'pix_format': pixFormat,
      'bitrate': '${bitrate}k',
      'maxrate': '${maxrate}k',
      'bufsize': '${bufsize}k',
      'fps': inputFPS.round(),
    };
  }

  // Расчет оптимального битрейта на основе разрешения
  int _calculateOptimalBitrate(
      int width, int height, double fps, int scaleFactor) {
    final totalPixels = width * height;
    final pixelsPerSecond = totalPixels * fps;

    // Базовый битрейт на пиксель (бит/пиксель/секунда)
    double bitsPerPixel;

    if (totalPixels >= 3840 * 2160) {
      // 4K
      bitsPerPixel = 0.15; // Высокое качество для 4K
    } else if (totalPixels >= 2560 * 1440) {
      // 1440p
      bitsPerPixel = 0.12;
    } else if (totalPixels >= 1920 * 1080) {
      // 1080p
      bitsPerPixel = 0.10;
    } else {
      // Ниже 1080p
      bitsPerPixel = 0.08;
    }

    // Увеличиваем битрейт для больших масштабов (больше деталей)
    if (scaleFactor >= 4) {
      bitsPerPixel *= 1.5;
    } else if (scaleFactor >= 2) {
      bitsPerPixel *= 1.2;
    }

    final bitrateKbps = (pixelsPerSecond * bitsPerPixel / 1000).round();

    // Ограничения
    return bitrateKbps.clamp(1000, 50000); // От 1Mbps до 50Mbps
  }

  Future<Map<String, String>> _createTempDirectories() async {
    final tempBase = await Directory.systemTemp.createTemp('video_upscaler_');
    _tempBasePath = tempBase.path;

    final directories = {
      'frames': path.join(tempBase.path, 'frames'),
      'scaled': path.join(tempBase.path, 'scaled'),
      'audio': path.join(tempBase.path, 'audio.mp3'),
    };

    for (final entry in directories.entries) {
      if (!entry.key.contains('audio')) {
        await Directory(entry.value).create(recursive: true);
      }
    }

    print('Временные директории созданы в: ${tempBase.path}');
    return directories;
  }

  // Оптимизированное извлечение кадров
  Future<void> _extractFrames(
      String videoPath, String framesDir, Map<String, dynamic> params) async {
    final executableManager = ExecutableManager();
    final ffmpegPath = executableManager.ffmpegPath;
    final ffmpegParams = params['ffmpeg'] as Map<String, dynamic>;

    print('Извлечение кадров: $videoPath -> $framesDir');

    final args = [
      '-i', videoPath,
      '-vf', 'fps=${ffmpegParams['fps']}', // Оптимизированный FPS
      path.join(framesDir, 'frame_%06d.png'),
      '-hide_banner',
      '-loglevel', 'error',
    ];

    final result =
        await Process.run(ffmpegPath, args, runInShell: Platform.isWindows);

    if (result.exitCode != 0) {
      throw Exception('Ошибка извлечения кадров: ${result.stderr}');
    }

    final framesList = await Directory(framesDir).list().toList();
    print('Извлечено кадров: ${framesList.length}');
  }

  Future<bool> _extractAudio(String videoPath, String audioPath) async {
    final executableManager = ExecutableManager();
    final ffmpegPath = executableManager.ffmpegPath;

    print('Извлечение аудио: $videoPath -> $audioPath');

    final result = await Process.run(
        ffmpegPath,
        [
          '-i',
          videoPath,
          '-vn',
          '-acodec',
          'copy',
          audioPath,
          '-hide_banner',
          '-loglevel',
          'error',
        ],
        runInShell: Platform.isWindows);

    final audioFile = File(audioPath);
    final hasAudio = await audioFile.exists() && await audioFile.length() > 0;

    if (!hasAudio) {
      print('Видео не содержит аудиодорожку или аудио не удалось извлечь');
    } else {
      print('Аудио извлечено успешно');
    }

    return hasAudio;
  }

  // ПОЛНОСТЬЮ ПЕРЕПИСАННЫЙ универсальный метод апскейлинга
  Future<void> _upscaleFrames(
    String framesDir,
    String scaledDir,
    ProcessingConfig config,
    SystemCapabilities systemInfo,
    Map<String, dynamic> optimizedParams,
  ) async {
    final executableManager = ExecutableManager();
    final waifu2xPath = executableManager.waifu2xPath;
    final waifu2xParams = optimizedParams['waifu2x'] as Map<String, dynamic>;

    print('🎯 Начинаем универсальный апскейлинг');
    print('⚙️ Платформа: ${systemInfo.platform}');

    // Проверяем что waifu2x существует
    if (!await File(waifu2xPath).exists()) {
      throw Exception('waifu2x-ncnn-vulkan не найден: $waifu2xPath');
    }

    // Используем исправленный scale factor
    final validScaleFactor = waifu2xParams['valid_scale_factor'] as int;

    // ИСПРАВЛЯЕМ noise level - только -1, 0, 1, 2, 3
    int validNoise = config.scaleNoise.clamp(-1, 3);
    if (validNoise != config.scaleNoise) {
      print('⚠️ Noise level исправлен с ${config.scaleNoise} на $validNoise');
    }

    // ПОЛУЧАЕМ правильный путь к модели
    final modelInfo = await _getValidModel(
        executableManager, config.modelType, validScaleFactor, validNoise);

    print('🎯 Используется модель: ${modelInfo['path']}');
    print('📐 Параметры: scale=${validScaleFactor}x, noise=$validNoise');

    // Проверяем кадры
    final framesList = await Directory(framesDir)
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.png'))
        .toList();

    if (framesList.isEmpty) {
      throw Exception('Не найдено кадров для обработки в: $framesDir');
    }

    print('📸 Найдено кадров: ${framesList.length}');

    // СОБИРАЕМ аргументы по документации
    final args = [
      '-i', framesDir,
      '-o', scaledDir,
      '-n', validNoise.toString(),
      '-s', validScaleFactor.toString(),
      '-m', modelInfo['path']!,
      '-g', waifu2xParams['gpu_device'].toString(),
      '-f', 'png', // Явно указываем формат
    ];

    // Добавляем tilesize если нужно
    if (waifu2xParams['tile_size'] > 0) {
      args.addAll(['-t', waifu2xParams['tile_size'].toString()]);
    }

    // Добавляем потоки для CPU режима
    if (waifu2xParams['gpu_device'] == -1) {
      final threads = waifu2xParams['threads'];
      args.addAll(['-j', '$threads:$threads:$threads']);
    }

    // Verbose для отладки
    args.add('-v');

    print('🚀 Универсальная команда: ${args.join(' ')}');

    // Запускаем процесс
    final process =
        await Process.start(waifu2xPath, args, runInShell: Platform.isWindows);

    String output = '';
    String errorOutput = '';
    int processedFrames = 0;
    bool hasCriticalError = false;

    process.stdout.transform(SystemEncoding().decoder).listen((data) {
      output += data;
      print('📤 stdout: $data');

      // Парсим прогресс
      if (data.contains('processing') || data.contains('.png')) {
        processedFrames++;
        if (processedFrames % 10 == 0) {
          final progressPercent =
              (processedFrames / framesList.length * 50).clamp(0, 50);
          _updateProgress(
              'AI апскейлинг: $processedFrames/${framesList.length} кадров...',
              30.0 + progressPercent);
        }
      }
    });

    process.stderr.transform(SystemEncoding().decoder).listen((data) {
      errorOutput += data;
      print('📥 stderr: $data');

      // ИСПРАВЛЕННАЯ обработка ошибок - игнорируем find_blob_index_by_name
      if (!data.contains('find_blob_index_by_name') &&
          (data.toLowerCase().contains('failed') ||
              data.toLowerCase().contains('error') ||
              data.toLowerCase().contains('segmentation fault') ||
              data.toLowerCase().contains('illegal instruction') ||
              data.toLowerCase().contains('out of memory'))) {
        print('🚨 КРИТИЧЕСКАЯ ОШИБКА: $data');
        hasCriticalError = true;
      }
    });

    final exitCode = await process.exitCode;

    print('⚡ waifu2x завершен с кодом: $exitCode');

    // Проверяем результаты НЕЗАВИСИМО от ошибок в stderr
    final scaledFrames = await Directory(scaledDir)
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.png'))
        .toList();

    print('📊 Результат: ${scaledFrames.length}/${framesList.length} кадров');

    // Если кадры обработаны успешно, игнорируем find_blob_index_by_name ошибки
    if (scaledFrames.length == framesList.length) {
      print('✅ Апскейлинг завершен успешно несмотря на stderr ошибки');
      return;
    }

    // Только если реально нет результатов - пробуем CPU fallback
    if (exitCode != 0 || hasCriticalError || scaledFrames.length == 0) {
      print('❌ ОШИБКА waifu2x, пробуем CPU fallback:');
      print('Exit code: $exitCode');
      print('STDERR: $errorOutput');

      if (waifu2xParams['gpu_device'] != -1) {
        print('🔄 Пробуем CPU fallback...');
        await _upscaleFramesCPUFallback(framesDir, scaledDir, waifu2xPath,
            modelInfo, validScaleFactor, validNoise, framesList);
        return;
      }

      throw Exception(
          'Ошибка waifu2x и CPU fallback (код: $exitCode):\n$errorOutput');
    }

    if (scaledFrames.length != framesList.length) {
      throw Exception(
          'Обработаны не все кадры: ${scaledFrames.length}/${framesList.length}');
    }
  }

  // Получение валидной модели с проверками
  Future<Map<String, String>> _getValidModel(
      ExecutableManager executableManager,
      String? modelType,
      int scaleFactor,
      int noise) async {
    final modelTypes = {
      'cunet': 'models-cunet',
      'anime': 'models-upconv_7_anime_style_art_rgb',
      'photo': 'models-upconv_7_photo',
    };

    String selectedModel = modelTypes[modelType] ?? 'models-cunet';
    String modelPath = executableManager.getModelPath(modelType ?? 'cunet');

    // Проверяем что директория модели существует
    if (!await Directory(modelPath).exists()) {
      print('⚠️ Модель $selectedModel не найдена, пробуем другие...');

      // Пробуем все доступные модели
      for (final entry in modelTypes.entries) {
        final testPath = executableManager.getModelPath(entry.key);
        if (await Directory(testPath).exists()) {
          selectedModel = entry.value;
          modelPath = testPath;
          print('✅ Найдена рабочая модель: $selectedModel');
          break;
        }
      }

      if (!await Directory(modelPath).exists()) {
        throw Exception(
            'Ни одна модель не найдена! Проверьте ExecutableManager.');
      }
    }

    return {
      'name': selectedModel,
      'path': modelPath,
    };
  }

  // CPU Fallback
  Future<void> _upscaleFramesCPUFallback(
      String framesDir,
      String scaledDir,
      String waifu2xPath,
      Map<String, String> modelInfo,
      int scaleFactor,
      int noise,
      List<FileSystemEntity> framesList) async {
    print('🔄 CPU FALLBACK режим');

    final args = [
      '-i', framesDir,
      '-o', scaledDir,
      '-n', noise.toString(),
      '-s', scaleFactor.toString(),
      '-m', modelInfo['path']!,
      '-g', '-1', // Принудительно CPU
      '-t', '32', // Очень маленький tilesize для CPU
      '-j', '1:1:1', // Один поток
      '-f', 'png',
      '-v',
    ];

    print('🚀 CPU команда: ${args.join(' ')}');

    final process = await Process.start(waifu2xPath, args);

    String cpuOutput = '';
    String cpuErrorOutput = '';

    process.stdout.transform(SystemEncoding().decoder).listen((data) {
      cpuOutput += data;
      print('📤 CPU stdout: $data');
    });

    process.stderr.transform(SystemEncoding().decoder).listen((data) {
      cpuErrorOutput += data;
      print('📥 CPU stderr: $data');
    });

    final exitCode = await process.exitCode;

    final scaledFrames = await Directory(scaledDir)
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.png'))
        .toList();

    if (exitCode != 0 || scaledFrames.length != framesList.length) {
      throw Exception(
          'CPU fallback тоже неудачен. Код: $exitCode, кадров: ${scaledFrames.length}/${framesList.length}');
    }

    print('✅ CPU fallback успешен: ${scaledFrames.length} кадров');
  }

  // Оптимизированная сборка видео
  Future<String> _assembleVideo(
    String scaledDir,
    String audioPath,
    ProcessingConfig config,
    bool hasAudio,
    Map<String, dynamic> optimizedParams,
  ) async {
    final executableManager = ExecutableManager();
    final ffmpegPath = executableManager.ffmpegPath;
    final ffmpegParams = optimizedParams['ffmpeg'] as Map<String, dynamic>;

    print(
        'Сборка видео с оптимизированными параметрами: $scaledDir -> ${config.outputPath}');
    print('FFmpeg параметры: $ffmpegParams');

    final args = [
      '-framerate',
      ffmpegParams['fps'].toString(),
      '-i',
      path.join(scaledDir, 'frame_%06d.png'),
    ];

    // Добавляем аудио если есть
    if (hasAudio && await File(audioPath).exists()) {
      args.addAll(['-i', audioPath]);
      args.addAll(['-c:a', config.audioCodec, '-b:a', '320k']);
    } else {
      args.addAll(['-an']);
    }

    // Оптимизированные параметры видео
    args.addAll([
      '-c:v', ffmpegParams['video_codec'],
      '-preset', ffmpegParams['preset'],
      '-crf', ffmpegParams['crf'].toString(),
      '-pix_fmt', ffmpegParams['pix_format'],
      '-maxrate', ffmpegParams['maxrate'],
      '-bufsize', ffmpegParams['bufsize'],
      '-movflags', '+faststart', // Оптимизация для стриминга
      config.outputPath,
      '-hide_banner',
      '-loglevel', 'error',
      '-y',
    ]);

    print('Запуск сборки с аргументами: ${args.join(' ')}');

    final result =
        await Process.run(ffmpegPath, args, runInShell: Platform.isWindows);

    if (result.exitCode != 0) {
      throw Exception('Ошибка сборки видео: ${result.stderr}');
    }

    final outputFile = File(config.outputPath);
    if (!await outputFile.exists()) {
      throw Exception('Выходной файл не был создан');
    }

    final outputSize = await outputFile.length();
    print(
        'Видео собрано успешно. Размер: ${(outputSize / 1024 / 1024).toStringAsFixed(2)} MB');

    return config.outputPath;
  }

  Future<void> _cleanupTempFiles() async {
    if (_tempBasePath != null) {
      try {
        final tempDir = Directory(_tempBasePath!);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
          print('Временные файлы очищены: $_tempBasePath');
        }
      } catch (e) {
        print('Ошибка очистки временных файлов: $e');
      }
      _tempBasePath = null;
    }
  }

  void _updateProgress(String message, double percentage) {
    _progressController.add(message);
    _percentageController.add(percentage);
    print('Progress ($percentage%): $message');
  }

  Future<Map<String, dynamic>> getVideoInfo(String videoPath) async {
    return await _analyzeInputVideo(videoPath);
  }

  void stopProcessing() {
    if (_isProcessing) {
      _updateProgress('Остановка обработки...', 0.0);
      _cleanupTempFiles();
      _isProcessing = false;
    }
  }

  void dispose() {
    stopProcessing();
    _progressController.close();
    _percentageController.close();
  }
}
