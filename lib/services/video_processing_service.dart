import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:convert';
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

  bool get isProcessing => _isProcessing;

  Future<String> processVideo(ProcessingConfig config) async {
    if (_isProcessing) {
      throw Exception('Уже выполняется обработка видео');
    }

    _isProcessing = true;

    try {
      _updateProgress('Проверка инициализации ExecutableManager...', 0.0);
      final executableManager = ExecutableManager.instance;

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

      // Подсчитываем кадры для мониторинга прогресса
      final frameFiles = await Directory(tempDir['frames']!)
          .list()
          .where((f) => f.path.endsWith('.png'))
          .toList();
      final totalFrames = frameFiles.length;

      print('📸 Всего кадров для обработки: $totalFrames');

      _updateProgress('Извлечение аудиодорожки...', 25.0);
      final hasAudio =
          await _extractAudio(config.inputVideoPath, tempDir['audio']!);

      _updateProgress('AI апскейлинг кадров...', 30.0);

      // Обновляем ResourceMonitor с информацией о кадрах
      ResourceMonitor.instance.updateProgress(
        processedFrames: 0,
        totalFrames: totalFrames,
        currentStage: 'AI апскейлинг кадров...',
      );

      await _upscaleFramesWithProgress(
        tempDir['frames']!,
        tempDir['scaled']!,
        config,
        systemInfo,
        optimizedParams,
        totalFrames,
      );

      _updateProgress('Сборка финального видео...', 85.0);

      ResourceMonitor.instance.updateProgress(
        processedFrames: totalFrames,
        totalFrames: totalFrames,
        currentStage: 'Сборка финального видео...',
      );

      final outputPath = await _assembleVideo(
        tempDir['scaled']!,
        tempDir['audio']!,
        config,
        hasAudio,
        optimizedParams,
      );

      _updateProgress('Очистка временных файлов...', 95.0);
      await _cleanupTempFiles();

      _updateProgress('Обработка завершена успешно!', 100.0);

      ResourceMonitor.instance.updateProgress(
        processedFrames: totalFrames,
        totalFrames: totalFrames,
        currentStage: 'Завершено успешно!',
      );

      return outputPath;
    } catch (e) {
      _updateProgress('Ошибка: $e', 0.0);
      await _cleanupTempFiles();

      ResourceMonitor.instance.updateProgress(
        processedFrames: 0,
        totalFrames: 0,
        currentStage: 'Ошибка обработки',
      );

      rethrow;
    } finally {
      _isProcessing = false;
    }
  }

  Future<Map<String, dynamic>> _analyzeInputVideo(String videoPath) async {
    final executableManager = ExecutableManager.instance;
    final ffmpegPath = executableManager.ffmpegPath;

    print('🎬 Анализ видео: $videoPath');

    final result = await Process.run(
      ffmpegPath,
      ['-i', videoPath, '-hide_banner'],
      runInShell: Platform.isWindows,
    );

    final output = result.stderr.toString();
    print('📹 FFmpeg вывод: $output');

    // Улучшенный парсинг информации о видео
    final RegExp resolutionRegex = RegExp(r'(\d{2,})x(\d{2,})');
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

  Future<Map<String, dynamic>> _getOptimizedParameters(
    SystemCapabilities systemInfo,
    Map<String, dynamic> videoInfo,
    ProcessingConfig config,
  ) async {
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
      scaleFactor,
    );

    return {
      'output_width': outputWidth,
      'output_height': outputHeight,
      'total_pixels': totalPixels,
      'waifu2x': waifu2xParams,
      'ffmpeg': ffmpegParams,
    };
  }

  Map<String, dynamic> _getWaifu2xParameters(
      SystemCapabilities systemInfo, int scaleFactor) {
    final memoryGB = systemInfo.totalMemoryGB;
    final cpuCores = systemInfo.cpuCores;
    final platform = systemInfo.platform;

    // Исправляем scale factor - только 1, 2, 4 поддерживаются!
    int validScaleFactor = scaleFactor;
    if (![1, 2, 4].contains(validScaleFactor)) {
      if (validScaleFactor == 3) {
        validScaleFactor = 2;
        print('⚠️ Масштаб 3x не поддерживается, используем 2x');
      } else if (validScaleFactor > 4) {
        validScaleFactor = 4;
        print('⚠️ Масштаб больше 4x не поддерживается, используем 4x');
      } else {
        validScaleFactor = 2;
        print('⚠️ Неподдерживаемый масштаб, используем 2x');
      }
    }

    int tileSize = 0; // auto по умолчанию
    int threads = (cpuCores / 2).round().clamp(1, 4);
    int gpuDevice = 0;

    // Платформо-специфичные настройки
    if (platform == 'macos') {
      gpuDevice = 0;
      if (validScaleFactor >= 4) {
        tileSize = 32;
      } else if (validScaleFactor >= 2) {
        tileSize = 64;
      } else {
        tileSize = 0;
      }
      print(
          '🍎 Apple Silicon: GPU=0, tileSize=$tileSize для ${validScaleFactor}x');
    } else if (platform == 'windows' || platform == 'linux') {
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

  Map<String, dynamic> _getFFmpegParameters(
    SystemCapabilities systemInfo,
    int inputWidth,
    int inputHeight,
    int outputWidth,
    int outputHeight,
    double inputFPS,
    int scaleFactor,
  ) {
    final totalPixels = outputWidth * outputHeight;
    final memoryGB = systemInfo.totalMemoryGB;

    String videoCodec = 'libx264';
    String preset = 'medium';
    int crf = 23;
    String pixFormat = 'yuv420p';

    if (totalPixels >= 3840 * 2160) {
      videoCodec = 'libx265';
      crf = 18;
      preset = memoryGB >= 16 ? 'slow' : 'medium';
      pixFormat = 'yuv420p10le';
    } else if (totalPixels >= 2560 * 1440) {
      videoCodec = 'libx264';
      crf = 20;
      preset = memoryGB >= 8 ? 'slow' : 'medium';
    } else {
      crf = 23;
      preset = 'medium';
    }

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

  int _calculateOptimalBitrate(
      int width, int height, double fps, int scaleFactor) {
    final totalPixels = width * height;
    final pixelsPerSecond = totalPixels * fps;

    double bitsPerPixel;
    if (totalPixels >= 3840 * 2160) {
      bitsPerPixel = 0.15;
    } else if (totalPixels >= 2560 * 1440) {
      bitsPerPixel = 0.12;
    } else if (totalPixels >= 1920 * 1080) {
      bitsPerPixel = 0.10;
    } else {
      bitsPerPixel = 0.08;
    }

    if (scaleFactor >= 4) {
      bitsPerPixel *= 1.5;
    } else if (scaleFactor >= 2) {
      bitsPerPixel *= 1.2;
    }

    final bitrateKbps = (pixelsPerSecond * bitsPerPixel / 1000).round();
    return bitrateKbps.clamp(1000, 50000);
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

  Future<void> _extractFrames(
      String videoPath, String framesDir, Map<String, dynamic> params) async {
    final executableManager = ExecutableManager.instance;
    final ffmpegPath = executableManager.ffmpegPath;
    final ffmpegParams = params['ffmpeg'] as Map<String, dynamic>;

    print('Извлечение кадров: $videoPath -> $framesDir');

    final args = [
      '-i',
      videoPath,
      '-vf',
      'fps=${ffmpegParams['fps']}',
      path.join(framesDir, 'frame_%06d.png'),
      '-hide_banner',
      '-loglevel',
      'error',
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
      runInShell: Platform.isWindows,
    );

    final audioFile = File(audioPath);
    final hasAudio = await audioFile.exists() && await audioFile.length() > 0;

    if (!hasAudio) {
      print('Видео не содержит аудиодорожку или аудио не удалось извлечь');
    } else {
      print('Аудио извлечено успешно');
    }

    return hasAudio;
  }

  // ИСПРАВЛЕННЫЙ метод upscale с отслеживанием прогресса
  Future<void> _upscaleFramesWithProgress(
    String framesDir,
    String scaledDir,
    ProcessingConfig config,
    SystemCapabilities systemInfo,
    Map<String, dynamic> optimizedParams,
    int totalFrames,
  ) async {
    final executableManager = ExecutableManager.instance;
    final waifu2xPath = executableManager.waifu2xPath;
    final waifu2xParams = optimizedParams['waifu2x'] as Map<String, dynamic>;

    print('🎯 Исправленный апскейлинг с отслеживанием прогресса');
    print('⚙️ Платформа: ${systemInfo.platform}');

    if (!await File(waifu2xPath).exists()) {
      throw Exception('waifu2x-ncnn-vulkan не найден: $waifu2xPath');
    }

    // Используем безопасные параметры
    int validScaleFactor = waifu2xParams['valid_scale_factor'];
    int validNoise = 0; // Безопасное значение

    // Получаем путь к модели
    final modelPath =
        executableManager.getModelPath(config.modelType ?? 'cunet');

    print(
        '🔒 Безопасные параметры: scale=${validScaleFactor}x, noise=$validNoise');
    print('📁 Модель: $modelPath');

    // ИСПРАВЛЕННЫЕ аргументы waifu2x
    final args = [
      '-i', framesDir,
      '-o', scaledDir,
      '-n', validNoise.toString(),
      '-s', validScaleFactor.toString(),
      '-m', modelPath,
      '-g', waifu2xParams['gpu_device'].toString(),
      '-t', waifu2xParams['tile_size'].toString(),
      '-j', '1:${waifu2xParams['threads']}:1', // load:proc:save
      '-f', 'png',
      '-v',
    ];

    print('🚀 Команда waifu2x: ${args.join(' ')}');

    // Запускаем процесс
    final process =
        await Process.start(waifu2xPath, args, runInShell: Platform.isWindows);

    // Отслеживаем прогресс в реальном времени
    Timer? progressTimer = Timer.periodic(Duration(seconds: 1), (timer) async {
      try {
        final processedFiles = await Directory(scaledDir)
            .list()
            .where((f) => f.path.endsWith('.png'))
            .length;

        final progressPercent =
            (processedFiles / totalFrames * 55).clamp(0, 55);

        _updateProgress(
          'AI апскейлинг: $processedFiles/$totalFrames кадров...',
          30.0 + progressPercent,
        );

        // Обновляем ResourceMonitor
        ResourceMonitor.instance.updateProgress(
          processedFrames: processedFiles,
          totalFrames: totalFrames,
          currentStage: 'AI апскейлинг кадров...',
          currentFile: processedFiles > 0
              ? 'frame_${processedFiles.toString().padLeft(6, '0')}.png'
              : null,
        );

        if (processedFiles >= totalFrames) {
          timer.cancel();
        }
      } catch (e) {
        // Игнорируем ошибки подсчета
      }
    });

    // Обрабатываем вывод процесса
    String errorOutput = '';

    process.stdout.transform(SystemEncoding().decoder).listen((data) {
      print('📤 waifu2x stdout: $data');
    });

    process.stderr.transform(SystemEncoding().decoder).listen((data) {
      errorOutput += data;
      // Игнорируем технические сообщения find_blob_index_by_name
      if (!data.contains('find_blob_index_by_name')) {
        print('📥 waifu2x stderr: $data');
      }
    });

    // Ждем завершения процесса
    final exitCode = await process.exitCode;
    progressTimer?.cancel();

    print('⚡ waifu2x завершен с кодом: $exitCode');

    // Проверяем результаты
    final processedFiles = await Directory(scaledDir)
        .list()
        .where((f) => f.path.endsWith('.png'))
        .length;

    print('📊 Результат: $processedFiles/$totalFrames кадров обработано');

    if (processedFiles < totalFrames * 0.8) {
      throw Exception(
          'Обработано слишком мало кадров: $processedFiles/$totalFrames');
    }

    // Финальное обновление прогресса
    ResourceMonitor.instance.updateProgress(
      processedFrames: processedFiles,
      totalFrames: totalFrames,
      currentStage: 'AI апскейлинг завершен',
    );

    print('✅ Апскейлинг успешно завершен');
  }

  Future<String> _assembleVideo(
    String scaledDir,
    String audioPath,
    ProcessingConfig config,
    bool hasAudio,
    Map<String, dynamic> optimizedParams,
  ) async {
    final executableManager = ExecutableManager.instance;
    final ffmpegPath = executableManager.ffmpegPath;
    final ffmpegParams = optimizedParams['ffmpeg'] as Map<String, dynamic>;

    print('🎬 Сборка финального видео');

    final outputPath = config.outputPath;
    final framePattern = path.join(scaledDir, 'frame_%06d.png');

    List<String> args = [
      '-framerate',
      ffmpegParams['fps'].toString(),
      '-i',
      framePattern,
    ];

    if (hasAudio) {
      args.addAll(['-i', audioPath]);
    }

    args.addAll([
      '-c:v',
      ffmpegParams['video_codec'],
      '-preset',
      ffmpegParams['preset'],
      '-crf',
      ffmpegParams['crf'].toString(),
      '-pix_fmt',
      ffmpegParams['pix_format'],
    ]);

    if (hasAudio) {
      args.addAll(['-c:a', 'aac', '-shortest']);
    }

    args.addAll([
      '-y',
      outputPath,
      '-hide_banner',
    ]);

    print('🚀 Команда сборки: ${args.join(' ')}');

    final result =
        await Process.run(ffmpegPath, args, runInShell: Platform.isWindows);

    if (result.exitCode != 0) {
      throw Exception('Ошибка сборки видео: ${result.stderr}');
    }

    final outputFile = File(outputPath);
    if (!await outputFile.exists()) {
      throw Exception('Выходной файл не был создан: $outputPath');
    }

    final outputSize = await outputFile.length();
    print(
        '✅ Видео собрано: ${(outputSize / 1024 / 1024).toStringAsFixed(1)} MB');

    return outputPath;
  }

  // Дополнительные методы для получения информации о видео
  Future<Map<String, dynamic>> getVideoInfo(String videoPath) async {
    return await _analyzeInputVideo(videoPath);
  }

  void stopProcessing() {
    _isProcessing = false;
    _updateProgress('Обработка остановлена пользователем', 0.0);
  }

  void _updateProgress(String message, double percentage) {
    _progressController.add(message);
    _percentageController.add(percentage);
  }

  Future<void> _cleanupTempFiles() async {
    if (_tempBasePath != null) {
      try {
        final tempDir = Directory(_tempBasePath!);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
          print('🧹 Временные файлы очищены: $_tempBasePath');
        }
      } catch (e) {
        print('⚠️ Ошибка очистки временных файлов: $e');
      }
      _tempBasePath = null;
    }
  }

  void dispose() {
    _progressController.close();
    _percentageController.close();
  }
}
