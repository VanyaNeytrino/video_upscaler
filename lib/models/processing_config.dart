import 'dart:io'; // ДОБАВЛЯЕМ ИМПОРТ для File и Directory

class ProcessingConfig {
  final String inputVideoPath;
  final String outputPath;
  final int scaleNoise;
  final int scaleFactor;
  final int framerate;
  final String videoCodec;
  final String audioCodec;
  final String? modelType;

  ProcessingConfig({
    required this.inputVideoPath,
    required this.outputPath,
    int? scaleNoise,
    int? scaleFactor,
    int? framerate,
    String? videoCodec,
    String? audioCodec,
    String? modelType,
  })  :
        // ВАЛИДАЦИЯ ПАРАМЕТРОВ согласно документации waifu2x
        scaleNoise = _validateNoise(scaleNoise ?? 1),
        scaleFactor = _validateScale(scaleFactor ?? 2),
        framerate = _validateFramerate(framerate ?? 30),
        videoCodec = videoCodec ?? 'libx264',
        audioCodec = audioCodec ?? 'aac',
        modelType = _validateModelType(modelType);

  // ВАЛИДАЦИЯ scale factor - только 1, 2, 4 поддерживаются waifu2x
  static int _validateScale(int scale) {
    const validScales = [1, 2, 4];
    if (!validScales.contains(scale)) {
      print('⚠️ Неподдерживаемый scale factor: $scale. Доступны: $validScales');
      if (scale == 3) return 2; // 3x -> 2x
      if (scale > 4) return 4; // >4x -> 4x
      if (scale < 1) return 1; // <1x -> 1x
      return 2; // По умолчанию 2x
    }
    return scale;
  }

  // ВАЛИДАЦИЯ noise level - только -1, 0, 1, 2, 3
  static int _validateNoise(int noise) {
    const minNoise = -1;
    const maxNoise = 3;
    if (noise < minNoise || noise > maxNoise) {
      print(
          '⚠️ Неподдерживаемый noise level: $noise. Диапазон: $minNoise..$maxNoise');
      return noise.clamp(minNoise, maxNoise);
    }
    return noise;
  }

  // ВАЛИДАЦИЯ framerate
  static int _validateFramerate(int fps) {
    const minFps = 1;
    const maxFps = 120;
    if (fps < minFps || fps > maxFps) {
      print('⚠️ Неподдерживаемый FPS: $fps. Диапазон: $minFps..$maxFps');
      return fps.clamp(minFps, maxFps);
    }
    return fps;
  }

  // ВАЛИДАЦИЯ типа модели
  static String _validateModelType(String? modelType) {
    const validModels = ['cunet', 'anime', 'photo'];
    if (modelType == null || !validModels.contains(modelType)) {
      print(
          '⚠️ Неподдерживаемый тип модели: $modelType. Доступны: $validModels');
      return 'cunet'; // По умолчанию
    }
    return modelType;
  }

  ProcessingConfig copyWith({
    String? inputVideoPath,
    String? outputPath,
    int? scaleNoise,
    int? scaleFactor,
    int? framerate,
    String? videoCodec,
    String? audioCodec,
    String? modelType,
  }) {
    return ProcessingConfig(
      inputVideoPath: inputVideoPath ?? this.inputVideoPath,
      outputPath: outputPath ?? this.outputPath,
      scaleNoise: scaleNoise ?? this.scaleNoise,
      scaleFactor: scaleFactor ?? this.scaleFactor,
      framerate: framerate ?? this.framerate,
      videoCodec: videoCodec ?? this.videoCodec,
      audioCodec: audioCodec ?? this.audioCodec,
      modelType: modelType ?? this.modelType,
    );
  }

  // ДОПОЛНИТЕЛЬНЫЕ МЕТОДЫ для валидации
  bool get isValidConfiguration {
    return _isValidScale(scaleFactor) &&
        _isValidNoise(scaleNoise) &&
        _isValidFramerate(framerate) &&
        _isValidModelType(modelType);
  }

  static bool _isValidScale(int scale) => [1, 2, 4].contains(scale);
  static bool _isValidNoise(int noise) => noise >= -1 && noise <= 3;
  static bool _isValidFramerate(int fps) => fps >= 1 && fps <= 120;
  static bool _isValidModelType(String? model) =>
      ['cunet', 'anime', 'photo'].contains(model);

  // ГЕТТЕРЫ для ограничений
  static List<int> get validScaleFactors => [1, 2, 4];
  static List<int> get validNoiselevels => [-1, 0, 1, 2, 3];
  static List<String> get validModelTypes => ['cunet', 'anime', 'photo'];
  static List<String> get validVideoCodecs =>
      ['libx264', 'libx265', 'libaom-av1'];
  static List<String> get validAudioCodecs => ['aac', 'mp3', 'libopus'];

  // ПРОВЕРКА совместимости модели с параметрами
  bool isModelCompatible() {
    // Некоторые модели могут не поддерживать определенные комбинации scale/noise
    if (modelType == 'anime' && scaleFactor == 4 && scaleNoise > 1) {
      return false; // Anime модель может не поддерживать 4x с высоким noise
    }
    return true;
  }

  // ПОЛУЧЕНИЕ оптимальных параметров для текущей конфигурации
  Map<String, dynamic> getOptimalParams() {
    return {
      'scale_factor': scaleFactor,
      'noise_level': scaleNoise,
      'model_type': modelType,
      'is_high_quality': scaleFactor >= 4,
      'estimated_processing_time': _estimateProcessingTime(),
      'recommended_tile_size': _getRecommendedTileSize(),
    };
  }

  int _estimateProcessingTime() {
    // Примерная оценка времени обработки (в секундах на кадр)
    int baseTime = 1;
    if (scaleFactor == 4) baseTime *= 4;
    if (scaleNoise > 1) baseTime += 1;
    if (modelType == 'photo') baseTime += 1;
    return baseTime;
  }

  int _getRecommendedTileSize() {
    if (scaleFactor >= 4) return 100;
    if (scaleFactor >= 2) return 200;
    return 0; // auto
  }

  Map<String, dynamic> toMap() {
    return {
      'inputVideoPath': inputVideoPath,
      'outputPath': outputPath,
      'scaleNoise': scaleNoise,
      'scaleFactor': scaleFactor,
      'framerate': framerate,
      'videoCodec': videoCodec,
      'audioCodec': audioCodec,
      'modelType': modelType,
      'isValid': isValidConfiguration,
      'isCompatible': isModelCompatible(),
    };
  }

  @override
  String toString() {
    return 'ProcessingConfig(scale: ${scaleFactor}x, noise: $scaleNoise, model: $modelType, fps: $framerate, valid: $isValidConfiguration)';
  }
}

// ДОПОЛНИТЕЛЬНЫЙ класс для настроек waifu2x
class Waifu2xSettings {
  static const Map<String, List<String>> modelCompatibility = {
    'cunet': [
      'scale2.0x',
      'scale4.0x',
      'noise0_scale2.0x',
      'noise1_scale2.0x',
      'noise2_scale2.0x',
      'noise3_scale2.0x'
    ],
    'anime': [
      'noise0_scale2.0x',
      'noise1_scale2.0x',
      'noise2_scale2.0x',
      'noise3_scale2.0x',
      'noise0_scale4.0x',
      'noise1_scale4.0x'
    ],
    'photo': [
      'noise0_scale2.0x',
      'noise1_scale2.0x',
      'noise2_scale2.0x',
      'noise3_scale2.0x'
    ],
  };

  static bool isSupported(String modelType, int scale, int noise) {
    final compatibility = modelCompatibility[modelType] ?? [];
    final targetModel =
        noise >= 0 ? 'noise${noise}_scale${scale}.0x' : 'scale${scale}.0x';
    return compatibility.contains(targetModel);
  }

  static List<String> getSupportedCombinations(String modelType) {
    return modelCompatibility[modelType] ?? [];
  }
}

class SystemCapabilities {
  final bool hasVulkan;
  final List<String> availableGPUs;
  final int cpuCores;
  final String platform;
  final Map<String, dynamic> cpuInfo;
  final Map<String, dynamic> memoryInfo;
  final Map<String, dynamic> systemDetails;
  final Map<String, dynamic> hardwareDetails;

  SystemCapabilities({
    required this.hasVulkan,
    required this.availableGPUs,
    required this.cpuCores,
    required this.platform,
    this.cpuInfo = const {},
    this.memoryInfo = const {},
    this.systemDetails = const {},
    this.hardwareDetails = const {},
  });

  int get totalMemoryGB {
    final totalGB = memoryInfo['total_gb'];
    return totalGB is int ? totalGB : 0;
  }

  String get cpuName => cpuInfo['name']?.toString() ?? 'Unknown CPU';
  String get architecture => cpuInfo['architecture']?.toString() ?? 'Unknown';
  bool get supportsGPU => hasVulkan && availableGPUs.isNotEmpty;
  int get recommendedThreads => (cpuCores / 2).round().clamp(1, 8);

  String get systemSummary {
    return 'Platform: $platform, CPU: $cpuName (${cpuCores} cores), RAM: ${totalMemoryGB}GB, GPU: ${supportsGPU ? availableGPUs.length : 0} devices';
  }

  // НОВЫЙ МЕТОД: получение оптимальной конфигурации под железо
  ProcessingConfig getOptimalConfig(String inputPath, String outputPath) {
    int optimalScale = 2; // По умолчанию
    int optimalNoise = 1;
    String optimalModel = 'cunet';

    // Оптимизация под железо
    if (supportsGPU && totalMemoryGB >= 16) {
      optimalScale = 4; // Мощное железо - можем 4x
      optimalNoise = 2;
    } else if (supportsGPU && totalMemoryGB >= 8) {
      optimalScale = 2;
      optimalNoise = 1;
    } else {
      // Слабое железо
      optimalScale = 2;
      optimalNoise = 0; // Без шумоподавления для скорости
    }

    return ProcessingConfig(
      inputVideoPath: inputPath,
      outputPath: outputPath,
      scaleFactor: optimalScale,
      scaleNoise: optimalNoise,
      modelType: optimalModel,
    );
  }
}

class ProcessingProgress {
  final String stage;
  final double percentage;
  final String message;
  final DateTime timestamp;

  ProcessingProgress({
    required this.stage,
    required this.percentage,
    required this.message,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'stage': stage,
      'percentage': percentage,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  @override
  String toString() {
    return 'ProcessingProgress(${toMap()})';
  }
}

class ModelTypes {
  static const String cunet = 'cunet';
  static const String anime = 'anime';
  static const String photo = 'photo';

  static const List<String> all = [cunet, anime, photo];

  static String getDisplayName(String modelType) {
    switch (modelType) {
      case cunet:
        return 'CUNet (универсальная)';
      case anime:
        return 'Anime (для аниме/арт)';
      case photo:
        return 'Photo (для фотографий)';
      default:
        return 'Неизвестная модель';
    }
  }

  static String getDescription(String modelType) {
    switch (modelType) {
      case cunet:
        return 'Универсальная модель, подходит для большинства типов контента';
      case anime:
        return 'Оптимизирована для аниме, мультфильмов и художественных изображений';
      case photo:
        return 'Специализируется на реальных фотографиях и видео';
      default:
        return 'Описание недоступно';
    }
  }

  // НОВЫЙ МЕТОД: получение поддерживаемых комбинаций
  static List<Map<String, dynamic>> getSupportedCombinations(String modelType) {
    final combinations = <Map<String, dynamic>>[];

    for (int scale in [1, 2, 4]) {
      for (int noise in [-1, 0, 1, 2, 3]) {
        if (Waifu2xSettings.isSupported(modelType, scale, noise)) {
          combinations.add({
            'scale': scale,
            'noise': noise,
            'display': 'Scale: ${scale}x, Noise: $noise',
          });
        }
      }
    }

    return combinations;
  }
}

class VideoCodecs {
  static const String h264 = 'libx264';
  static const String h265 = 'libx265';
  static const String av1 = 'libaom-av1';

  static const List<String> all = [h264, h265, av1];

  static String getDisplayName(String codec) {
    switch (codec) {
      case h264:
        return 'H.264 (быстрый, совместимый)';
      case h265:
        return 'H.265 (меньший размер)';
      case av1:
        return 'AV1 (новейший стандарт)';
      default:
        return 'Неизвестный кодек';
    }
  }

  // НОВЫЙ МЕТОД: рекомендация кодека под разрешение
  static String getRecommendedCodec(int width, int height) {
    final totalPixels = width * height;

    if (totalPixels >= 3840 * 2160) {
      return h265; // 4K+ лучше сжимается H.265
    } else if (totalPixels >= 2560 * 1440) {
      return h264; // 1440p оптимально H.264
    } else {
      return h264; // 1080p и ниже
    }
  }
}

class AudioCodecs {
  static const String aac = 'aac';
  static const String mp3 = 'mp3';
  static const String opus = 'libopus';

  static const List<String> all = [aac, mp3, opus];

  static String getDisplayName(String codec) {
    switch (codec) {
      case aac:
        return 'AAC (рекомендуется)';
      case mp3:
        return 'MP3 (совместимый)';
      case opus:
        return 'Opus (высокое качество)';
      default:
        return 'Неизвестный кодек';
    }
  }
}

// ИСПРАВЛЕННЫЙ КЛАСС: Валидатор конфигурации с правильным импортом
class ConfigValidator {
  static List<String> validateConfig(ProcessingConfig config) {
    final errors = <String>[];

    if (!config.isValidConfiguration) {
      errors.add('Конфигурация содержит неподдерживаемые параметры');
    }

    if (!config.isModelCompatible()) {
      errors.add(
          'Модель ${config.modelType} несовместима с scale=${config.scaleFactor}, noise=${config.scaleNoise}');
    }

    // ТЕПЕРЬ File и Directory доступны благодаря импорту dart:io
    try {
      final inputFile = File(config.inputVideoPath);
      if (!inputFile.existsSync()) {
        errors.add('Входной файл не найден: ${config.inputVideoPath}');
      }
    } catch (e) {
      errors.add('Ошибка проверки входного файла: $e');
    }

    try {
      final outputDir = Directory(File(config.outputPath).parent.path);
      if (!outputDir.existsSync()) {
        errors.add('Выходная директория не существует: ${outputDir.path}');
      }
    } catch (e) {
      errors.add('Ошибка проверки выходной директории: $e');
    }

    return errors;
  }

  static bool isConfigValid(ProcessingConfig config) {
    return validateConfig(config).isEmpty;
  }

  // ДОПОЛНИТЕЛЬНЫЕ МЕТОДЫ валидации
  static bool canWriteToOutput(String outputPath) {
    try {
      final file = File(outputPath);
      final parent = file.parent;
      return parent.existsSync();
    } catch (e) {
      return false;
    }
  }

  static bool isVideoFile(String path) {
    final validExtensions = ['.mp4', '.avi', '.mov', '.mkv', '.webm', '.flv'];
    final extension = path.toLowerCase().split('.').last;
    return validExtensions.contains('.$extension');
  }

  static Map<String, dynamic> getValidationSummary(ProcessingConfig config) {
    final errors = validateConfig(config);

    return {
      'isValid': errors.isEmpty,
      'errors': errors,
      'warnings': _getWarnings(config),
      'recommendations': _getRecommendations(config),
    };
  }

  static List<String> _getWarnings(ProcessingConfig config) {
    final warnings = <String>[];

    if (config.scaleFactor == 4) {
      warnings.add('4x upscale требует много времени и ресурсов');
    }

    if (config.scaleNoise >= 2) {
      warnings.add('Высокое шумоподавление может замедлить обработку');
    }

    return warnings;
  }

  static List<String> _getRecommendations(ProcessingConfig config) {
    final recommendations = <String>[];

    if (config.scaleFactor == 1) {
      recommendations
          .add('Рассмотрите использование scale=2 для лучшего результата');
    }

    if (config.modelType == 'cunet' && config.scaleNoise == 0) {
      recommendations.add('Попробуйте noise=1 для лучшего качества с CUNet');
    }

    return recommendations;
  }
}
