import 'dart:io';
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

  Directory? executablesDir;
  bool _isInitialized = false;
  bool _useSystemFFmpeg = false;

  bool get isInitialized => _isInitialized;

  String get _platformDir {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    return 'linux';
  }

  String get _executableExtension => Platform.isWindows ? '.exe' : '';

  String get waifu2xPath {
    _checkInitialization();
    return path.join(
        executablesDir!.path, 'waifu2x-ncnn-vulkan$_executableExtension');
  }

  String get ffmpegPath {
    _checkInitialization();

    // Если используем системный FFmpeg
    if (_useSystemFFmpeg && (Platform.isMacOS || Platform.isLinux)) {
      return _getSystemFFmpegPath();
    }

    return path.join(executablesDir!.path, 'ffmpeg$_executableExtension');
  }

  String get ffprobePath {
    _checkInitialization();
    return path.join(executablesDir!.path, 'ffprobe$_executableExtension');
  }

  String get modelsDir {
    _checkInitialization();
    return executablesDir!.path;
  }

  String getModelPath(String modelType) {
    _checkInitialization();

    final modelFolders = {
      'cunet': 'models-cunet',
      'anime': 'models-upconv_7_anime_style_art_rgb',
      'photo': 'models-upconv_7_photo',
    };

    final modelFolder = modelFolders[modelType] ?? 'models-cunet';
    return path.join(executablesDir!.path, modelFolder);
  }

  // Поиск системного FFmpeg
  String _getSystemFFmpegPath() {
    final systemPaths = [
      '/opt/homebrew/bin/ffmpeg', // Homebrew ARM (M1/M2)
      '/usr/local/bin/ffmpeg', // Homebrew Intel
      '/usr/bin/ffmpeg', // Системный
    ];

    for (final systemPath in systemPaths) {
      if (File(systemPath).existsSync()) {
        return systemPath;
      }
    }

    // Fallback на локальный если системный не найден
    return path.join(executablesDir!.path, 'ffmpeg$_executableExtension');
  }

  Future<int> getInstallationSizeBytes() async {
    if (!_isInitialized || executablesDir == null) return 0;

    try {
      int totalSize = 0;
      await for (final entity in executablesDir!.list(recursive: true)) {
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

    try {
      await _setupExecutablesDirectory();
      await _extractExecutablesFromAssets();

      // ИСПРАВЛЕНО: устанавливаем флаг ДО установки прав
      _isInitialized = true;

      await _makeExecutablesExecutable();

      // Проверяем что все работает и решаем использовать ли системный FFmpeg
      await _validateAndConfigureExecutables();

      print('✅ ExecutableManager успешно инициализирован');
    } catch (e) {
      print('❌ Ошибка инициализации ExecutableManager: $e');
      _isInitialized = false;
      rethrow;
    }
  }

  Future<void> _setupExecutablesDirectory() async {
    final tempDir = await getTemporaryDirectory();
    executablesDir =
        Directory(path.join(tempDir.path, 'video_upscaler_executables'));

    if (!await executablesDir!.exists()) {
      await executablesDir!.create(recursive: true);
    }

    print('📁 Рабочая директория: ${executablesDir!.path}');
  }

  Future<void> _extractExecutablesFromAssets() async {
    print('📥 Извлечение исполняемых файлов из assets для $_platformDir...');

    final executableFiles = _getExecutableFilesForPlatform();

    for (final executable in executableFiles) {
      await _extractExecutableFromAssets(executable);
    }

    await _extractModelsFromAssets();
  }

  List<String> _getExecutableFilesForPlatform() {
    switch (_platformDir) {
      case 'windows':
        return ['ffmpeg.exe', 'ffprobe.exe', 'waifu2x-ncnn-vulkan.exe'];
      case 'linux':
        return ['ffmpeg', 'ffprobe', 'waifu2x-ncnn-vulkan'];
      case 'macos':
        return ['ffmpeg', 'waifu2x-ncnn-vulkan'];
      default:
        return [];
    }
  }

  Future<void> _extractExecutableFromAssets(String fileName) async {
    try {
      final assetPath = 'assets/executables/$_platformDir/$fileName';
      final targetPath = path.join(executablesDir!.path, fileName);

      print('📦 Извлечение $fileName...');

      final targetFile = File(targetPath);
      if (await targetFile.exists()) {
        try {
          final assetData = await rootBundle.load(assetPath);
          final existingSize = await targetFile.length();

          if (existingSize == assetData.lengthInBytes) {
            final sizeMB = (existingSize / 1024 / 1024).toStringAsFixed(1);
            print('✅ $fileName уже извлечен ($sizeMB MB)');
            return;
          }
        } catch (e) {
          print('⚠️ Проблема при проверке $fileName: $e');
        }
      }

      final byteData = await rootBundle.load(assetPath);
      final bytes = byteData.buffer.asUint8List();

      await targetFile.writeAsBytes(bytes);

      final sizeMB = (bytes.length / 1024 / 1024).toStringAsFixed(1);
      print('✅ $fileName извлечен: $sizeMB MB');
    } catch (e) {
      print('❌ Ошибка извлечения $fileName: $e');
      throw Exception('Не удалось извлечь $fileName: $e');
    }
  }

  Future<void> _extractModelsFromAssets() async {
    print('📥 Извлечение моделей ИИ...');

    final modelDirs = [
      'models-cunet',
      'models-upconv_7_anime_style_art_rgb',
      'models-upconv_7_photo'
    ];

    for (final modelDir in modelDirs) {
      await _extractModelDirectory(modelDir);
    }
  }

  Future<void> _extractModelDirectory(String modelDirName) async {
    try {
      final targetDir =
          Directory(path.join(executablesDir!.path, modelDirName));
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final modelAssets = assetManifest
          .listAssets()
          .where((key) =>
              key.startsWith('assets/executables/$_platformDir/$modelDirName/'))
          .toList();

      print(
          '📁 Извлечение $modelDirName: найдено ${modelAssets.length} файлов');

      for (final assetKey in modelAssets) {
        await _extractModelFile(assetKey, modelDirName);
      }
    } catch (e) {
      print('❌ Ошибка извлечения модели $modelDirName: $e');
    }
  }

  Future<void> _extractModelFile(String assetKey, String modelDirName) async {
    try {
      final fileName = path.basename(assetKey);
      final targetPath =
          path.join(executablesDir!.path, modelDirName, fileName);
      final targetFile = File(targetPath);

      if (await targetFile.exists()) {
        final assetData = await rootBundle.load(assetKey);
        final existingSize = await targetFile.length();

        if (existingSize == assetData.lengthInBytes) {
          return;
        }
      }

      final byteData = await rootBundle.load(assetKey);
      final bytes = byteData.buffer.asUint8List();

      await targetFile.writeAsBytes(bytes);
    } catch (e) {
      print('  ❌ Ошибка извлечения файла модели $assetKey: $e');
    }
  }

  // ИСПРАВЛЕННЫЙ метод установки прав с решением macOS quarantine
  Future<void> _makeExecutablesExecutable() async {
    if (Platform.isWindows) {
      print('ℹ️ Windows: права доступа устанавливаются автоматически');
      return;
    }

    try {
      print('🔧 Установка прав на выполнение...');

      final executables = [
        path.join(
            executablesDir!.path, 'waifu2x-ncnn-vulkan$_executableExtension'),
        path.join(executablesDir!.path, 'ffmpeg$_executableExtension'),
      ];

      if (Platform.isLinux) {
        executables.add(
            path.join(executablesDir!.path, 'ffprobe$_executableExtension'));
      }

      for (final execPath in executables) {
        if (await File(execPath).exists()) {
          await _fixExecutablePermissions(execPath);
        }
      }
    } catch (e) {
      print('❌ Ошибка при установке прав доступа: $e');
    }
  }

  // НОВЫЙ МЕТОД: Агрессивное исправление прав для macOS
  Future<void> _fixExecutablePermissions(String execPath) async {
    final fileName = path.basename(execPath);

    try {
      print('🔧 Исправление прав для $fileName...');

      if (Platform.isMacOS) {
        // 1. Убираем ALL extended attributes (включая quarantine)
        await Process.run('xattr', ['-c', execPath]).catchError(
            (e) => ProcessResult(0, 0, '', 'не удалось очистить атрибуты'));

        // 2. Убираем quarantine специально (если остался)
        await Process.run('xattr', ['-d', 'com.apple.quarantine', execPath])
            .catchError(
                (e) => ProcessResult(0, 0, '', 'quarantine уже удален'));

        print('✅ Extended attributes очищены для $fileName');
      }

      // 3. Устанавливаем права 755 (rwxr-xr-x)
      var result = await Process.run('chmod', ['755', execPath]);
      if (result.exitCode == 0) {
        print('✅ Права 755 установлены для $fileName');
      } else {
        print('⚠️ Ошибка chmod для $fileName: ${result.stderr}');
      }

      // 4. Дополнительная установка owner права
      await Process.run('chmod', ['u+x', execPath]);

      // 5. Проверяем результат
      result = await Process.run('ls', ['-la', execPath]);
      print('📋 Права для $fileName: ${result.stdout.toString().trim()}');
    } catch (e) {
      print('❌ Ошибка исправления прав для $fileName: $e');
    }
  }

  // НОВЫЙ МЕТОД: Проверка и настройка исполняемых файлов
  Future<void> _validateAndConfigureExecutables() async {
    print('🔍 Проверка исполняемых файлов...');

    // Проверяем FFmpeg
    final localFFmpegPath =
        path.join(executablesDir!.path, 'ffmpeg$_executableExtension');
    final ffmpegWorks = await _testExecutable(localFFmpegPath, ['-version']);

    if (!ffmpegWorks && (Platform.isMacOS || Platform.isLinux)) {
      print('⚠️ Локальный FFmpeg не работает, ищем системный...');

      final systemFFmpeg = _getSystemFFmpegPath();
      if (systemFFmpeg != localFFmpegPath) {
        final systemWorks = await _testExecutable(systemFFmpeg, ['-version']);
        if (systemWorks) {
          _useSystemFFmpeg = true;
          print('✅ Будет использоваться системный FFmpeg: $systemFFmpeg');
        } else {
          print('❌ Системный FFmpeg тоже не работает');
        }
      }
    } else if (ffmpegWorks) {
      print('✅ Локальный FFmpeg работает корректно');
    }

    // Проверяем waifu2x
    final waifu2xWorks = await _testExecutable(waifu2xPath, ['-h']);
    if (waifu2xWorks) {
      print('✅ waifu2x работает корректно');
    } else {
      print('❌ waifu2x не работает');
    }
  }

  // НОВЫЙ МЕТОД: Тест исполняемого файла
  Future<bool> _testExecutable(String execPath, List<String> args) async {
    try {
      if (!await File(execPath).exists()) {
        return false;
      }

      final result =
          await Process.run(execPath, args).timeout(Duration(seconds: 10));

      return result.exitCode == 0 ||
          result.exitCode == 1; // FFmpeg возвращает 1 при -version
    } catch (e) {
      print('❌ Ошибка тестирования ${path.basename(execPath)}: $e');
      return false;
    }
  }

  Future<bool> validateInstallation() async {
    if (!_isInitialized) {
      print('❌ ExecutableManager не инициализирован');
      return false;
    }

    print('🔍 Проверка установки исполняемых файлов...');

    // Проверяем основные исполняемые файлы
    final executables = [
      {'path': waifu2xPath, 'name': 'waifu2x'},
      {'path': ffmpegPath, 'name': 'FFmpeg'},
    ];

    if (Platform.isLinux && !_useSystemFFmpeg) {
      executables.add({'path': ffprobePath, 'name': 'FFprobe'});
    }

    bool allValid = true;

    for (final exec in executables) {
      final file = File(exec['path']!);
      if (!await file.exists()) {
        print('❌ ${exec['name']} не найден: ${exec['path']}');
        allValid = false;
        continue;
      }

      final size = await file.length();
      if (size < 1000) {
        print('❌ ${exec['name']} слишком мал: ${size} bytes');
        allValid = false;
        continue;
      }

      print('✅ ${exec['name']}: ${(size / 1024 / 1024).toStringAsFixed(1)} MB');
    }

    // Проверяем модели
    if (!await _validateModelFiles()) {
      print('❌ Файлы модели не найдены');
      allValid = false;
    }

    // Функциональный тест FFmpeg
    if (!await _testExecutable(ffmpegPath, ['-version'])) {
      print('❌ FFmpeg не может быть запущен');
      allValid = false;
    } else {
      print('✅ FFmpeg функциональный тест пройден');
    }

    if (allValid) {
      print('✅ Все файлы найдены и готовы к использованию');
    } else {
      print('❌ Обнаружены проблемы с установкой');
    }

    return allValid;
  }

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

  Future<void> cleanupExecutables() async {
    if (executablesDir != null && await executablesDir!.exists()) {
      await executablesDir!.delete(recursive: true);
      _isInitialized = false;
      _useSystemFFmpeg = false;
      print('Очистка исполняемых файлов завершена');
    }
  }

  void _checkInitialization() {
    if (executablesDir == null || !_isInitialized) {
      throw Exception(
          'ExecutableManager не инициализирован! Вызовите initializeExecutables() сначала.');
    }
  }

  // Публичный метод для получения информации о конфигурации
  Map<String, dynamic> getConfigurationInfo() {
    return {
      'isInitialized': _isInitialized,
      'useSystemFFmpeg': _useSystemFFmpeg,
      'executablesDir': executablesDir?.path,
      'platform': _platformDir,
      'ffmpegPath': _isInitialized ? ffmpegPath : null,
      'waifu2xPath': _isInitialized ? waifu2xPath : null,
    };
  }
}
