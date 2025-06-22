import 'dart:io';
import 'dart:async';
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
          'ExecutableManager не инициализирован или файлы отсутствуют. Пожалуйста, перезапустите приложение.',
        );
      }

      _updateProgress('Анализ системы...', 5.0);
      final systemInfo = await SystemInfoService.analyzeSystem();
      print(
        'Система: ${systemInfo.platform}, CPU: ${systemInfo.cpuCores}, GPU: ${systemInfo.availableGPUs.length}',
      );

      _updateProgress('Создание временных директорий...', 10.0);
      final tempDir = await _createTempDirectories();

      _updateProgress('Извлечение кадров из видео...', 15.0);
      await _extractFrames(config.inputVideoPath, tempDir['frames']!);

      _updateProgress('Извлечение аудиодорожки...', 25.0);
      final hasAudio = await _extractAudio(
        config.inputVideoPath,
        tempDir['audio']!,
      );

      _updateProgress('AI апскейлинг кадров...', 30.0);
      await _upscaleFrames(
        tempDir['frames']!,
        tempDir['scaled']!,
        config,
        systemInfo,
      );

      _updateProgress('Сборка финального видео...', 85.0);
      final outputPath = await _assembleVideo(
        tempDir['scaled']!,
        tempDir['audio']!,
        config,
        hasAudio,
      );

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

  Future<void> _extractFrames(String videoPath, String framesDir) async {
    final executableManager = ExecutableManager();
    final ffmpegPath = executableManager.ffmpegPath;

    print('Извлечение кадров: $videoPath -> $framesDir');

    final infoResult = await Process.run(ffmpegPath, [
      '-i',
      videoPath,
      '-hide_banner',
    ], runInShell: Platform.isWindows);

    final result = await Process.run(ffmpegPath, [
      '-i',
      videoPath,
      '-vf',
      'fps=30',
      path.join(framesDir, 'frame_%06d.png'),
      '-hide_banner',
      '-loglevel',
      'error',
    ], runInShell: Platform.isWindows);

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

    final result = await Process.run(ffmpegPath, [
      '-i',
      videoPath,
      '-vn',
      '-acodec',
      'copy',
      audioPath,
      '-hide_banner',
      '-loglevel',
      'error',
    ], runInShell: Platform.isWindows);

    final audioFile = File(audioPath);
    final hasAudio = await audioFile.exists() && await audioFile.length() > 0;

    if (!hasAudio) {
      print('Видео не содержит аудиодорожку или аудио не удалось извлечь');
    } else {
      print('Аудио извлечено успешно');
    }

    return hasAudio;
  }

  Future<void> _upscaleFrames(
    String framesDir,
    String scaledDir,
    ProcessingConfig config,
    SystemCapabilities systemInfo,
  ) async {
    final executableManager = ExecutableManager();
    final waifu2xPath = executableManager.waifu2xPath;

    String modelPath;
    switch (config.modelType ?? 'cunet') {
      case 'anime':
        modelPath = executableManager.getModelPath('anime');
        break;
      case 'photo':
        modelPath = executableManager.getModelPath('photo');
        break;
      default:
        modelPath = executableManager.getModelPath('cunet');
    }

    print('Используется модель: $modelPath');
    print('waifu2x путь: $waifu2xPath');

    final args = [
      '-i',
      framesDir,
      '-o',
      scaledDir,
      '-n',
      config.scaleNoise.toString(),
      '-s',
      config.scaleFactor.toString(),
      '-f',
      'png',
      '-m',
      modelPath,
      '-v',
    ];

    if (Platform.isMacOS) {
      print('macOS: используется автоматический выбор устройства');
      args.addAll(['-t', '0']);
    } else if (systemInfo.hasVulkan && systemInfo.availableGPUs.isNotEmpty) {
      args.addAll(['-g', '0']);
      args.addAll(['-t', '0']);
      print('Используется GPU для обработки');
    } else {
      args.addAll(['-g', '-1']);
      args.addAll(['-t', '400']);
      print('Используется CPU с tilesize 400');
    }

    print('Запуск waifu2x с аргументами: ${args.join(' ')}');

    final process = await Process.start(
      waifu2xPath,
      args,
      runInShell: Platform.isWindows,
    );

    String output = '';
    process.stdout.transform(SystemEncoding().decoder).listen((data) {
      output += data;
      print('waifu2x stdout: $data');
    });

    process.stderr.transform(SystemEncoding().decoder).listen((data) {
      output += data;
      print('waifu2x stderr: $data');

      if (data.contains('%') || data.contains('processing')) {
        _updateProgress('AI апскейлинг: обработка кадров...', 50.0);
      }
    });

    final exitCode = await process.exitCode;

    if (exitCode != 0) {
      throw Exception('Ошибка waifu2x (код: $exitCode): $output');
    }

    final scaledFrames = await Directory(scaledDir).list().toList();
    print('Апскейлинг завершен. Обработано кадров: ${scaledFrames.length}');
  }

  Future<String> _assembleVideo(
    String scaledDir,
    String audioPath,
    ProcessingConfig config,
    bool hasAudio,
  ) async {
    final executableManager = ExecutableManager();
    final ffmpegPath = executableManager.ffmpegPath;

    print('Сборка видео: $scaledDir -> ${config.outputPath}');

    final args = [
      '-framerate',
      config.framerate.toString(),
      '-i',
      path.join(scaledDir, 'frame_%06d.png'),
    ];

    if (hasAudio && await File(audioPath).exists()) {
      args.addAll(['-i', audioPath]);
      args.addAll(['-c:a', config.audioCodec]);
    } else {
      args.addAll(['-an']);
    }

    args.addAll([
      '-c:v',
      config.videoCodec,
      '-pix_fmt',
      'yuv420p',
      '-crf',
      '18',
      '-preset',
      'medium',
      config.outputPath,
      '-hide_banner',
      '-loglevel',
      'error',
      '-y',
    ]);

    print('Запуск сборки с аргументами: ${args.join(' ')}');

    final result = await Process.run(
      ffmpegPath,
      args,
      runInShell: Platform.isWindows,
    );

    if (result.exitCode != 0) {
      throw Exception('Ошибка сборки видео: ${result.stderr}');
    }

    final outputFile = File(config.outputPath);
    if (!await outputFile.exists()) {
      throw Exception('Выходной файл не был создан');
    }

    final outputSize = await outputFile.length();
    print(
      'Видео собрано успешно. Размер: ${(outputSize / 1024 / 1024).toStringAsFixed(2)} MB',
    );

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
    final executableManager = ExecutableManager();
    final ffmpegPath = executableManager.ffmpegPath;

    final result = await Process.run(ffmpegPath, [
      '-i',
      videoPath,
      '-hide_banner',
    ], runInShell: Platform.isWindows);

    final output = result.stderr.toString();

    return {
      'path': videoPath,
      'info': output,
      'exists': await File(videoPath).exists(),
    };
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
