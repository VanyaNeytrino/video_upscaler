import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart'
    as http; // ДОБАВЬТЕ В pubspec.yaml: http: ^1.1.0

class ExecutableManager {
  late Directory executablesDir;

  String get waifu2xPath {
    if (Platform.isMacOS) {
      return path.join(executablesDir.path, 'macos', 'waifu2x-ncnn-vulkan');
    } else if (Platform.isWindows) {
      return path.join(
          executablesDir.path, 'windows', 'waifu2x-ncnn-vulkan.exe');
    } else {
      return path.join(executablesDir.path, 'linux', 'waifu2x-ncnn-vulkan');
    }
  }

  String get ffmpegPath {
    if (Platform.isMacOS) {
      return path.join(executablesDir.path, 'macos', 'ffmpeg');
    } else if (Platform.isWindows) {
      return path.join(executablesDir.path, 'windows', 'ffmpeg.exe');
    } else {
      return path.join(executablesDir.path, 'linux', 'ffmpeg');
    }
  }

  String getModelPath(String modelType) {
    final platformDir = Platform.isMacOS
        ? 'macos'
        : Platform.isWindows
            ? 'windows'
            : 'linux';

    switch (modelType) {
      case 'cunet':
        return path.join(executablesDir.path, platformDir, 'models-cunet');
      case 'anime':
        return path.join(executablesDir.path, platformDir,
            'models-upconv_7_anime_style_art_rgb');
      case 'photo':
        return path.join(
            executablesDir.path, platformDir, 'models-upconv_7_photo');
      default:
        return path.join(executablesDir.path, platformDir, 'models-cunet');
    }
  }

  Future<void> initializeExecutables() async {
    await _setupExecutablesDirectory();

    // НОВОЕ: сначала скачиваем реальные файлы модели
    await _downloadRealModelFiles();

    await _extractExecutablesFromAssets();
    await _makeExecutablesExecutable();

    print('Все файлы успешно извлечены');
  }

  Future<void> _setupExecutablesDirectory() async {
    final appSupportDir = await _getApplicationSupportDirectory();
    executablesDir = Directory(path.join(appSupportDir.path, 'executables'));

    if (!await executablesDir.exists()) {
      await executablesDir.create(recursive: true);
    }
  }

  // НОВЫЙ МЕТОД: Скачивание настоящих файлов модели
  Future<void> _downloadRealModelFiles() async {
    print(
        '📥 Скачиваем настоящие файлы модели из оригинального репозитория...');

    final platformDir = Platform.isMacOS
        ? 'macos'
        : Platform.isWindows
            ? 'windows'
            : 'linux';

    // URLs файлов модели из оригинального репозитория waifu2x-ncnn-vulkan
    final modelUrls = {
      // CUNet модель - основная
      'models-cunet/noise0_scale2.0x_model.bin':
          'https://github.com/nihui/waifu2x-ncnn-vulkan/raw/master/models-cunet/noise0_scale2.0x_model.bin',
      'models-cunet/noise0_scale2.0x_model.param':
          'https://github.com/nihui/waifu2x-ncnn-vulkan/raw/master/models-cunet/noise0_scale2.0x_model.param',
      'models-cunet/noise1_scale2.0x_model.bin':
          'https://github.com/nihui/waifu2x-ncnn-vulkan/raw/master/models-cunet/noise1_scale2.0x_model.bin',
      'models-cunet/noise1_scale2.0x_model.param':
          'https://github.com/nihui/waifu2x-ncnn-vulkan/raw/master/models-cunet/noise1_scale2.0x_model.param',
      'models-cunet/noise2_scale2.0x_model.bin':
          'https://github.com/nihui/waifu2x-ncnn-vulkan/raw/master/models-cunet/noise2_scale2.0x_model.bin',
      'models-cunet/noise2_scale2.0x_model.param':
          'https://github.com/nihui/waifu2x-ncnn-vulkan/raw/master/models-cunet/noise2_scale2.0x_model.param',
      'models-cunet/noise3_scale2.0x_model.bin':
          'https://github.com/nihui/waifu2x-ncnn-vulkan/raw/master/models-cunet/noise3_scale2.0x_model.bin',
      'models-cunet/noise3_scale2.0x_model.param':
          'https://github.com/nihui/waifu2x-ncnn-vulkan/raw/master/models-cunet/noise3_scale2.0x_model.param',

      // Только noise файлы
      'models-cunet/noise0_model.bin':
          'https://github.com/nihui/waifu2x-ncnn-vulkan/raw/master/models-cunet/noise0_model.bin',
      'models-cunet/noise0_model.param':
          'https://github.com/nihui/waifu2x-ncnn-vulkan/raw/master/models-cunet/noise0_model.param',
      'models-cunet/noise1_model.bin':
          'https://github.com/nihui/waifu2x-ncnn-vulkan/raw/master/models-cunet/noise1_model.bin',
      'models-cunet/noise1_model.param':
          'https://github.com/nihui/waifu2x-ncnn-vulkan/raw/master/models-cunet/noise1_model.param',
      'models-cunet/noise2_model.bin':
          'https://github.com/nihui/waifu2x-ncnn-vulkan/raw/master/models-cunet/noise2_model.bin',
      'models-cunet/noise2_model.param':
          'https://github.com/nihui/waifu2x-ncnn-vulkan/raw/master/models-cunet/noise2_model.param',
      'models-cunet/noise3_model.bin':
          'https://github.com/nihui/waifu2x-ncnn-vulkan/raw/master/models-cunet/noise3_model.bin',
      'models-cunet/noise3_model.param':
          'https://github.com/nihui/waifu2x-ncnn-vulkan/raw/master/models-cunet/noise3_model.param',

      // Scale файлы
      'models-cunet/scale2.0x_model.bin':
          'https://github.com/nihui/waifu2x-ncnn-vulkan/raw/master/models-cunet/scale2.0x_model.bin',
      'models-cunet/scale2.0x_model.param':
          'https://github.com/nihui/waifu2x-ncnn-vulkan/raw/master/models-cunet/scale2.0x_model.param',
    };

    final http.Client client = http.Client();

    for (final entry in modelUrls.entries) {
      final relativePath = entry.key;
      final url = entry.value;
      final localPath =
          path.join(executablesDir.path, platformDir, relativePath);

      // Создаем директорию если не существует
      final localDir = Directory(path.dirname(localPath));
      if (!await localDir.exists()) {
        await localDir.create(recursive: true);
      }

      // ПРОВЕРЯЕМ если файл уже существует и имеет правильный размер
      final file = File(localPath);
      if (await file.exists()) {
        final size = await file.length();
        if (size > 100 * 1024) {
          // Больше 100KB = нормальный файл
          print(
              '✅ ${path.basename(localPath)}: уже существует (${(size / 1024 / 1024).toStringAsFixed(1)} MB)');
          continue;
        } else {
          print(
              '🗑️ ${path.basename(localPath)}: удаляем поврежденный файл (${size} bytes)');
          await file.delete();
        }
      }

      print('📥 Скачиваем: ${path.basename(localPath)}');

      try {
        final response = await client.get(Uri.parse(url));

        if (response.statusCode == 200) {
          await file.writeAsBytes(response.bodyBytes);

          final size = response.bodyBytes.length;
          print(
              '✅ Скачан: ${path.basename(localPath)} (${(size / 1024 / 1024).toStringAsFixed(1)} MB)');

          // ПРОВЕРЯЕМ что файл действительно нормального размера
          if (size < 100 * 1024) {
            print(
                '⚠️ ВНИМАНИЕ: Файл слишком маленький: ${path.basename(localPath)} (${size} bytes)');
          }
        } else {
          print(
              '❌ Ошибка скачивания ${path.basename(localPath)}: HTTP ${response.statusCode}');
        }
      } catch (e) {
        print('❌ Ошибка скачивания ${path.basename(localPath)}: $e');
      }
    }

    client.close();
    print('✅ Скачивание файлов модели завершено');
  }

  Future<void> _extractExecutablesFromAssets() async {
    final platformDir = Platform.isMacOS
        ? 'macos'
        : Platform.isWindows
            ? 'windows'
            : 'linux';
    print('Извлечение файлов для платформы: $platformDir');

    final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assetKeys = assetManifest
        .listAssets()
        .where((key) => key.startsWith('assets/executables/$platformDir/'))
        .toList();

    print('Найдено ${assetKeys.length} файлов для извлечения');

    for (final assetKey in assetKeys) {
      // ПРОПУСКАЕМ файлы модели - они теперь скачиваются отдельно
      if (assetKey.contains('models-') &&
          (assetKey.endsWith('.bin') || assetKey.endsWith('.param'))) {
        print(
            'Пропускаем файл модели: ${path.basename(assetKey)} (скачивается отдельно)');
        continue;
      }

      final relativePath =
          assetKey.replaceFirst('assets/executables/$platformDir/', '');
      final targetPath =
          path.join(executablesDir.path, platformDir, relativePath);

      final targetDir = Directory(path.dirname(targetPath));
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final byteData = await rootBundle.load(assetKey);
      final bytes = byteData.buffer.asUint8List();

      await File(targetPath).writeAsBytes(bytes);
      print('Извлечен: $relativePath');
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
    print('🔍 Проверка установки исполняемых файлов...');

    if (!await File(waifu2xPath).exists()) {
      print('❌ waifu2x не найден');
      return false;
    }

    if (!await File(ffmpegPath).exists()) {
      print('❌ FFmpeg не найден');
      return false;
    }

    // НОВОЕ: проверяем размеры файлов модели
    if (!await _validateModelFiles()) {
      print('🚨 Обнаружены поврежденные файлы модели - переустанавливаем...');

      // ПЕРЕУСТАНАВЛИВАЕМ файлы модели
      await _downloadRealModelFiles();

      // Перепроверяем
      if (!await _validateModelFiles()) {
        print('❌ Не удалось восстановить файлы модели');
        return false;
      }
    }

    print('✅ Все файлы найдены и готовы к использованию');
    return true;
  }

  Future<bool> _validateModelFiles() async {
    print('🔍 ПРОВЕРКА РАЗМЕРОВ ФАЙЛОВ МОДЕЛИ');

    final modelTypes = ['cunet']; // Пока проверяем только основную модель
    bool allValid = true;

    for (final modelType in modelTypes) {
      final modelPath = getModelPath(modelType);

      if (!await Directory(modelPath).exists()) {
        print('❌ Директория модели не существует: $modelPath');
        allValid = false;
        continue;
      }

      final files = await Directory(modelPath)
          .list()
          .where((entity) =>
              entity is File &&
              (entity.path.endsWith('.bin') || entity.path.endsWith('.param')))
          .cast<File>()
          .toList();

      for (final file in files) {
        final size = await file.length();
        final name = path.basename(file.path);

        print('📄 $modelType/$name: ${(size / 1024).toStringAsFixed(1)} KB');

        // КРИТИЧЕСКАЯ ПРОВЕРКА: файлы модели должны быть больше 100KB
        if (size < 100 * 1024) {
          // Меньше 100KB = поврежден или LFS pointer
          print('🚨 ПОВРЕЖДЕННЫЙ ФАЙЛ: $name (${size} bytes)');
          allValid = false;

          // УДАЛЯЕМ поврежденный файл
          await file.delete();
          print('🗑️ Удален поврежденный файл: $name');
        }
      }
    }

    return allValid;
  }

  Future<Directory> _getApplicationSupportDirectory() async {
    // Реализация зависит от платформы
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
    if (await executablesDir.exists()) {
      await executablesDir.delete(recursive: true);
      print('Очистка исполняемых файлов завершена');
    }
  }
}
