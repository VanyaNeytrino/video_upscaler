import 'dart:io';
import 'package:video_upscaler/models/processing_config.dart';
import 'package:video_upscaler/services/executable_manager.dart';

class SystemInfoService {
  static Future<SystemCapabilities> analyzeSystem() async {
    final platform = _getPlatformName();
    final cpuCores = Platform.numberOfProcessors;

    bool hasVulkan = await _checkVulkanSupport();

    List<String> gpus = await _getAvailableGPUs();

    return SystemCapabilities(
      hasVulkan: hasVulkan,
      availableGPUs: gpus,
      cpuCores: cpuCores,
      platform: platform,
    );
  }

  static Future<bool> _checkVulkanSupport() async {
    try {
      final executableManager = ExecutableManager();

      if (!await _isExecutableManagerInitialized()) {
        return false;
      }

      final waifu2xPath = executableManager.waifu2xPath;
      final result = await Process.run(waifu2xPath, ['-l']);

      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        print('waifu2x GPU список: $output');

        return output.contains('Apple') ||
            output.contains('Intel') ||
            output.contains('AMD') ||
            output.contains('NVIDIA') ||
            output.contains('[0') && output.contains(']');
      }

      return false;
    } catch (e) {
      print('Ошибка проверки Vulkan: $e');
      return false;
    }
  }

  static Future<List<String>> _getAvailableGPUs() async {
    try {
      final executableManager = ExecutableManager();

      if (!await _isExecutableManagerInitialized()) {
        return [];
      }

      final waifu2xPath = executableManager.waifu2xPath;
      final result = await Process.run(waifu2xPath, ['-l']);

      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        print('Полный вывод waifu2x -l: $output');

        final lines = output.split('\n');
        final gpus = <String>[];

        for (final line in lines) {
          if (line.contains('[') &&
              line.contains(']') &&
              (line.contains('Apple') ||
                  line.contains('Intel') ||
                  line.contains('AMD') ||
                  line.contains('NVIDIA'))) {
            gpus.add(line.trim());
          }
        }

        return gpus;
      }
    } catch (e) {
      print('Ошибка получения списка GPU: $e');
    }
    return [];
  }

  static Future<bool> _isExecutableManagerInitialized() async {
    try {
      final executableManager = ExecutableManager();

      final waifu2xPath = executableManager.waifu2xPath;
      final ffmpegPath = executableManager.ffmpegPath;

      return await File(waifu2xPath).exists() &&
          await File(ffmpegPath).exists();
    } catch (e) {
      return false;
    }
  }

  static String _getPlatformName() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  static Future<Map<String, dynamic>> getSystemDetails() async {
    final capabilities = await analyzeSystem();
    final executableManager = ExecutableManager();

    Map<String, dynamic> details = {
      'platform': capabilities.platform,
      'cpu_cores': capabilities.cpuCores,
      'has_vulkan': capabilities.hasVulkan,
      'available_gpus': capabilities.availableGPUs,
      'executable_manager_initialized': await _isExecutableManagerInitialized(),
    };

    if (await _isExecutableManagerInitialized()) {
      try {
        details['waifu2x_path'] = executableManager.waifu2xPath;
        details['ffmpeg_path'] = executableManager.ffmpegPath;
        details['models_dir'] = executableManager.modelsDir;

        details['installation_size'] =
            await executableManager.getInstallationSize();

        details['installation_valid'] =
            await executableManager.validateInstallation();
      } catch (e) {
        details['error'] = e.toString();
      }
    }

    return details;
  }
}
