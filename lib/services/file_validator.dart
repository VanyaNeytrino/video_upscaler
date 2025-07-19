import 'dart:io';

class FileValidator {
  // Ограничения (можно настроить)
  static const int maxFileSizeMB = 1000; // 1GB
  static const int maxResolutionWidth = 3840; // 4K
  static const int maxResolutionHeight = 2160; // 4K
  static const int maxDurationSeconds = 1800; // 30 минут

  static ValidationResult validateVideoFile(String filePath) {
    final file = File(filePath);
    final warnings = <String>[];
    final errors = <String>[];

    // Проверка существования файла
    if (!file.existsSync()) {
      errors.add('Файл не найден');
      return ValidationResult(
          isValid: false, errors: errors, warnings: warnings);
    }

    // Проверка размера файла
    final fileSizeBytes = file.lengthSync();
    final fileSizeMB = fileSizeBytes / (1024 * 1024);

    if (fileSizeMB > maxFileSizeMB) {
      errors.add(
          'Файл слишком большой: ${fileSizeMB.toStringAsFixed(1)}MB (макс: ${maxFileSizeMB}MB)');
    } else if (fileSizeMB > maxFileSizeMB * 0.8) {
      warnings.add(
          'Большой файл: ${fileSizeMB.toStringAsFixed(1)}MB. Обработка может быть медленной.');
    }

    // Проверка расширения
    final extension = filePath.toLowerCase().split('.').last;
    final validExtensions = ['mp4', 'avi', 'mov', 'mkv', 'webm'];

    if (!validExtensions.contains(extension)) {
      warnings.add('Неподдерживаемый формат: .$extension');
    }

    return ValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
      fileSizeMB: fileSizeMB,
    );
  }

  static String getRecommendations(double fileSizeMB) {
    if (fileSizeMB > 500) {
      return 'Для больших файлов рекомендуется: Scale 2x, Noise 0-1';
    } else if (fileSizeMB > 100) {
      return 'Для средних файлов рекомендуется: Scale 2-4x, Noise 1-2';
    } else {
      return 'Для маленьких файлов можно: Scale 4x, Noise 2-3';
    }
  }
}

class ValidationResult {
  final bool isValid;
  final List<String> errors;
  final List<String> warnings;
  final double? fileSizeMB;

  ValidationResult({
    required this.isValid,
    required this.errors,
    required this.warnings,
    this.fileSizeMB,
  });
}
