import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

class ExecutableManager {
  // ДОБАВЛЯЕМ СИНГЛТОН ПАТТЕРН
  static ExecutableManager? _instance;
  static ExecutableManager get instance {
    _instance ??= ExecutableManager._internal();
    return _instance!;
  }

  ExecutableManager._internal();

  Directory? executablesDir;
  bool _isInitialized = false;

  // ДОБАВЛЯЕМ геттер для проверки инициализации
  bool get isInitialized => _isInitialized;

  String get waifu2xPath {
    if (executablesDir == null || !_isInitialized) {
      throw Exception(
          'ExecutableManager не инициализирован! Вызовите initializeExecutables() сначала.');
    }

    if (Platform.isMacOS) {
      return path.join(executablesDir!.path, 'macos', 'waifu2x-ncnn-vulkan');
    } else if (Platform.isWindows) {
      return path.join(
          executablesDir!.path, 'windows', 'waifu2x-ncnn-vulkan.exe');
    } else {
      return path.join(executablesDir!.path, 'linux', 'waifu2x-ncnn-vulkan');
    }
  }

  String get ffmpegPath {
    if (executablesDir == null || !_isInitialized) {
      throw Exception(
          'ExecutableManager не инициализирован! Вызовите initializeExecutables() сначала.');
    }

    if (Platform.isMacOS) {
      return path.join(executablesDir!.path, 'macos', 'ffmpeg');
    } else if (Platform.isWindows) {
      return path.join(executablesDir!.path, 'windows', 'ffmpeg.exe');
    } else {
      return path.join(executablesDir!.path, 'linux', 'ffmpeg');
    }
  }

  String get modelsDir {
    if (executablesDir == null || !_isInitialized) {
      throw Exception(
          'ExecutableManager не инициализирован! Вызовите initializeExecutables() сначала.');
    }

    final platformDir = Platform.isMacOS
        ? 'macos'
        : Platform.isWindows
            ? 'windows'
            : 'linux';
    return path.join(executablesDir!.path, platformDir);
  }

  String getModelPath(String modelType) {
    if (executablesDir == null || !_isInitialized) {
      throw Exception(
          'ExecutableManager не инициализирован! Вызовите initializeExecutables() сначала.');
    }

    final platformDir = Platform.isMacOS
        ? 'macos'
        : Platform.isWindows
            ? 'windows'
            : 'linux';

    switch (modelType) {
      case 'cunet':
        return path.join(executablesDir!.path, platformDir, 'models-cunet');
      case 'anime':
        return path.join(executablesDir!.path, platformDir,
            'models-upconv_7_anime_style_art_rgb');
      case 'photo':
        return path.join(
            executablesDir!.path, platformDir, 'models-upconv_7_photo');
      default:
        return path.join(executablesDir!.path, platformDir, 'models-cunet');
    }
  }

  Future<Map<String, dynamic>> getInstallationSize() async {
    if (executablesDir == null || !_isInitialized) {
      return {
        'error': 'ExecutableManager не инициализирован',
        'total_size_bytes': 0,
        'total_size_mb': '0.0',
        'file_count': 0,
      };
    }

    // ... остальной код метода остается тем же ...
    int totalSizeBytes = 0;
    int fileCount = 0;

    try {
      final platformDir = Platform.isMacOS
          ? 'macos'
          : Platform.isWindows
              ? 'windows'
              : 'linux';
      final installDir =
          Directory(path.join(executablesDir!.path, platformDir));

      if (await installDir.exists()) {
        await for (final entity in installDir.list(recursive: true)) {
          if (entity is File) {
            final size = await entity.length();
            totalSizeBytes += size;
            fileCount++;
          }
        }
      }

      return {
        'total_size_bytes': totalSizeBytes,
        'total_size_mb': (totalSizeBytes / 1024 / 1024).toStringAsFixed(2),
        'file_count': fileCount,
        'installation_path': installDir.path,
      };
    } catch (e) {
      return {
        'error': e.toString(),
        'total_size_bytes': 0,
        'total_size_mb': '0.0',
        'file_count': 0,
      };
    }
  }

  // ИСПРАВЛЕННАЯ инициализация
  Future<void> initializeExecutables() async {
    if (_isInitialized) {
      print('✅ ExecutableManager уже инициализирован');
      return;
    }

    print('🔄 Инициализация ExecutableManager...');

    await _setupExecutablesDirectory();
    await _extractAllFromAssets();
    await _makeExecutablesExecutable();

    _isInitialized = true; // УСТАНАВЛИВАЕМ ФЛАГ
    print('✅ ExecutableManager успешно инициализирован');
  }

  // ОСТАЛЬНЫЕ МЕТОДЫ ОСТАЮТСЯ БЕЗ ИЗМЕНЕНИЙ...
  Future<void> _setupExecutablesDirectory() async {
    final appSupportDir = await _getApplicationSupportDirectory();
    executablesDir = Directory(path.join(appSupportDir.path, 'executables'));

    if (!await executablesDir!.exists()) {
      await executablesDir!.create(recursive: true);
    }
  }

  Future<void> _extractAllFromAssets() async {
    final platformDir = Platform.isMacOS
        ? 'macos'
        : Platform.isWindows
            ? 'windows'
            : 'linux';
    print('Извлечение ВСЕХ файлов для платформы: $platformDir');

    final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assetKeys = assetManifest
        .listAssets()
        .where((key) => key.startsWith('assets/executables/$platformDir/'))
        .toList();

    print('Найдено ${assetKeys.length} файлов для извлечения');

    for (final assetKey in assetKeys) {
      final relativePath =
          assetKey.replaceFirst('assets/executables/$platformDir/', '');
      final targetPath =
          path.join(executablesDir!.path, platformDir, relativePath);

      final targetDir = Directory(path.dirname(targetPath));
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final byteData = await rootBundle.load(assetKey);
      final bytes = byteData.buffer.asUint8List();

      await File(targetPath).writeAsBytes(bytes);

      if (assetKey.contains('models-') &&
          (assetKey.endsWith('.bin') || assetKey.endsWith('.param'))) {
        print(
            'Извлечен файл модели: $relativePath (${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB)');
      } else {
        print('Извлечен: $relativePath');
      }
    }
  }

  Future<void> _makeExecutablesExecutable() async {
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['+x', waifu2xPath]);
        await Process.run('chmod', ['+x', ffmpegPath]);
        print('Исполняемые файлы сделаны исполняемыми');
      } catch (e) {
        print('Ошибка при установке прав доступа: $e');
      }
    }
  }

  Future<bool> validateInstallation() async {
    if (!_isInitialized) {
      print('❌ ExecutableManager не инициализирован');
      return false;
    }

    print('🔍 Проверка установки исполняемых файлов...');

    if (!await File(waifu2xPath).exists()) {
      print('❌ waifu2x не найден');
      return false;
    }

    if (!await File(ffmpegPath).exists()) {
      print('❌ FFmpeg не найден');
      return false;
    }

    if (!await _validateModelFiles()) {
      print('❌ Некорректные файлы модели');
      return false;
    }

    print('✅ Все файлы найдены и готовы к использованию');
    return true;
  }

  Future<bool> _validateModelFiles() async {
    print('🔍 ПРОВЕРКА ФАЙЛОВ МОДЕЛИ');

    final modelPath = getModelPath('cunet');

    if (!await Directory(modelPath).exists()) {
      print('❌ Директория модели не существует: $modelPath');
      return false;
    }

    final files = await Directory(modelPath)
        .list()
        .where((entity) =>
            entity is File &&
            (entity.path.endsWith('.bin') || entity.path.endsWith('.param')))
        .cast<File>()
        .toList();

    if (files.isEmpty) {
      print('❌ Нет файлов модели в: $modelPath');
      return false;
    }

    for (final file in files) {
      final size = await file.length();
      final name = path.basename(file.path);

      print('📄 $name: ${(size / 1024 / 1024).toStringAsFixed(1)} MB');

      if (size < 100 * 1024) {
        print('🚨 ПОДОЗРИТЕЛЬНО МАЛЕНЬКИЙ ФАЙЛ: $name (${size} bytes)');
        return false;
      }
    }

    return true;
  }

  Future<Directory> _getApplicationSupportDirectory() async {
    if (Platform.isMacOS) {
      return Directory(path.join(Platform.environment['HOME']!, 'Library',
          'Application Support', 'com.example.videoUpscaler'));
    } else if (Platform.isWindows) {
      return Directory(
          path.join(Platform.environment['APPDATA']!, 'VideoUpscaler'));
    } else {
      return Directory(path.join(
          Platform.environment['HOME']!, '.local', 'share', 'video_upscaler'));
    }
  }

  Future<void> _cleanupExecutables() async {
    if (executablesDir != null && await executablesDir!.exists()) {
      await executablesDir!.delete(recursive: true);
      _isInitialized = false;
      print('Очистка исполняемых файлов завершена');
    }
  }
}
