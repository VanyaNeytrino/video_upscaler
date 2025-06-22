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
    this.scaleNoise = 1,
    this.scaleFactor = 2,
    this.framerate = 30,
    this.videoCodec = 'libx264',
    this.audioCodec = 'aac',
    this.modelType = 'cunet',
  });

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
    };
  }

  @override
  String toString() {
    return 'ProcessingConfig(${toMap()})';
  }
}

class SystemCapabilities {
  final bool hasVulkan;
  final List<String> availableGPUs;
  final int cpuCores;
  final String platform;

  SystemCapabilities({
    required this.hasVulkan,
    required this.availableGPUs,
    required this.cpuCores,
    required this.platform,
  });

  SystemCapabilities copyWith({
    bool? hasVulkan,
    List<String>? availableGPUs,
    int? cpuCores,
    String? platform,
  }) {
    return SystemCapabilities(
      hasVulkan: hasVulkan ?? this.hasVulkan,
      availableGPUs: availableGPUs ?? this.availableGPUs,
      cpuCores: cpuCores ?? this.cpuCores,
      platform: platform ?? this.platform,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'hasVulkan': hasVulkan,
      'availableGPUs': availableGPUs,
      'cpuCores': cpuCores,
      'platform': platform,
    };
  }

  @override
  String toString() {
    return 'SystemCapabilities(${toMap()})';
  }

  bool get supportsGPU => hasVulkan && availableGPUs.isNotEmpty;

  int get recommendedThreads => (cpuCores / 2).round().clamp(1, 8);

  String get capabilitiesDescription {
    final parts = <String>[];

    parts.add('Platform: $platform');
    parts.add('CPU Cores: $cpuCores');
    parts.add('Vulkan: ${hasVulkan ? "Supported" : "Not supported"}');

    if (availableGPUs.isNotEmpty) {
      parts.add('GPUs: ${availableGPUs.length} (${availableGPUs.first})');
    } else {
      parts.add('GPUs: None available');
    }

    return parts.join(', ');
  }
}

class VideoInfo {
  final String path;
  final Duration? duration;
  final int? width;
  final int? height;
  final double? fps;
  final String? codec;
  final bool hasAudio;
  final int? bitrate;

  VideoInfo({
    required this.path,
    this.duration,
    this.width,
    this.height,
    this.fps,
    this.codec,
    this.hasAudio = false,
    this.bitrate,
  });

  Map<String, dynamic> toMap() {
    return {
      'path': path,
      'duration': duration?.inSeconds,
      'width': width,
      'height': height,
      'fps': fps,
      'codec': codec,
      'hasAudio': hasAudio,
      'bitrate': bitrate,
    };
  }

  @override
  String toString() {
    return 'VideoInfo(${toMap()})';
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
