import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:path/path.dart' as path;
import 'package:video_upscaler/models/processing_config.dart';
import 'package:video_upscaler/services/executable_manager.dart';
import 'package:video_upscaler/services/system_info_service.dart';
import 'package:video_upscaler/services/resource_monitor.dart';

class VideoProcessingService {
  final StreamController<String> _progressController =
      StreamController<String>.broadcast();
  final StreamController<double> _percentageController =
      StreamController<double>.broadcast();

  Stream<String> get progressStream => _progressController.stream;
  Stream<double> get percentageStream => _percentageController.stream;

  bool _isProcessing = false;
  String? _tempBasePath;
  int _totalFrames = 0;
  DateTime? _startTime;

  bool get isProcessing => _isProcessing;

  Future<String> processVideo(ProcessingConfig config) async {
    if (_isProcessing) {
      throw Exception('Уже выполняется обработка видео');
    }

    _isProcessing = true;
    _startTime = DateTime.now();

    try {
      // Запускаем мониторинг ресурсов
      ResourceMonitor.instance.startMonitoring();

      _updateProgress('Проверка инициализации ExecutableManager...', 0.0);
      ResourceMonitor.instance.updateProgress(
        processedFrames: 0,
        totalFrames: 0,
        currentStage: 'Инициализация системы...',
      );

      final executableManager = ExecutableManager.instance;

      if (!await executableManager.validateInstallation()) {
        throw Exception(
            'ExecutableManager не инициализирован или файлы отсутствуют.');
      }

      _updateProgress('Анализ системы и оптимизация параметров...', 5.0);
      ResourceMonitor.instance.updateProgress(
        processedFrames: 0,
        totalFrames: 0,
        currentStage: 'Анализ системы...',
      );

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
      ResourceMonitor.instance.updateProgress(
        processedFrames: 0,
        totalFrames: 0,
        currentStage: 'Подготовка файлов...',
      );

      final tempDir = await _createTempDirectories();

      _updateProgress('Извлечение кадров из видео...', 15.0);
      ResourceMonitor.instance.updateProgress(
        processedFrames: 0,
        totalFrames: 0,
        currentStage: 'Извлечение кадров...',
      );

      await _extractFrames(
          config.inputVideoPath, tempDir['frames']!, optimizedParams);

      // Подсчитываем общее количество кадров
      final framesList = await Directory(tempDir['frames']!)
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.png'))
          .toList();
      _totalFrames = framesList.length;

      print('📸 Общее количество кадров: $_totalFrames');

      _updateProgress('Извлечение аудиодорожки...', 25.0);
      ResourceMonitor.instance.updateProgress(
        processedFrames: 0,
        totalFrames: _totalFrames,
        currentStage: 'Извлечение аудио...',
      );

      final hasAudio =
          await _extractAudio(config.inputVideoPath, tempDir['audio']!);

      _updateProgress('AI апскейлинг кадров...', 30.0);
      ResourceMonitor.instance.updateProgress(
        processedFrames: 0,
        totalFrames: _totalFrames,
        currentStage: 'AI апскейлинг кадров...',
      );

      await _upscaleFramesWithProgress(tempDir['frames']!, tempDir['scaled']!,
          config, systemInfo, optimizedParams);

      _updateProgress('Сборка финального видео...', 85.0);
      ResourceMonitor.instance.updateProgress(
        processedFrames: _totalFrames,
        totalFrames: _totalFrames,
        currentStage: 'Сборка видео...',
      );

      final outputPath = await _assembleVideo(tempDir['scaled']!,
          tempDir['audio']!, config, hasAudio, optimizedParams);

      _updateProgress('Очистка временных файлов...', 95.0);
      ResourceMonitor.instance.updateProgress(
        processedFrames: _totalFrames,
        totalFrames: _totalFrames,
        currentStage: 'Завершение...',
      );

      await _cleanupTempFiles();

      _updateProgress('Обработка завершена успешно!', 100.0);
      ResourceMonitor.instance.updateProgress(
        processedFrames: _totalFrames,
        totalFrames: _totalFrames,
        currentStage: 'Готово!',
      );

      return outputPath;
    } catch (e) {
      _updateProgress('Ошибка: $e', 0.0);
      ResourceMonitor.instance.updateProgress(
        processedFrames: 0,
        totalFrames: _totalFrames,
        currentStage: 'Ошибка обработки',
      );
      await _cleanupTempFiles();
      rethrow;
    } finally {
      _isProcessing = false;
      // Останавливаем мониторинг ресурсов
      ResourceMonitor.instance.stopMonitoring();
    }
  }

  // Анализ входного видео для оптимизации
  Future<Map<String, dynamic>> _analyzeInputVideo(String videoPath) async {
    final executableManager = ExecutableManager.instance;
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

    // Получаем системные возможности для ExecutableManager
    final systemCapabilities = {
      'has_vulkan': systemInfo.supportsGPU,
      'available_gpus': systemInfo.availableGPUs,
      'cpu_cores': systemInfo.cpuCores,
      'memory_info': {
        'total_gb': systemInfo.totalMemoryGB,
      },
      'platform': systemInfo.platform,
    };

    // Используем новые методы из ExecutableManager для оптимизации
    final optimalArgs = ExecutableManager.instance.getOptimalWaifu2xArgs(
      inputPath: 'dummy', // Заполним позже
      outputPath: 'dummy', // Заполним позже
      modelPath: 'dummy', // Заполним позже
      systemCapabilities: systemCapabilities,
      scale: config.scaleFactor,
      noise: config.scaleNoise,
      useGPU: systemInfo.supportsGPU,
      enableTTA: false, // Для скорости
      format: 'png',
    );

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
      'optimal_args': optimalArgs,
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
      // Apple Silicon - оптимизированные настройки
      gpuDevice = 0;
      if (memoryGB >= 16) {
        tileSize = validScaleFactor >= 4 ? 128 : 256; // Увеличено для 16GB+
      } else if (memoryGB >= 8) {
        tileSize = validScaleFactor >= 4 ? 64 : 128;
      } else {
        tileSize = 32; // Консервативно для <8GB
      }
      print(
          '🍎 Apple Silicon оптимизация: GPU=0, tileSize=$tileSize для ${validScaleFactor}x');
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
    final executableManager = ExecutableManager.instance;
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
    final executableManager = ExecutableManager.instance;
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

  // ОБНОВЛЕННЫЙ метод апскейлинга с отслеживанием прогресса
  Future<void> _upscaleFramesWithProgress(
    String framesDir,
    String scaledDir,
    ProcessingConfig config,
    SystemCapabilities systemInfo,
    Map<String, dynamic> optimizedParams,
  ) async {
    final executableManager = ExecutableManager.instance;
    final waifu2xPath = executableManager.waifu2xPath;

    print('🎯 OPTIMIZED апскейлинг с отслеживанием прогресса');
    print('⚙️ Платформа: ${systemInfo.platform}');

    if (!await File(waifu2xPath).exists()) {
      throw Exception('waifu2x-ncnn-vulkan не найден: $waifu2xPath');
    }

    // Получаем системные возможности для оптимизации
    final systemCapabilities = {
      'has_vulkan': systemInfo.supportsGPU,
      'available_gpus': systemInfo.availableGPUs,
      'cpu_cores': systemInfo.cpuCores,
      'memory_info': {
        'total_gb': systemInfo.totalMemoryGB,
      },
      'platform': systemInfo.platform,
    };

    // Получаем оптимальную модель
    final modelPath =
        executableManager.getModelPath(config.modelType ?? 'cunet');

    // Создаем оптимизированные аргументы
    final args = executableManager.getOptimalWaifu2xArgs(
      inputPath: framesDir,
      outputPath: scaledDir,
      modelPath: modelPath,
      systemCapabilities: systemCapabilities,
      scale: config.scaleFactor,
      noise: config.scaleNoise,
      useGPU: systemInfo.supportsGPU,
      enableTTA: false, // Для скорости
      format: 'png',
    );

    print('🚀 ОПТИМИЗИРОВАННАЯ команда: ${args.join(' ')}');

    // Запускаем процесс с отслеживанием прогресса
    final process =
        await Process.start(waifu2xPath, args, runInShell: Platform.isWindows);

    String output = '';
    String errorOutput = '';

    // Отслеживаем прогресс через файлы
    Timer? progressTimer;
    progressTimer = Timer.periodic(Duration(seconds: 2), (timer) async {
      try {
        final processedFiles = await Directory(scaledDir)
            .list()
            .where((entity) => entity is File && entity.path.endsWith('.png'))
            .length;

        if (processedFiles > 0) {
          final currentProgress = processedFiles;

          // Обновляем прогресс
          ResourceMonitor.instance.updateProgress(
            processedFrames: currentProgress,
            totalFrames: _totalFrames,
            currentStage: 'AI апскейлинг кадров...',
            currentFile:
                'frame_${currentProgress.toString().padLeft(6, '0')}.png',
          );

          // Обновляем процент для старого интерфейса
          final progressPercent =
              (currentProgress / _totalFrames * 55).clamp(0, 55);
          _updateProgress(
              'AI апскейлинг: $currentProgress/$_totalFrames кадров...',
              30.0 + progressPercent);

          // Останавливаем таймер если все кадры обработаны
          if (currentProgress >= _totalFrames) {
            timer.cancel();
          }
        }
      } catch (e) {
        // Игнорируем ошибки мониторинга
      }
    });

    // Обрабатываем вывод процесса
    process.stdout.transform(SystemEncoding().decoder).listen((data) {
      output += data;
      if (!data.contains('find_blob_index_by_name')) {
        print('📤 waifu2x stdout: $data');
      }
    });

    process.stderr.transform(SystemEncoding().decoder).listen((data) {
      errorOutput += data;
      if (!data.contains('find_blob_index_by_name')) {
        print('📥 waifu2x stderr: $data');
      }
    });

    // Ждем завершения процесса
    final exitCode = await process.exitCode;
    progressTimer?.cancel();

    print('⚡ waifu2x завершен с кодом: $exitCode');

    // Проверяем результаты
    final scaledFrames = await Directory(scaledDir)
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.png'))
        .toList();

    print('📊 Результат: ${scaledFrames.length}/$_totalFrames кадров');

    if (scaledFrames.length < _totalFrames * 0.8) {
      throw Exception(
          'Апскейлинг неудачен: обработано только ${scaledFrames.length}/$_totalFrames кадров');
    }

    print(
        '✅ Апскейлинг завершен успешно: ${scaledFrames.length}/$_totalFrames');
  }

  // ИСПРАВЛЕННАЯ сборка видео с ПРОСТЫМИ параметрами
  Future<String> _assembleVideo(
    String scaledDir,
    String audioPath,
    ProcessingConfig config,
    bool hasAudio,
    Map<String, dynamic> optimizedParams,
  ) async {
    final executableManager = ExecutableManager.instance;
    final ffmpegPath = executableManager.ffmpegPath;

    print('🎬 Сборка видео: $scaledDir -> ${config.outputPath}');

    // ПРОВЕРЯЕМ что кадры действительно существуют
    final scaledFrames = await Directory(scaledDir)
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.png'))
        .toList();

    if (scaledFrames.isEmpty) {
      throw Exception('Нет кадров для сборки видео в: $scaledDir');
    }

    print('📸 Найдено кадров для сборки: ${scaledFrames.length}');

    // ПРОСТЫЕ ПАРАМЕТРЫ
    final List<String> args = [
      '-y', // Перезаписать выходной файл
      '-framerate', '30', // Фиксированный framerate
      '-i', path.join(scaledDir, 'frame_%06d.png'),

      // Простые параметры H.264
      '-c:v', 'libx264',
      '-crf', '18', // Хорошее качество
      '-preset', 'medium',
      '-pix_fmt', 'yuv420p',

      '-r', '30', // Выходной framerate
    ];

    // Обработка аудио
    if (hasAudio && await File(audioPath).exists()) {
      print('🔊 Добавляем аудиодорожку');
      args.addAll([
        '-i',
        audioPath,
        '-c:a',
        'aac',
        '-b:a',
        '128k',
        '-shortest',
      ]);
    } else {
      print('🔇 Видео без аудио');
      args.add('-an');
    }

    // Финальные параметры
    args.addAll([
      '-movflags',
      '+faststart',
      config.outputPath,
    ]);

    print('🚀 Команда FFmpeg: ${args.join(' ')}');

    final result =
        await Process.run(ffmpegPath, args, runInShell: Platform.isWindows);

    print('📊 FFmpeg результат:');
    print('Exit code: ${result.exitCode}');
    if (result.stderr.isNotEmpty) print('STDERR: ${result.stderr}');

    if (result.exitCode != 0) {
      throw Exception('Сборка видео не удалась: ${result.stderr}');
    }

    final outputFile = File(config.outputPath);
    if (!await outputFile.exists()) {
      throw Exception('Выходной файл не был создан: ${config.outputPath}');
    }

    final outputSize = await outputFile.length();
    final outputSizeMB = (outputSize / 1024 / 1024);

    print('📹 Видео собрано: ${outputSizeMB.toStringAsFixed(2)} MB');

    if (outputSize < 500 * 1024) {
      throw Exception('Видео слишком маленькое - возможна ошибка сборки');
    }

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
      ResourceMonitor.instance.updateProgress(
        processedFrames: 0,
        totalFrames: _totalFrames,
        currentStage: 'Остановлено пользователем',
      );
      ResourceMonitor.instance.stopMonitoring();
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
