import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

class ExecutableManager {
  static ExecutableManager? _instance;
  static ExecutableManager get instance {
    _instance ??= ExecutableManager._internal();
    return _instance!;
  }

  ExecutableManager._internal();

  Directory? executablesDir;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  // Убираем дублирование логики платформы
  String get _platformDir {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    return 'linux';
  }

  String get _executableExtension => Platform.isWindows ? '.exe' : '';

  String get waifu2xPath {
    _checkInitialization();
    return path.join(executablesDir!.path, _platformDir,
        'waifu2x-ncnn-vulkan$_executableExtension');
  }

  String get ffmpegPath {
    _checkInitialization();
    return path.join(
        executablesDir!.path, _platformDir, 'ffmpeg$_executableExtension');
  }

  String get modelsDir {
    _checkInitialization();
    return path.join(executablesDir!.path, _platformDir);
  }

  String getModelPath(String modelType) {
    _checkInitialization();

    final modelFolders = {
      'cunet': 'models-cunet',
      'anime': 'models-upconv_7_anime_style_art_rgb',
      'photo': 'models-upconv_7_photo',
    };

    final modelFolder = modelFolders[modelType] ?? 'models-cunet';
    return path.join(executablesDir!.path, _platformDir, modelFolder);
  }

  // Упрощенный метод получения размера (убираем избыточную детализацию)
  Future<int> getInstallationSizeBytes() async {
    if (!_isInitialized || executablesDir == null) return 0;

    try {
      final installDir =
          Directory(path.join(executablesDir!.path, _platformDir));
      if (!await installDir.exists()) return 0;

      int totalSize = 0;
      await for (final entity in installDir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      return totalSize;
    } catch (e) {
      return 0;
    }
  }

  Future<void> initializeExecutables() async {
    if (_isInitialized) {
      print('✅ ExecutableManager уже инициализирован');
      return;
    }

    print('🔄 Инициализация ExecutableManager...');

    await _setupExecutablesDirectory();
    await _extractAllFromAssets();
    await _makeExecutablesExecutable();

    _isInitialized = true;
    print('✅ ExecutableManager успешно инициализирован');
  }

  Future<void> _setupExecutablesDirectory() async {
    final appSupportDir = await _getApplicationSupportDirectory();
    executablesDir = Directory(path.join(appSupportDir.path, 'executables'));

    if (!await executablesDir!.exists()) {
      await executablesDir!.create(recursive: true);
    }
  }

  // Убираем избыточное логирование размеров файлов
  Future<void> _extractAllFromAssets() async {
    print('Извлечение файлов для платформы: $_platformDir');

    final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assetKeys = assetManifest
        .listAssets()
        .where((key) => key.startsWith('assets/executables/$_platformDir/'))
        .toList();

    print('Найдено ${assetKeys.length} файлов для извлечения');

    for (final assetKey in assetKeys) {
      await _extractSingleAsset(assetKey);
    }
  }

  Future<void> _extractSingleAsset(String assetKey) async {
    final relativePath =
        assetKey.replaceFirst('assets/executables/$_platformDir/', '');
    final targetPath =
        path.join(executablesDir!.path, _platformDir, relativePath);

    final targetDir = Directory(path.dirname(targetPath));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final byteData = await rootBundle.load(assetKey);
    final bytes = byteData.buffer.asUint8List();
    await File(targetPath).writeAsBytes(bytes);

    // Упрощенное логирование без размеров
    print('Извлечен: $relativePath');
  }

  Future<void> _makeExecutablesExecutable() async {
    if (Platform.isWindows) return;

    try {
      await Process.run('chmod', ['+x', waifu2xPath]);
      await Process.run('chmod', ['+x', ffmpegPath]);
      print('Исполняемые файлы сделаны исполняемыми');
    } catch (e) {
      print('Ошибка при установке прав доступа: $e');
    }
  }

  Future<bool> validateInstallation() async {
    if (!_isInitialized) {
      print('❌ ExecutableManager не инициализирован');
      return false;
    }

    print('🔍 Проверка установки исполняемых файлов...');

    // Простая проверка существования файлов
    if (!await File(waifu2xPath).exists()) {
      print('❌ waifu2x не найден');
      return false;
    }

    if (!await File(ffmpegPath).exists()) {
      print('❌ FFmpeg не найден');
      return false;
    }

    if (!await _validateModelFiles()) {
      print('❌ Файлы модели не найдены');
      return false;
    }

    print('✅ Все файлы найдены и готовы к использованию');
    return true;
  }

  // Упрощенная валидация без детального анализа размеров
  Future<bool> _validateModelFiles() async {
    final modelPath = getModelPath('cunet');

    if (!await Directory(modelPath).exists()) {
      return false;
    }

    final modelFiles = await Directory(modelPath)
        .list()
        .where((entity) =>
            entity is File &&
            (entity.path.endsWith('.bin') || entity.path.endsWith('.param')))
        .cast<File>()
        .toList();

    return modelFiles.isNotEmpty;
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

  Future<void> cleanupExecutables() async {
    if (executablesDir != null && await executablesDir!.exists()) {
      await executablesDir!.delete(recursive: true);
      _isInitialized = false;
      print('Очистка исполняемых файлов завершена');
    }
  }

  void _checkInitialization() {
    if (executablesDir == null || !_isInitialized) {
      throw Exception(
          'ExecutableManager не инициализирован! Вызовите initializeExecutables() сначала.');
    }
  }
}
