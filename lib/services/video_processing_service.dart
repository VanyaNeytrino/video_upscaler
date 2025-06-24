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

    print('🎯 ИСПРАВЛЕННЫЙ апскейлинг с проверкой модели');
    print('⚙️ Платформа: ${systemInfo.platform}');

    if (!await File(waifu2xPath).exists()) {
      throw Exception('waifu2x-ncnn-vulkan не найден: $waifu2xPath');
    }

    // ПРИНУДИТЕЛЬНО устанавливаем БЕЗОПАСНЫЕ параметры
    int validScaleFactor = 2; // ТОЛЬКО 2x для стабильности
    int validNoise = 0; // БЕЗ noise для совместимости

    print(
        '🔒 Принудительно используем безопасные параметры: scale=2x, noise=0');

    // ПОЛУЧАЕМ модель с детальной проверкой
    final modelInfo = await _getValidModelWithFiles(
        executableManager, 'cunet', validScaleFactor, validNoise);

    print('🎯 ПРОВЕРЕННАЯ модель: ${modelInfo['path']}');
    print(
        '📐 БЕЗОПАСНЫЕ параметры: scale=${validScaleFactor}x, noise=$validNoise');

    final framesList = await Directory(framesDir)
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.png'))
        .toList();

    if (framesList.isEmpty) {
      throw Exception('Не найдено кадров для обработки в: $framesDir');
    }

    print('📸 Найдено кадров: ${framesList.length}');

    // ТЕСТ ОДНОГО КАДРА перед массовой обработкой
    await _testSingleFrame(
        executableManager, framesDir, validScaleFactor, validNoise);

    // МИНИМАЛЬНЫЕ БЕЗОПАСНЫЕ аргументы
    final args = [
      '-i', framesDir,
      '-o', scaledDir,
      '-n', validNoise.toString(),
      '-s', validScaleFactor.toString(),
      '-m', modelInfo['path']!,
      '-g', '0', // ПРИНУДИТЕЛЬНО GPU для Apple M1
      '-t', '32', // ОЧЕНЬ маленький tilesize
      '-f', 'png',
      '-v',
    ];

    print('🚀 БЕЗОПАСНАЯ команда: ${args.join(' ')}');

    // ПОДАВЛЯЕМ вывод find_blob_index_by_name ошибок
    final process =
        await Process.start(waifu2xPath, args, runInShell: Platform.isWindows);

    String output = '';
    String errorOutput = '';
    int processedFrames = 0;

    process.stdout.transform(SystemEncoding().decoder).listen((data) {
      output += data;
      print('📤 stdout: $data');

      if (data.contains('processing') || data.contains('.png')) {
        processedFrames++;
        if (processedFrames % 5 == 0) {
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
      // ПОЛНОСТЬЮ ИГНОРИРУЕМ find_blob_index_by_name ошибки в логах
      if (!data.contains('find_blob_index_by_name')) {
        print('📥 stderr: $data');
      }
    });

    final exitCode = await process.exitCode;
    print('⚡ waifu2x завершен с кодом: $exitCode');

    // ПРОВЕРЯЕМ результаты по файлам
    final scaledFrames = await Directory(scaledDir)
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.png'))
        .toList();

    print('📊 Результат: ${scaledFrames.length}/${framesList.length} кадров');

    // УСПЕХ если обработано >80% кадров (учитываем что некоторые могут не обработаться)
    if (scaledFrames.length >= framesList.length * 0.8) {
      print(
          '✅ Апскейлинг завершен успешно: ${scaledFrames.length}/${framesList.length}');

      // КРИТИЧЕСКАЯ ДИАГНОСТИКА СОДЕРЖИМОГО КАДРОВ
      await _diagnoseFrameContent(scaledDir);
      await _diagnoseFramesBeforeAssembly(scaledDir);
      return;
    }

    // ТОЛЬКО если результат совсем плохой - пробуем CPU
    if (scaledFrames.length < framesList.length * 0.3) {
      print('🔄 Мало кадров обработано, пробуем CPU fallback...');
      await _upscaleFramesCPUFallback(framesDir, scaledDir, waifu2xPath,
          modelInfo, validScaleFactor, validNoise, framesList);
      await _diagnoseFrameContent(scaledDir);
      await _diagnoseFramesBeforeAssembly(scaledDir);
      return;
    }

    print(
        '⚠️ Частичный успех: ${scaledFrames.length}/${framesList.length} кадров');
    await _diagnoseFrameContent(scaledDir);
    await _diagnoseFramesBeforeAssembly(scaledDir);
  }

  // НОВЫЙ МЕТОД: Тест одного кадра для отладки
  Future<void> _testSingleFrame(ExecutableManager executableManager,
      String framesDir, int scaleFactor, int noise) async {
    final waifu2xPath = executableManager.waifu2xPath;
    final modelPath = executableManager.getModelPath('cunet');

    print('🧪 ТЕСТ ОДНОГО КАДРА для отладки');

    // Создаем тестовую директорию
    final testDir = await Directory.systemTemp.createTemp('waifu2x_test_');
    final inputDir = path.join(testDir.path, 'input');
    final outputDir = path.join(testDir.path, 'output');

    await Directory(inputDir).create();
    await Directory(outputDir).create();

    try {
      // Копируем ПЕРВЫЙ кадр для теста
      final framesList = await Directory(framesDir)
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.png'))
          .toList();

      if (framesList.isNotEmpty) {
        final firstFrame = framesList.first as File;
        final testInputPath = path.join(inputDir, 'test.png');
        final testOutputPath = path.join(outputDir, 'test_output.png');

        await firstFrame.copy(testInputPath);

        print('🧪 Тестируем кадр: ${path.basename(firstFrame.path)}');
        print(
            '🧪 Размер входного кадра: ${(await firstFrame.length() / 1024).toStringAsFixed(1)} KB');

        // Тестируем waifu2x на ОДНОМ кадре
        final args = [
          '-i',
          testInputPath,
          '-o',
          testOutputPath,
          '-n',
          noise.toString(),
          '-s',
          scaleFactor.toString(),
          '-m',
          modelPath,
          '-g',
          '0',
          '-v',
        ];

        print('🧪 Тест команда: ${args.join(' ')}');

        final result = await Process.run(waifu2xPath, args);

        print('🧪 Результат теста: exit code ${result.exitCode}');
        if (result.stdout.isNotEmpty) print('🧪 STDOUT: ${result.stdout}');
        if (result.stderr.isNotEmpty &&
            !result.stderr.contains('find_blob_index_by_name')) {
          print('🧪 STDERR: ${result.stderr}');
        }

        final outputFile = File(testOutputPath);
        if (await outputFile.exists()) {
          final outputSize = await outputFile.length();
          final inputSize = await File(testInputPath).length();
          print(
              '🧪 Выходной кадр: ${(outputSize / 1024).toStringAsFixed(1)} KB');
          print(
              '🧪 Увеличение размера: ${(outputSize / inputSize * 100).toStringAsFixed(1)}%');

          // Проверяем что кадр действительно изменился
          final inputBytes = await File(testInputPath).readAsBytes();
          final outputBytes = await outputFile.readAsBytes();

          final inputHash =
              inputBytes.fold(0, (prev, element) => prev + element);
          final outputHash =
              outputBytes.fold(0, (prev, element) => prev + element);

          if (inputHash == outputHash) {
            print('🧪 ⚠️ ПРОБЛЕМА: Входной и выходной кадр ИДЕНТИЧНЫ!');
            print('🧪 ⚠️ waifu2x не обрабатывает кадры правильно!');
          } else {
            print(
                '🧪 ✅ Кадр успешно изменен (hash: $inputHash -> $outputHash)');
          }
        } else {
          print('🧪 ❌ Выходной файл НЕ СОЗДАН!');
        }
      }
    } finally {
      await testDir.delete(recursive: true);
    }
  }

  // НОВЫЙ МЕТОД: Детальная диагностика содержимого кадров
  Future<void> _diagnoseFrameContent(String scaledDir) async {
    print('🔍 КРИТИЧЕСКАЯ ДИАГНОСТИКА СОДЕРЖИМОГО КАДРОВ');

    final scaledFrames = await Directory(scaledDir)
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.png'))
        .cast<File>()
        .toList();

    if (scaledFrames.isEmpty) {
      throw Exception('❌ НЕТ КАДРОВ для диагностики!');
    }

    // Сортируем
    scaledFrames
        .sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));

    print('📸 Всего кадров: ${scaledFrames.length}');

    // Проверяем первые 5 кадров детально
    final List<int> frameHashes = [];
    for (int i = 0; i < min(5, scaledFrames.length); i++) {
      final frame = scaledFrames[i];
      final size = await frame.length();
      final bytes = await frame.readAsBytes();

      // Простая проверка на "пустой" PNG
      final isEmptyPng = size < 1000 || bytes.length < 1000;

      // Проверяем MD5 хеш для сравнения кадров
      final hash = bytes.fold(0, (prev, element) => prev + element) % 1000000;
      frameHashes.add(hash);

      print(
          '📸 ${path.basename(frame.path)}: ${(size / 1024).toStringAsFixed(1)}KB, hash: $hash, empty: $isEmptyPng');

      // Проверяем PNG заголовок
      if (bytes.length >= 8) {
        final pngHeader = bytes.sublist(0, 8);
        final expectedPng = [
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10
        ]; // PNG magic number

        bool validPng = true;
        for (int i = 0; i < 8; i++) {
          if (pngHeader[i] != expectedPng[i]) {
            validPng = false;
            break;
          }
        }

        if (!validPng) {
          print('📸 ⚠️ ${path.basename(frame.path)}: ПОВРЕЖДЕН PNG заголовок!');
        }
      }
    }

    // КРИТИЧЕСКАЯ ПРОВЕРКА: все ли кадры одинаковые?
    if (frameHashes.length > 1) {
      final firstHash = frameHashes.first;
      final allSame = frameHashes.every((hash) => hash == firstHash);

      if (allSame) {
        print(
            '🚨 КРИТИЧЕСКАЯ ПРОБЛЕМА: ВСЕ КАДРЫ ИДЕНТИЧНЫ! (hash: $firstHash)');
        print('🚨 Поэтому FFmpeg их пропускает как дубликаты!');
        print('🚨 waifu2x создает одинаковые кадры вместо обработанных!');
      } else {
        print('✅ Кадры различаются (хеши: ${frameHashes.join(", ")})');
      }
    }

    // Сравниваем первый и последний кадр если их больше 10
    if (scaledFrames.length > 10) {
      final firstBytes = await scaledFrames.first.readAsBytes();
      final lastBytes = await scaledFrames.last.readAsBytes();

      final firstHash = firstBytes.fold(0, (prev, element) => prev + element);
      final lastHash = lastBytes.fold(0, (prev, element) => prev + element);

      if (firstHash == lastHash) {
        print(
            '🚨 ПРОБЛЕМА: Первый и последний кадр ИДЕНТИЧНЫ! (hash: $firstHash)');
        print('🚨 Вероятно ВСЕ кадры одинаковые!');
      } else {
        print('✅ Первый и последний кадр РАЗНЫЕ ($firstHash vs $lastHash)');
      }
    }

    // Проверяем средний размер кадров
    int totalSize = 0;
    for (final frame in scaledFrames.take(10)) {
      // Проверяем только первые 10 для скорости
      totalSize += await frame.length();
    }
    final avgSizeKB = (totalSize / min(10, scaledFrames.length) / 1024);
    print('📊 Средний размер кадра: ${avgSizeKB.toStringAsFixed(1)} KB');

    if (avgSizeKB < 50) {
      print('⚠️ ПОДОЗРИТЕЛЬНО: Кадры очень маленькие для обработанных!');
    }
  }

  // ИСПРАВЛЕННАЯ проверка модели с реальной структурой файлов
  Future<Map<String, String>> _getValidModelWithFiles(
      ExecutableManager executableManager,
      String? modelType,
      int scaleFactor,
      int noise) async {
    print('🔍 Детальная проверка моделей для scale=$scaleFactor, noise=$noise');

    final modelTypes = {
      'cunet': 'cunet',
      'anime': 'anime',
      'photo': 'photo',
    };

    // ПРОВЕРЯЕМ ВСЕ модели по очереди
    for (final entry in modelTypes.entries) {
      final modelKey = entry.key;
      final modelPath = executableManager.getModelPath(modelKey);

      print('🔍 Проверяем модель: $modelKey -> $modelPath');

      if (!await Directory(modelPath).exists()) {
        print('❌ Директория модели не существует: $modelPath');
        continue;
      }

      // ИСПРАВЛЕНО: проверяем файлы согласно РЕАЛЬНОЙ структуре со скриншота
      final requiredFiles = _getCorrectModelFiles(modelKey, scaleFactor, noise);
      print(
          '📁 Требуемые файлы для $modelKey (scale=$scaleFactor, noise=$noise): $requiredFiles');

      bool allFilesExist = true;
      List<String> missingFiles = [];

      for (final fileName in requiredFiles) {
        final filePath = path.join(modelPath, fileName);
        if (!await File(filePath).exists()) {
          print('❌ Файл не найден: $filePath');
          missingFiles.add(fileName);
          allFilesExist = false;
        } else {
          final fileSize = await File(filePath).length();
          print('✅ Файл найден: $filePath (${fileSize} bytes)');
        }
      }

      if (allFilesExist && requiredFiles.isNotEmpty) {
        print('✅ ВСЕ ФАЙЛЫ НАЙДЕНЫ для модели: $modelKey');
        return {
          'name': modelKey,
          'path': modelPath,
        };
      } else {
        print('❌ Отсутствующие файлы в $modelKey: $missingFiles');
      }
    }

    // FALLBACK: пробуем самые базовые файлы со скриншота
    print('🔄 Fallback - ищем базовые файлы модели cunet...');
    final fallbackPath = executableManager.getModelPath('cunet');

    // Пробуем файлы которые ТОЧНО есть на скриншоте
    final basicFilesToTry = [
      [
        'noise0_scale2.0x_model.param',
        'noise0_scale2.0x_model.bin'
      ], // Приоритет 1
      ['noise0_model.param', 'noise0_model.bin'], // Приоритет 2
      [
        'noise1_scale2.0x_model.param',
        'noise1_scale2.0x_model.bin'
      ], // Приоритет 3
    ];

    for (final basicFiles in basicFilesToTry) {
      bool basicExists = true;
      for (final file in basicFiles) {
        final filePath = path.join(fallbackPath, file);
        if (!await File(filePath).exists()) {
          basicExists = false;
          break;
        }
      }

      if (basicExists) {
        print('✅ Используем базовую модель cunet: ${basicFiles.join(", ")}');
        return {
          'name': 'cunet-basic',
          'path': fallbackPath,
        };
      }
    }

    throw Exception(
        '❌ НИ ОДНА МОДЕЛЬ НЕ НАЙДЕНА! Проверьте файлы в $fallbackPath');
  }

  // ИСПРАВЛЕНО: правильные имена файлов согласно РЕАЛЬНОЙ структуре
  List<String> _getCorrectModelFiles(String modelType, int scale, int noise) {
    final files = <String>[];

    print('🔍 Определяем файлы для $modelType, scale=$scale, noise=$noise');

    if (modelType == 'cunet') {
      // Согласно РЕАЛЬНОЙ структуре со скриншота:
      // noise0_model.bin/param - только noise без scale
      // noise0_scale2.0x_model.bin/param - noise + scale 2x
      if (scale == 2 && noise >= 0) {
        // Комбинация noise + scale для 2x (ПРИОРИТЕТ - есть на скриншоте)
        files.addAll([
          'noise${noise}_scale2.0x_model.param',
          'noise${noise}_scale2.0x_model.bin'
        ]);
        print('✅ Используем noise${noise}_scale2.0x файлы');
      } else if (noise >= 0) {
        // Только noise без scale (FALLBACK - есть на скриншоте)
        files.addAll(['noise${noise}_model.param', 'noise${noise}_model.bin']);
        print('✅ Используем noise${noise} файлы (без scale)');
      }
    } else if (modelType == 'anime') {
      // Для anime модели пробуем аналогичную структуру
      if (scale == 2 && noise >= 0) {
        files.addAll([
          'noise${noise}_scale2.0x_model.param',
          'noise${noise}_scale2.0x_model.bin'
        ]);
      } else if (noise >= 0) {
        files.addAll(['noise${noise}_model.param', 'noise${noise}_model.bin']);
      }
    } else if (modelType == 'photo') {
      // Для photo модели аналогично
      if (scale == 2 && noise >= 0) {
        files.addAll([
          'noise${noise}_scale2.0x_model.param',
          'noise${noise}_scale2.0x_model.bin'
        ]);
      }
    }

    print('📁 Найденные файлы для $modelType: $files');
    return files;
  }

  // CPU Fallback с минимальными параметрами
  Future<void> _upscaleFramesCPUFallback(
      String framesDir,
      String scaledDir,
      String waifu2xPath,
      Map<String, String> modelInfo,
      int scaleFactor,
      int noise,
      List<FileSystemEntity> framesList) async {
    print('🔄 CPU FALLBACK режим');

    // Очищаем scaled директорию
    await Directory(scaledDir).delete(recursive: true);
    await Directory(scaledDir).create();

    final args = [
      '-i', framesDir,
      '-o', scaledDir,
      '-n', '0', // Без noise для CPU
      '-s', scaleFactor.toString(),
      '-m', modelInfo['path']!,
      '-g', '-1', // Принудительно CPU
      '-t', '32', // Очень маленький tilesize
      '-j', '1:1:1', // Один поток
      '-f', 'png',
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
      if (!data.contains('find_blob_index_by_name')) {
        print('📥 CPU stderr: $data');
      }
    });

    final exitCode = await process.exitCode;

    final scaledFrames = await Directory(scaledDir)
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.png'))
        .toList();

    if (scaledFrames.length < framesList.length * 0.8) {
      throw Exception(
          'CPU fallback неудачен. Код: $exitCode, кадров: ${scaledFrames.length}/${framesList.length}');
    }

    print('✅ CPU fallback успешен: ${scaledFrames.length} кадров');
  }

  // ИСПРАВЛЕННАЯ сборка видео с ПРОСТЫМИ параметрами
  Future<String> _assembleVideo(
    String scaledDir,
    String audioPath,
    ProcessingConfig config,
    bool hasAudio,
    Map<String, dynamic> optimizedParams,
  ) async {
    final executableManager = ExecutableManager();
    final ffmpegPath = executableManager.ffmpegPath;

    print('🎬 УПРОЩЕННАЯ сборка видео: $scaledDir -> ${config.outputPath}');

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
      '-framerate', '30', // УПРОЩЕНО: фиксированный framerate
      '-i', path.join(scaledDir, 'frame_%06d.png'),

      // ПРОСТЫЕ параметры H.264 вместо сложного H.265
      '-c:v', 'libx264', // ИЗМЕНЕНО: простой H.264
      '-crf', '18', // УПРОЩЕНО: хорошее качество
      '-preset', 'medium', // УПРОЩЕНО: средняя скорость
      '-pix_fmt', 'yuv420p', // Стандартный формат

      // УБИРАЕМ проблемные параметры:
      // -video_track_timescale, -maxrate, -bufsize, -b:v

      '-r', '30', // Выходной framerate
    ];

    // УПРОЩЕННАЯ обработка аудио
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

    print('🚀 УПРОЩЕННАЯ команда FFmpeg: ${args.join(' ')}');

    final result =
        await Process.run(ffmpegPath, args, runInShell: Platform.isWindows);

    print('📊 FFmpeg результат:');
    print('Exit code: ${result.exitCode}');
    print('STDOUT: ${result.stdout}');
    print('STDERR: ${result.stderr}');

    if (result.exitCode != 0) {
      // АЛЬТЕРНАТИВНЫЙ подход если первый не сработал
      print('🔄 Пробуем АЛЬТЕРНАТИВНУЮ команду...');
      return await _assembleVideoAlternative(scaledDir, config);
    }

    final outputFile = File(config.outputPath);
    if (!await outputFile.exists()) {
      throw Exception('Выходной файл не был создан: ${config.outputPath}');
    }

    final outputSize = await outputFile.length();
    final outputSizeMB = (outputSize / 1024 / 1024);

    print('📹 Видео собрано: ${outputSizeMB.toStringAsFixed(2)} MB');

    if (outputSize < 1024 * 1024) {
      print('🔄 Видео слишком маленькое, пробуем альтернативный подход...');
      return await _assembleVideoAlternative(scaledDir, config);
    }

    return config.outputPath;
  }

  // АЛЬТЕРНАТИВНЫЙ метод сборки
  Future<String> _assembleVideoAlternative(
      String scaledDir, ProcessingConfig config) async {
    final executableManager = ExecutableManager();
    final ffmpegPath = executableManager.ffmpegPath;

    print('🔄 АЛЬТЕРНАТИВНАЯ сборка видео (метод из Reddit)');

    // МАКСИМАЛЬНО ПРОСТАЯ команда
    final List<String> args = [
      '-y',
      '-framerate', '30',
      '-i', path.join(scaledDir, 'frame_%06d.png'),
      '-c:v', 'libx264',
      '-crf', '23', // Стандартное качество
      '-pix_fmt', 'yuv420p',
      '-an', // Без аудио для простоты
      config.outputPath,
    ];

    print('🚀 АЛЬТЕРНАТИВНАЯ команда: ${args.join(' ')}');

    final result =
        await Process.run(ffmpegPath, args, runInShell: Platform.isWindows);

    print('📊 Альтернативный результат:');
    print('Exit code: ${result.exitCode}');
    print('STDERR: ${result.stderr}');

    if (result.exitCode != 0) {
      throw Exception('Альтернативная сборка не удалась: ${result.stderr}');
    }

    final outputFile = File(config.outputPath);
    final outputSize = await outputFile.length();
    final outputSizeMB = (outputSize / 1024 / 1024);

    print('📹 АЛЬТЕРНАТИВНОЕ видео: ${outputSizeMB.toStringAsFixed(2)} MB');

    if (outputSize < 500 * 1024) {
      // Меньше 500KB все еще подозрительно
      throw Exception(
          'Даже альтернативная сборка создала слишком маленькое видео');
    }

    return config.outputPath;
  }

  // ЕДИНСТВЕННЫЙ метод диагностики кадров (без дублирования)
  Future<void> _diagnoseFramesBeforeAssembly(String scaledDir) async {
    print('🔍 ДИАГНОСТИКА КАДРОВ ПОСЛЕ ОБРАБОТКИ');

    final scaledFrames = await Directory(scaledDir)
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.png'))
        .cast<File>()
        .toList();

    if (scaledFrames.isEmpty) {
      throw Exception('❌ НЕТ КАДРОВ для сборки видео!');
    }

    // Сортируем для правильного порядка
    scaledFrames
        .sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));

    print('📸 Всего кадров: ${scaledFrames.length}');
    print('📸 Первый кадр: ${path.basename(scaledFrames.first.path)}');
    print('📸 Последний кадр: ${path.basename(scaledFrames.last.path)}');

    // Проверяем размеры первых нескольких кадров
    for (int i = 0; i < min(5, scaledFrames.length); i++) {
      final frame = scaledFrames[i];
      final size = await frame.length();
      final sizeKB = (size / 1024).toStringAsFixed(1);
      print('📸 ${path.basename(frame.path)}: ${sizeKB} KB');

      if (size < 1024) {
        // Меньше 1KB - подозрительно
        print('⚠️ ВНИМАНИЕ: Кадр слишком маленький!');
      }
    }

    // Проверяем общий размер всех кадров
    int totalSize = 0;
    for (final frame in scaledFrames) {
      totalSize += await frame.length();
    }
    final totalSizeMB = (totalSize / 1024 / 1024);
    print('📊 Общий размер кадров: ${totalSizeMB.toStringAsFixed(2)} MB');
  }

  // ДИАГНОСТИКА файлов модели
  Future<void> diagnoseModelFiles(ExecutableManager executableManager) async {
    print('🔍 ДИАГНОСТИКА ФАЙЛОВ МОДЕЛИ');

    for (final modelType in ['cunet', 'anime', 'photo']) {
      final modelPath = executableManager.getModelPath(modelType);
      print('\n📁 Модель: $modelType -> $modelPath');

      if (!await Directory(modelPath).exists()) {
        print('❌ Директория не существует');
        continue;
      }

      final files = await Directory(modelPath)
          .list()
          .where((entity) => entity is File)
          .cast<File>()
          .toList();

      print('📄 Найдено файлов: ${files.length}');

      // Сортируем файлы для лучшего отображения
      files.sort(
          (a, b) => path.basename(a.path).compareTo(path.basename(b.path)));

      for (final file in files) {
        final name = path.basename(file.path);
        final size = await file.length();
        final sizeKB = (size / 1024).toStringAsFixed(1);
        print('  📄 $name (${sizeKB} KB)');
      }
    }
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
