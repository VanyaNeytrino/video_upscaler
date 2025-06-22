import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class ExecutableManager {
  static final ExecutableManager _instance = ExecutableManager._internal();
  factory ExecutableManager() => _instance;
  ExecutableManager._internal();

  String? _ffmpegPath;
  String? _waifu2xPath;
  String? _modelsDir;

  Future<void> initializeExecutables() async {
    final appDir = await getApplicationSupportDirectory();
    final executablesDir = Directory(path.join(appDir.path, 'executables'));

    if (!await executablesDir.exists()) {
      await executablesDir.create(recursive: true);
    }

    await _extractAllFiles(executablesDir.path);
  }

  Future<void> _extractAllFiles(String targetDir) async {
    final platform = _getPlatformName();
    print('Извлечение файлов для платформы: $platform');

    final platformDir = Directory(path.join(targetDir, platform));
    if (!await platformDir.exists()) {
      await platformDir.create(recursive: true);
    }

    try {
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);

      final platformAssets =
          manifestMap.keys
              .where(
                (String key) => key.startsWith('assets/executables/$platform/'),
              )
              .toList();

      print('Найдено ${platformAssets.length} файлов для извлечения');

      for (final assetPath in platformAssets) {
        await _extractSingleFile(assetPath, targetDir);
      }

      _setExecutablePaths(targetDir, platform);

      print('Все файлы успешно извлечены');
    } catch (e) {
      throw Exception('Ошибка при извлечении файлов: $e');
    }
  }

  Future<void> _extractSingleFile(
    String assetPath,
    String baseTargetDir,
  ) async {
    try {
      final relativePath = assetPath.replaceFirst('assets/executables/', '');
      final targetPath = path.join(baseTargetDir, relativePath);

      final targetFile = File(targetPath);
      final targetDirPath = targetFile.parent;
      if (!await targetDirPath.exists()) {
        await targetDirPath.create(recursive: true);
      }

      final data = await rootBundle.load(assetPath);
      await targetFile.writeAsBytes(data.buffer.asUint8List());

      if (!Platform.isWindows && _isExecutableFile(path.basename(targetPath))) {
        await Process.run('chmod', ['+x', targetPath]);
      }

      print('Извлечен: $relativePath');
    } catch (e) {
      print('Ошибка при извлечении $assetPath: $e');
      throw e;
    }
  }

  void _setExecutablePaths(String baseDir, String platform) {
    if (platform == 'windows') {
      _waifu2xPath = path.join(baseDir, platform, 'waifu2x-ncnn-vulkan.exe');
      _ffmpegPath = path.join(baseDir, platform, 'ffmpeg.exe');
    } else {
      _waifu2xPath = path.join(baseDir, platform, 'waifu2x-ncnn-vulkan');
      _ffmpegPath = path.join(baseDir, platform, 'ffmpeg');
    }

    _modelsDir = path.join(baseDir, platform);

    print('Waifu2x path: $_waifu2xPath');
    print('FFmpeg path: $_ffmpegPath');
    print('Models dir: $_modelsDir');
  }

  bool _isExecutableFile(String filename) {
    return filename == 'waifu2x-ncnn-vulkan' ||
        filename == 'waifu2x-ncnn-vulkan.exe' ||
        filename == 'ffmpeg' ||
        filename == 'ffmpeg.exe';
  }

  String _getPlatformName() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  String get ffmpegPath {
    if (_ffmpegPath == null) {
      throw StateError(
        'ExecutableManager не инициализирован. Вызовите initializeExecutables() сначала.',
      );
    }
    return _ffmpegPath!;
  }

  String get waifu2xPath {
    if (_waifu2xPath == null) {
      throw StateError(
        'ExecutableManager не инициализирован. Вызовите initializeExecutables() сначала.',
      );
    }
    return _waifu2xPath!;
  }

  String get modelsDir {
    if (_modelsDir == null) {
      throw StateError(
        'ExecutableManager не инициализирован. Вызовите initializeExecutables() сначала.',
      );
    }
    return _modelsDir!;
  }

  String getModelPath(String modelType) {
    final availableModels = {
      'cunet': 'models-cunet',
      'anime': 'models-upconv_7_anime_style_art_rgb',
      'photo': 'models-upconv_7_photo',
    };

    final modelFolder = availableModels[modelType];
    if (modelFolder == null) {
      throw ArgumentError(
        'Неизвестный тип модели: $modelType. Доступные: ${availableModels.keys.join(', ')}',
      );
    }

    return path.join(modelsDir, modelFolder);
  }

  Future<bool> validateInstallation() async {
    try {
      if (!await File(ffmpegPath).exists()) {
        print('FFmpeg не найден: $ffmpegPath');
        return false;
      }

      if (!await File(waifu2xPath).exists()) {
        print('Waifu2x не найден: $waifu2xPath');
        return false;
      }

      final modelTypes = ['cunet', 'anime', 'photo'];
      for (final modelType in modelTypes) {
        final modelPath = getModelPath(modelType);
        if (!await Directory(modelPath).exists()) {
          print('Модель $modelType не найдена: $modelPath');
          return false;
        }
      }

      print('Все файлы найдены и готовы к использованию');
      return true;
    } catch (e) {
      print('Ошибка при проверке установки: $e');
      return false;
    }
  }

  Future<int> getInstallationSize() async {
    int totalSize = 0;

    try {
      final platformDir = Directory(path.dirname(waifu2xPath));
      await for (final entity in platformDir.list(recursive: true)) {
        if (entity is File) {
          final stat = await entity.stat();
          totalSize += stat.size;
        }
      }
    } catch (e) {
      print('Ошибка при подсчете размера: $e');
    }

    return totalSize;
  }
}
