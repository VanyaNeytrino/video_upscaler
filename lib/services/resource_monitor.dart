import 'dart:async';
import 'dart:io';
import 'dart:convert';

class ResourceMonitor {
  static ResourceMonitor? _instance;
  static ResourceMonitor get instance => _instance ??= ResourceMonitor._();
  ResourceMonitor._();

  Timer? _timer;
  final _cpuController = StreamController<double>.broadcast();
  final _memoryController = StreamController<double>.broadcast();
  final _progressController = StreamController<ProcessingProgress>.broadcast();

  Stream<double> get cpuUsageStream => _cpuController.stream;
  Stream<double> get memoryUsageStream => _memoryController.stream;
  Stream<ProcessingProgress> get progressStream => _progressController.stream;

  ProcessingProgress? _currentProgress;

  void startMonitoring() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      _updateStats();
    });
  }

  void stopMonitoring() {
    _timer?.cancel();
  }

  void updateProgress({
    required int processedFrames,
    required int totalFrames,
    required String currentStage,
    String? currentFile,
  }) {
    _currentProgress = ProcessingProgress(
      processedFrames: processedFrames,
      totalFrames: totalFrames,
      currentStage: currentStage,
      currentFile: currentFile,
      timestamp: DateTime.now(),
    );
    _progressController.add(_currentProgress!);
  }

  void _updateStats() async {
    try {
      final cpuUsage = await _getRealCpuUsage();
      final memoryUsage = await _getRealMemoryUsage();

      _cpuController.add(cpuUsage);
      _memoryController.add(memoryUsage);
    } catch (e) {
      print('⚠️ Ошибка мониторинга ресурсов: $e');
    }
  }

  /// Получает реальное использование CPU
  Future<double> _getRealCpuUsage() async {
    try {
      if (Platform.isMacOS) {
        return await _getMacOSCpuUsage();
      } else if (Platform.isLinux) {
        return await _getLinuxCpuUsage();
      } else if (Platform.isWindows) {
        return await _getWindowsCpuUsage();
      }
    } catch (e) {
      print('⚠️ Ошибка получения CPU: $e');
    }
    return 0.0;
  }

  /// Получает реальное использование памяти
  Future<double> _getRealMemoryUsage() async {
    try {
      if (Platform.isMacOS) {
        return await _getMacOSMemoryUsage();
      } else if (Platform.isLinux) {
        return await _getLinuxMemoryUsage();
      } else if (Platform.isWindows) {
        return await _getWindowsMemoryUsage();
      }
    } catch (e) {
      print('⚠️ Ошибка получения памяти: $e');
    }
    return 0.0;
  }

  /// macOS CPU usage
  Future<double> _getMacOSCpuUsage() async {
    try {
      final result = await Process.run('top', ['-l', '1', '-n', '0']);
      final output = result.stdout.toString();

      // Парсим строку: "CPU usage: 12.5% user, 2.1% sys, 85.4% idle"
      final cpuLine = output.split('\n').firstWhere(
            (line) => line.contains('CPU usage'),
            orElse: () => '',
          );

      if (cpuLine.isNotEmpty) {
        final regex = RegExp(r'(\d+\.?\d*)%\s+user.*?(\d+\.?\d*)%\s+sys');
        final match = regex.firstMatch(cpuLine);

        if (match != null) {
          final userCpu = double.tryParse(match.group(1) ?? '0') ?? 0;
          final sysCpu = double.tryParse(match.group(2) ?? '0') ?? 0;
          return userCpu + sysCpu;
        }
      }
    } catch (e) {
      print('⚠️ Ошибка macOS CPU: $e');
    }
    return 0.0;
  }

  /// macOS Memory usage
  Future<double> _getMacOSMemoryUsage() async {
    try {
      final result = await Process.run('vm_stat', []);
      final output = result.stdout.toString();

      // Парсим vm_stat
      final lines = output.split('\n');
      int pageSize = 4096; // Обычно 4KB на страницу

      int totalPages = 0;
      int freePages = 0;
      int inactivePages = 0;

      for (final line in lines) {
        if (line.contains('Pages free:')) {
          freePages =
              int.tryParse(line.split(':')[1].trim().replaceAll('.', '')) ?? 0;
        } else if (line.contains('Pages inactive:')) {
          inactivePages =
              int.tryParse(line.split(':')[1].trim().replaceAll('.', '')) ?? 0;
        }
      }

      // Получаем общую память системы
      final memResult = await Process.run('sysctl', ['hw.memsize']);
      final totalMemory =
          int.tryParse(memResult.stdout.toString().split(':')[1].trim()) ?? 0;

      if (totalMemory > 0) {
        final totalPagesCalc = totalMemory ~/ pageSize;
        final usedPages = totalPagesCalc - freePages - inactivePages;
        return (usedPages / totalPagesCalc) * 100;
      }
    } catch (e) {
      print('⚠️ Ошибка macOS Memory: $e');
    }
    return 0.0;
  }

  /// Linux CPU usage
  Future<double> _getLinuxCpuUsage() async {
    try {
      final result = await Process.run('top', ['-bn1']);
      final output = result.stdout.toString();

      final cpuLine = output.split('\n').firstWhere(
            (line) => line.contains('%Cpu(s)'),
            orElse: () => '',
          );

      if (cpuLine.isNotEmpty) {
        final regex = RegExp(r'(\d+\.?\d*)%?\s*us.*?(\d+\.?\d*)%?\s*sy');
        final match = regex.firstMatch(cpuLine);

        if (match != null) {
          final userCpu = double.tryParse(match.group(1) ?? '0') ?? 0;
          final sysCpu = double.tryParse(match.group(2) ?? '0') ?? 0;
          return userCpu + sysCpu;
        }
      }
    } catch (e) {
      print('⚠️ Ошибка Linux CPU: $e');
    }
    return 0.0;
  }

  /// Linux Memory usage
  Future<double> _getLinuxMemoryUsage() async {
    try {
      final result = await Process.run('free', ['-m']);
      final output = result.stdout.toString();

      final lines = output.split('\n');
      final memLine = lines.firstWhere(
        (line) => line.startsWith('Mem:'),
        orElse: () => '',
      );

      if (memLine.isNotEmpty) {
        final parts = memLine.split(RegExp(r'\s+'));
        if (parts.length >= 3) {
          final total = int.tryParse(parts[1]) ?? 0;
          final used = int.tryParse(parts[2]) ?? 0;
          if (total > 0) {
            return (used / total) * 100;
          }
        }
      }
    } catch (e) {
      print('⚠️ Ошибка Linux Memory: $e');
    }
    return 0.0;
  }

  /// Windows CPU usage
  Future<double> _getWindowsCpuUsage() async {
    try {
      final result =
          await Process.run('wmic', ['cpu', 'get', 'loadpercentage', '/value']);

      final output = result.stdout.toString();
      final regex = RegExp(r'LoadPercentage=(\d+)');
      final match = regex.firstMatch(output);

      if (match != null) {
        return double.tryParse(match.group(1) ?? '0') ?? 0;
      }
    } catch (e) {
      print('⚠️ Ошибка Windows CPU: $e');
    }
    return 0.0;
  }

  /// Windows Memory usage
  Future<double> _getWindowsMemoryUsage() async {
    try {
      final result = await Process.run('wmic',
          ['OS', 'get', 'TotalVisibleMemorySize,FreePhysicalMemory', '/value']);

      final output = result.stdout.toString();
      final totalMatch =
          RegExp(r'TotalVisibleMemorySize=(\d+)').firstMatch(output);
      final freeMatch = RegExp(r'FreePhysicalMemory=(\d+)').firstMatch(output);

      if (totalMatch != null && freeMatch != null) {
        final total = int.tryParse(totalMatch.group(1) ?? '0') ?? 0;
        final free = int.tryParse(freeMatch.group(1) ?? '0') ?? 0;
        if (total > 0) {
          return ((total - free) / total) * 100;
        }
      }
    } catch (e) {
      print('⚠️ Ошибка Windows Memory: $e');
    }
    return 0.0;
  }

  void dispose() {
    _timer?.cancel();
    _cpuController.close();
    _memoryController.close();
    _progressController.close();
  }
}

/// Класс для отслеживания прогресса обработки
class ProcessingProgress {
  final int processedFrames;
  final int totalFrames;
  final String currentStage;
  final String? currentFile;
  final DateTime timestamp;

  ProcessingProgress({
    required this.processedFrames,
    required this.totalFrames,
    required this.currentStage,
    this.currentFile,
    required this.timestamp,
  });

  double get percentage =>
      totalFrames > 0 ? (processedFrames / totalFrames) * 100 : 0.0;

  String get progressText => '$processedFrames / $totalFrames кадров';

  String get eta {
    if (processedFrames == 0) return 'Оценка...';

    final elapsedSeconds = DateTime.now().difference(timestamp).inSeconds;
    final framesPerSecond = processedFrames / elapsedSeconds;

    if (framesPerSecond <= 0) return 'Оценка...';

    final remainingFrames = totalFrames - processedFrames;
    final remainingSeconds = remainingFrames / framesPerSecond;

    final minutes = (remainingSeconds / 60).floor();
    final seconds = (remainingSeconds % 60).floor();

    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }
}
