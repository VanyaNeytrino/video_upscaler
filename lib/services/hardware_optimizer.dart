import 'dart:io';
import 'package:video_upscaler/models/processing_config.dart';

class HardwareOptimizer {
  static HardwareOptimizer? _instance;
  static HardwareOptimizer get instance => _instance ??= HardwareOptimizer._();

  HardwareOptimizer._();

  /// Анализирует железо и создает оптимальные технические параметры
  OptimizedConfig optimizeForHardware({
    required ProcessingConfig userConfig,
    required Map<String, dynamic> systemInfo,
    required Map<String, dynamic> videoInfo,
  }) {
    final hardware = _analyzeHardware(systemInfo);
    final videoParams = _analyzeVideo(videoInfo, userConfig.scaleFactor);

    return OptimizedConfig(
      userConfig: userConfig,
      waifu2xParams: _optimizeWaifu2x(hardware, userConfig),
      ffmpegParams: _optimizeFFmpeg(hardware, videoParams, userConfig),
      systemParams: _optimizeSystem(hardware, videoParams),
    );
  }

  /// Анализ железа пользователя
  HardwareProfile _analyzeHardware(Map<String, dynamic> systemInfo) {
    final platform = systemInfo['platform'] as String? ?? 'unknown';
    final cpuCores = systemInfo['cpu_cores'] as int? ?? 4;
    final memoryGB =
        (systemInfo['memory_info'] as Map?)?.getValue('total_gb') ?? 8;
    final hasVulkan = systemInfo['has_vulkan'] as bool? ?? false;
    final gpuList = systemInfo['available_gpus'] as List? ?? [];
    final cpuInfo = systemInfo['cpu_info'] as Map? ?? {};

    // Определяем тип железа
    HardwareType hardwareType = _detectHardwareType(platform, cpuInfo, gpuList);

    return HardwareProfile(
      type: hardwareType,
      platform: platform,
      cpuCores: cpuCores,
      memoryGB: memoryGB,
      hasVulkan: hasVulkan,
      gpuDevices: gpuList.cast<String>(),
      cpuName: cpuInfo['name']?.toString() ?? 'Unknown',
      architecture: cpuInfo['architecture']?.toString() ?? 'Unknown',
    );
  }

  /// Определение типа железа
  HardwareType _detectHardwareType(String platform, Map cpuInfo, List gpuList) {
    final cpuName = cpuInfo['name']?.toString().toLowerCase() ?? '';
    final hasHighEndGPU = gpuList.any((gpu) =>
        gpu.toString().toLowerCase().contains('rtx') ||
        gpu.toString().toLowerCase().contains('rx 6') ||
        gpu.toString().toLowerCase().contains('rx 7'));

    if (platform == 'macos') {
      if (cpuName.contains('m1') ||
          cpuName.contains('m2') ||
          cpuName.contains('m3')) {
        return HardwareType.appleSilicon;
      }
      return HardwareType.macIntel;
    }

    if (hasHighEndGPU) {
      return HardwareType.gamingPC;
    }

    if (cpuName.contains('i7') ||
        cpuName.contains('i9') ||
        cpuName.contains('ryzen 7') ||
        cpuName.contains('ryzen 9')) {
      return HardwareType.highEndPC;
    }

    return HardwareType.standardPC;
  }

  /// Оптимизация параметров waifu2x
  Waifu2xParams _optimizeWaifu2x(
      HardwareProfile hardware, ProcessingConfig userConfig) {
    switch (hardware.type) {
      case HardwareType.appleSilicon:
        return _optimizeForAppleSilicon(hardware, userConfig);
      case HardwareType.gamingPC:
        return _optimizeForGamingPC(hardware, userConfig);
      case HardwareType.highEndPC:
        return _optimizeForHighEndPC(hardware, userConfig);
      case HardwareType.macIntel:
        return _optimizeForMacIntel(hardware, userConfig);
      case HardwareType.standardPC:
        return _optimizeForStandardPC(hardware, userConfig);
    }
  }

  /// Оптимизация для Apple Silicon (M1, M2, M3)
  Waifu2xParams _optimizeForAppleSilicon(
      HardwareProfile hardware, ProcessingConfig userConfig) {
    // Apple Silicon: консервативные настройки, GPU предпочтителен
    int tileSize;
    int gpuDevice = 0; // Всегда используем встроенную графику
    int loadThreads = 1;
    int procThreads = 2;
    int saveThreads = 1;

    // Tile size зависит от scale factor и памяти
    switch (userConfig.scaleFactor) {
      case 4:
        tileSize =
            hardware.memoryGB >= 16 ? 64 : 32; // Очень консервативно для 4x
        procThreads = 1; // Один поток для 4x
        break;
      case 2:
        tileSize = hardware.memoryGB >= 16 ? 128 : 64;
        procThreads = 2;
        break;
      default:
        tileSize = 200;
        procThreads = 2;
    }

    return Waifu2xParams(
      tileSize: tileSize,
      gpuDevice: gpuDevice,
      loadThreads: loadThreads,
      procThreads: procThreads,
      saveThreads: saveThreads,
      useGPU: true,
      enableTTA: false, // Отключаем для скорости
    );
  }

  /// Оптимизация для Gaming PC (RTX/RX серии)
  Waifu2xParams _optimizeForGamingPC(
      HardwareProfile hardware, ProcessingConfig userConfig) {
    // Gaming PC: агрессивные настройки, используем мощную GPU
    int tileSize;
    int gpuDevice = 0;
    int loadThreads = 2;
    int procThreads = 4;
    int saveThreads = 2;

    // Агрессивные настройки для мощного GPU
    switch (userConfig.scaleFactor) {
      case 4:
        tileSize = hardware.memoryGB >= 16 ? 256 : 128;
        procThreads = 6;
        break;
      case 2:
        tileSize = hardware.memoryGB >= 16 ? 512 : 256;
        procThreads = 8;
        break;
      default:
        tileSize = 512;
        procThreads = 4;
    }

    return Waifu2xParams(
      tileSize: tileSize,
      gpuDevice: gpuDevice,
      loadThreads: loadThreads,
      procThreads: procThreads,
      saveThreads: saveThreads,
      useGPU: true,
      enableTTA: userConfig.scaleFactor <= 2, // TTA только для 2x и ниже
    );
  }

  /// Оптимизация для High-End PC (без топового GPU)
  Waifu2xParams _optimizeForHighEndPC(
      HardwareProfile hardware, ProcessingConfig userConfig) {
    int tileSize;
    int gpuDevice = hardware.hasVulkan ? 0 : -1;
    int loadThreads = 2;
    int procThreads = hardware.cpuCores.clamp(2, 6);
    int saveThreads = 2;

    if (hardware.hasVulkan) {
      // Умеренные настройки для GPU
      switch (userConfig.scaleFactor) {
        case 4:
          tileSize = 128;
          procThreads = 4;
          break;
        case 2:
          tileSize = 256;
          procThreads = 6;
          break;
        default:
          tileSize = 400;
          procThreads = 4;
      }
    } else {
      // CPU fallback
      tileSize = userConfig.scaleFactor >= 4 ? 64 : 128;
      procThreads = hardware.cpuCores.clamp(4, 8);
    }

    return Waifu2xParams(
      tileSize: tileSize,
      gpuDevice: gpuDevice,
      loadThreads: loadThreads,
      procThreads: procThreads,
      saveThreads: saveThreads,
      useGPU: hardware.hasVulkan,
      enableTTA: false,
    );
  }

  /// Оптимизация для Mac Intel
  Waifu2xParams _optimizeForMacIntel(
      HardwareProfile hardware, ProcessingConfig userConfig) {
    // Mac Intel: средние настройки, GPU может быть слабым
    int tileSize = userConfig.scaleFactor >= 4 ? 64 : 128;
    int gpuDevice = hardware.hasVulkan ? 0 : -1;
    int procThreads = hardware.cpuCores.clamp(2, 4);

    return Waifu2xParams(
      tileSize: tileSize,
      gpuDevice: gpuDevice,
      loadThreads: 1,
      procThreads: procThreads,
      saveThreads: 1,
      useGPU: hardware.hasVulkan,
      enableTTA: false,
    );
  }

  /// Оптимизация для Standard PC
  Waifu2xParams _optimizeForStandardPC(
      HardwareProfile hardware, ProcessingConfig userConfig) {
    // Standard PC: консервативные настройки
    int tileSize = userConfig.scaleFactor >= 4 ? 32 : 64;
    int gpuDevice = hardware.hasVulkan ? 0 : -1;
    int procThreads = hardware.cpuCores.clamp(1, 4);

    return Waifu2xParams(
      tileSize: tileSize,
      gpuDevice: gpuDevice,
      loadThreads: 1,
      procThreads: procThreads,
      saveThreads: 1,
      useGPU: hardware.hasVulkan && hardware.memoryGB >= 8,
      enableTTA: false,
    );
  }

  /// Анализ видео параметров
  VideoAnalysis _analyzeVideo(Map<String, dynamic> videoInfo, int scaleFactor) {
    final width = videoInfo['width'] as int? ?? 1920;
    final height = videoInfo['height'] as int? ?? 1080;
    final fps = videoInfo['fps'] as double? ?? 30.0;
    final bitrate = videoInfo['bitrate'] as int? ?? 5000;

    final outputWidth = width * scaleFactor;
    final outputHeight = height * scaleFactor;
    final totalPixels = outputWidth * outputHeight;

    return VideoAnalysis(
      inputWidth: width,
      inputHeight: height,
      outputWidth: outputWidth,
      outputHeight: outputHeight,
      totalPixels: totalPixels,
      fps: fps,
      originalBitrate: bitrate,
    );
  }

  /// Оптимизация параметров FFmpeg
  FFmpegParams _optimizeFFmpeg(HardwareProfile hardware, VideoAnalysis video,
      ProcessingConfig userConfig) {
    // Выбор кодека на основе разрешения и железа
    String videoCodec = _selectOptimalCodec(hardware, video);
    String preset = _selectOptimalPreset(hardware, video);
    int crf = _selectOptimalCRF(video, userConfig.scaleFactor);
    String pixFormat = _selectOptimalPixFormat(video);
    int bitrate = _calculateOptimalBitrate(video, userConfig.scaleFactor);

    return FFmpegParams(
      videoCodec: videoCodec,
      preset: preset,
      crf: crf,
      pixFormat: pixFormat,
      bitrate: '${bitrate}k',
      maxrate: '${(bitrate * 1.5).round()}k',
      bufsize: '${(bitrate * 2).round()}k',
      fps: video.fps.round(),
    );
  }

  String _selectOptimalCodec(HardwareProfile hardware, VideoAnalysis video) {
    // 4K и выше - предпочитаем H.265
    if (video.totalPixels >= 3840 * 2160) {
      if (hardware.type == HardwareType.gamingPC ||
          hardware.type == HardwareType.highEndPC) {
        return 'libx265'; // Мощное железо справится с H.265
      }
    }

    // Для Apple Silicon всегда H.264 (лучшая совместимость)
    if (hardware.type == HardwareType.appleSilicon) {
      return 'libx264';
    }

    return 'libx264'; // По умолчанию
  }

  String _selectOptimalPreset(HardwareProfile hardware, VideoAnalysis video) {
    switch (hardware.type) {
      case HardwareType.gamingPC:
        return 'slow'; // Максимальное качество
      case HardwareType.highEndPC:
        return 'medium';
      case HardwareType.appleSilicon:
        return video.totalPixels >= 2560 * 1440 ? 'medium' : 'fast';
      default:
        return 'fast';
    }
  }

  int _selectOptimalCRF(VideoAnalysis video, int scaleFactor) {
    // Чем больше scale, тем лучше качество нужно
    if (scaleFactor >= 4) {
      return video.totalPixels >= 3840 * 2160
          ? 16
          : 18; // Очень высокое качество для 4x
    } else if (scaleFactor >= 2) {
      return video.totalPixels >= 3840 * 2160 ? 18 : 20;
    } else {
      return 23; // Стандартное качество для 1x
    }
  }

  String _selectOptimalPixFormat(VideoAnalysis video) {
    // 4K и выше - 10 bit для лучшего качества
    if (video.totalPixels >= 3840 * 2160) {
      return 'yuv420p10le';
    }
    return 'yuv420p';
  }

  int _calculateOptimalBitrate(VideoAnalysis video, int scaleFactor) {
    final pixelsPerSecond = video.totalPixels * video.fps;

    // Базовый битрейт на пиксель (в битах)
    double bitsPerPixel = 0.1;

    // Коррекция для высоких разрешений
    if (video.totalPixels >= 3840 * 2160) {
      bitsPerPixel = 0.08; // 4K - более эффективное сжатие
    } else if (video.totalPixels >= 2560 * 1440) {
      bitsPerPixel = 0.09; // 1440p
    }

    // Коррекция для scale factor
    if (scaleFactor >= 4) {
      bitsPerPixel *= 1.3; // Больше битрейта для 4x
    }

    final bitrateKbps = (pixelsPerSecond * bitsPerPixel / 1000).round();
    return bitrateKbps.clamp(1000, 50000); // Ограничения: 1-50 Mbps
  }

  /// Системные параметры
  SystemParams _optimizeSystem(HardwareProfile hardware, VideoAnalysis video) {
    int bufferSize = _calculateBufferSize(hardware);
    int concurrentTasks = _calculateConcurrentTasks(hardware);
    bool useHardwareAccel = _shouldUseHardwareAccel(hardware);

    return SystemParams(
      bufferSizeMB: bufferSize,
      concurrentTasks: concurrentTasks,
      useHardwareAccel: useHardwareAccel,
      tempDirStrategy: _getTempDirStrategy(hardware),
    );
  }

  int _calculateBufferSize(HardwareProfile hardware) {
    final memoryGB = hardware.memoryGB;
    if (memoryGB >= 32) return 1024; // 1GB буфер
    if (memoryGB >= 16) return 512; // 512MB буфер
    if (memoryGB >= 8) return 256; // 256MB буфер
    return 128; // 128MB буфер
  }

  int _calculateConcurrentTasks(HardwareProfile hardware) {
    switch (hardware.type) {
      case HardwareType.gamingPC:
        return 3; // Можем параллельно: извлечение, обработка, сборка
      case HardwareType.highEndPC:
        return 2;
      default:
        return 1; // Последовательная обработка
    }
  }

  bool _shouldUseHardwareAccel(HardwareProfile hardware) {
    return hardware.type == HardwareType.gamingPC ||
        hardware.type == HardwareType.appleSilicon;
  }

  String _getTempDirStrategy(HardwareProfile hardware) {
    // SSD vs HDD, RAM disk для быстрого железа
    switch (hardware.type) {
      case HardwareType.gamingPC:
      case HardwareType.appleSilicon:
        return 'ramdisk'; // Попытка использовать RAM для временных файлов
      default:
        return 'temp'; // Стандартная временная папка
    }
  }
}

/// Типы железа
enum HardwareType {
  appleSilicon, // M1, M2, M3 MacBook/iMac
  gamingPC, // RTX/RX + мощный CPU
  highEndPC, // Мощный CPU, слабая/средняя GPU
  macIntel, // Intel Mac
  standardPC, // Обычный ПК
}

/// Профиль железа
class HardwareProfile {
  final HardwareType type;
  final String platform;
  final int cpuCores;
  final int memoryGB;
  final bool hasVulkan;
  final List<String> gpuDevices;
  final String cpuName;
  final String architecture;

  HardwareProfile({
    required this.type,
    required this.platform,
    required this.cpuCores,
    required this.memoryGB,
    required this.hasVulkan,
    required this.gpuDevices,
    required this.cpuName,
    required this.architecture,
  });

  @override
  String toString() {
    return 'HardwareProfile(type: $type, cpu: $cpuName, cores: $cpuCores, ram: ${memoryGB}GB, gpu: ${gpuDevices.length})';
  }
}

/// Анализ видео
class VideoAnalysis {
  final int inputWidth;
  final int inputHeight;
  final int outputWidth;
  final int outputHeight;
  final int totalPixels;
  final double fps;
  final int originalBitrate;

  VideoAnalysis({
    required this.inputWidth,
    required this.inputHeight,
    required this.outputWidth,
    required this.outputHeight,
    required this.totalPixels,
    required this.fps,
    required this.originalBitrate,
  });
}

/// Оптимизированные параметры waifu2x
class Waifu2xParams {
  final int tileSize;
  final int gpuDevice;
  final int loadThreads;
  final int procThreads;
  final int saveThreads;
  final bool useGPU;
  final bool enableTTA;

  Waifu2xParams({
    required this.tileSize,
    required this.gpuDevice,
    required this.loadThreads,
    required this.procThreads,
    required this.saveThreads,
    required this.useGPU,
    required this.enableTTA,
  });

  List<String> toWaifu2xArgs(String inputPath, String outputPath,
      String modelPath, ProcessingConfig userConfig) {
    final args = <String>[];

    args.addAll(['-i', inputPath, '-o', outputPath]);
    args.addAll(['-n', userConfig.scaleNoise.toString()]);
    args.addAll(['-s', userConfig.scaleFactor.toString()]);
    args.addAll(['-m', modelPath]);
    args.addAll(['-g', gpuDevice.toString()]);
    args.addAll(['-t', tileSize.toString()]);
    args.addAll(['-j', '$loadThreads:$procThreads:$saveThreads']);

    if (enableTTA) {
      args.add('-x');
    }

    args.addAll(['-f', 'png']);
    args.add('-v');

    return args;
  }
}

/// Оптимизированные параметры FFmpeg
class FFmpegParams {
  final String videoCodec;
  final String preset;
  final int crf;
  final String pixFormat;
  final String bitrate;
  final String maxrate;
  final String bufsize;
  final int fps;

  FFmpegParams({
    required this.videoCodec,
    required this.preset,
    required this.crf,
    required this.pixFormat,
    required this.bitrate,
    required this.maxrate,
    required this.bufsize,
    required this.fps,
  });
}

/// Системные параметры
class SystemParams {
  final int bufferSizeMB;
  final int concurrentTasks;
  final bool useHardwareAccel;
  final String tempDirStrategy;

  SystemParams({
    required this.bufferSizeMB,
    required this.concurrentTasks,
    required this.useHardwareAccel,
    required this.tempDirStrategy,
  });
}

/// Полная оптимизированная конфигурация
class OptimizedConfig {
  final ProcessingConfig userConfig;
  final Waifu2xParams waifu2xParams;
  final FFmpegParams ffmpegParams;
  final SystemParams systemParams;

  OptimizedConfig({
    required this.userConfig,
    required this.waifu2xParams,
    required this.ffmpegParams,
    required this.systemParams,
  });

  @override
  String toString() {
    return '''
OptimizedConfig:
  User: scale=${userConfig.scaleFactor}x, noise=${userConfig.scaleNoise}, model=${userConfig.modelType}
  Waifu2x: tile=${waifu2xParams.tileSize}, gpu=${waifu2xParams.gpuDevice}, threads=${waifu2xParams.loadThreads}:${waifu2xParams.procThreads}:${waifu2xParams.saveThreads}
  FFmpeg: codec=${ffmpegParams.videoCodec}, crf=${ffmpegParams.crf}, bitrate=${ffmpegParams.bitrate}
  System: buffer=${systemParams.bufferSizeMB}MB, tasks=${systemParams.concurrentTasks}
''';
  }
}

// Добавить extension для Map
extension MapExtensions on Map {
  T? getValue<T>(String key) {
    final value = this[key];
    return value is T ? value : null;
  }
}
