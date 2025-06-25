import 'dart:io';
import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
// import 'package:device_vendor_info/device_vendor_info.dart';  // УБРАНО
import 'package:video_upscaler/models/processing_config.dart';
import 'package:video_upscaler/services/executable_manager.dart';

class SystemInfoService {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  static Future<SystemCapabilities> analyzeSystem() async {
    final platform = _getPlatformName();
    final cpuCores = Platform.numberOfProcessors;

    // Получаем системную информацию через device_info_plus
    final systemDetails = await _getSystemDetails();
    final cpuInfo = await _getCPUInfoFromSystem(systemDetails);
    final memoryInfo = await _getMemoryInfoFromSystem(systemDetails);

    // УБИРАЕМ: детальную информацию о железе (несовместимо с Apple Silicon)
    final hardwareDetails = await _getBasicHardwareDetails();

    // Проверяем Vulkan и GPU через waifu2x
    bool hasVulkan = await _checkVulkanSupport();
    List<String> gpus = await _getAvailableGPUs();

    return SystemCapabilities(
      hasVulkan: hasVulkan,
      availableGPUs: gpus,
      cpuCores: cpuCores,
      platform: platform,
      cpuInfo: cpuInfo,
      memoryInfo: memoryInfo,
      systemDetails: systemDetails,
      hardwareDetails: hardwareDetails,
    );
  }

  // ЗАМЕНЯЕМ: упрощенная информация о железе без device_vendor_info
  static Future<Map<String, dynamic>> _getBasicHardwareDetails() async {
    Map<String, dynamic> hardwareInfo = {};

    try {
      // Основная информация об архитектуре
      hardwareInfo['architecture'] = _getArchitecture();
      hardwareInfo['platform'] = _getPlatformName();

      // Проверка виртуализации через простые методы
      hardwareInfo['virtualization'] = await _checkVirtualization();

      // Информация об окружении
      final environment = Platform.environment;
      hardwareInfo['environment'] = {
        'user': environment['USER'] ?? environment['USERNAME'] ?? 'Unknown',
        'home': environment['HOME'] ?? environment['USERPROFILE'] ?? 'Unknown',
        'path_separator': Platform.pathSeparator,
      };
    } catch (e) {
      print('Ошибка получения базовой информации о железе: $e');
      hardwareInfo['error'] = e.toString();
    }

    return hardwareInfo;
  }

  // Простая проверка виртуализации без внешних библиотек
  static Future<bool> _checkVirtualization() async {
    try {
      final platform = _getPlatformName();

      if (platform == 'linux') {
        // Проверяем /proc/cpuinfo на наличие признаков виртуализации
        final file = File('/proc/cpuinfo');
        if (await file.exists()) {
          final content = await file.readAsString();
          return content.toLowerCase().contains('hypervisor') ||
              content.toLowerCase().contains('vmware') ||
              content.toLowerCase().contains('virtualbox');
        }
      } else if (platform == 'macos') {
        // На macOS проверяем через system_profiler
        final result =
            await Process.run('system_profiler', ['SPHardwareDataType']);
        if (result.exitCode == 0) {
          final output = result.stdout.toString().toLowerCase();
          return output.contains('virtual') || output.contains('vmware');
        }
      } else if (platform == 'windows') {
        // На Windows проверяем через systeminfo
        final result = await Process.run('systeminfo', []);
        if (result.exitCode == 0) {
          final output = result.stdout.toString().toLowerCase();
          return output.contains('virtual') ||
              output.contains('vmware') ||
              output.contains('virtualbox');
        }
      }
    } catch (e) {
      print('Не удалось проверить виртуализацию: $e');
    }

    return false; // По умолчанию считаем, что не виртуализация
  }

  // Остальные методы остаются без изменений...
  static Future<Map<String, dynamic>> _getSystemDetails() async {
    try {
      final platform = _getPlatformName();

      if (platform == 'windows') {
        final windowsInfo = await _deviceInfo.windowsInfo;
        return {
          'type': 'windows',
          'computer_name': windowsInfo.computerName,
          'user_name': windowsInfo.userName,
          'system_memory_in_megabytes': windowsInfo.systemMemoryInMegabytes,
          'number_of_cores': windowsInfo.numberOfCores,
          'build_number': windowsInfo.buildNumber,
          'display_version': windowsInfo.displayVersion,
          'product_name': windowsInfo.productName,
          'edition_id': windowsInfo.editionId,
          'release_id': windowsInfo.releaseId,
          'major_version': windowsInfo.majorVersion,
          'minor_version': windowsInfo.minorVersion,
        };
      } else if (platform == 'macos') {
        final macOSInfo = await _deviceInfo.macOsInfo;
        return {
          'type': 'macos',
          'computer_name': macOSInfo.computerName,
          'host_name': macOSInfo.hostName,
          'arch': macOSInfo.arch,
          'model': macOSInfo.model,
          'kernel_version': macOSInfo.kernelVersion,
          'os_release': macOSInfo.osRelease,
          'major_version': macOSInfo.majorVersion,
          'minor_version': macOSInfo.minorVersion,
          'patch_version': macOSInfo.patchVersion,
          'cpu_frequency': macOSInfo.cpuFrequency,
          'memory_size': macOSInfo.memorySize,
          'system_guid': macOSInfo.systemGUID,
        };
      } else if (platform == 'linux') {
        final linuxInfo = await _deviceInfo.linuxInfo;
        return {
          'type': 'linux',
          'name': linuxInfo.name,
          'version': linuxInfo.version,
          'id': linuxInfo.id,
          'id_like': linuxInfo.idLike?.join(', ') ?? '',
          'version_codename': linuxInfo.versionCodename,
          'version_id': linuxInfo.versionId,
          'pretty_name': linuxInfo.prettyName,
          'build_id': linuxInfo.buildId,
          'variant': linuxInfo.variant,
          'variant_id': linuxInfo.variantId,
          'machine_id': linuxInfo.machineId,
        };
      }
    } catch (e) {
      print('Ошибка получения системной информации: $e');
    }

    return {
      'type': _getPlatformName(),
      'error': 'Could not retrieve system information'
    };
  }

  static Future<Map<String, dynamic>> _getCPUInfoFromSystem(
      Map<String, dynamic> systemDetails) async {
    Map<String, dynamic> cpuInfo = {
      'cores': Platform.numberOfProcessors,
      'architecture': _getArchitecture(),
    };

    if (systemDetails['type'] == 'windows') {
      cpuInfo.addAll({
        'cores':
            systemDetails['number_of_cores'] ?? Platform.numberOfProcessors,
        'name': 'Unknown Windows CPU',
        'vendor': 'Unknown',
      });
    } else if (systemDetails['type'] == 'macos') {
      cpuInfo.addAll({
        'name': systemDetails['model'] ?? 'Unknown Mac CPU',
        'architecture': systemDetails['arch'] ?? 'Unknown',
        'frequency': systemDetails['cpu_frequency'] ?? 0,
      });
    } else if (systemDetails['type'] == 'linux') {
      try {
        final cpuInfoFromProc = await _getLinuxCPUInfo();
        cpuInfo.addAll(cpuInfoFromProc);
      } catch (e) {
        print('Не удалось получить информацию о CPU из /proc/cpuinfo: $e');
      }
    }

    return cpuInfo;
  }

  static Future<Map<String, dynamic>> _getLinuxCPUInfo() async {
    try {
      final file = File('/proc/cpuinfo');
      if (await file.exists()) {
        final content = await file.readAsString();
        final lines = content.split('\n');

        String? modelName;
        String? vendor;
        double? frequency;

        for (final line in lines) {
          if (line.startsWith('model name')) {
            modelName = line.split(':').last.trim();
          } else if (line.startsWith('vendor_id')) {
            vendor = line.split(':').last.trim();
          } else if (line.startsWith('cpu MHz')) {
            try {
              frequency = double.parse(line.split(':').last.trim());
            } catch (e) {
              // Игнорируем ошибки парсинга
            }
          }
        }

        return {
          'name': modelName ?? 'Unknown Linux CPU',
          'vendor': vendor ?? 'Unknown',
          'frequency': frequency ?? 0.0,
        };
      }
    } catch (e) {
      print('Ошибка чтения /proc/cpuinfo: $e');
    }

    return {'name': 'Unknown Linux CPU'};
  }

  static Future<Map<String, dynamic>> _getMemoryInfoFromSystem(
      Map<String, dynamic> systemDetails) async {
    Map<String, dynamic> memoryInfo = {};

    if (systemDetails['type'] == 'windows') {
      final totalMB = systemDetails['system_memory_in_megabytes'] ?? 0;
      memoryInfo = {
        'total_physical': totalMB * 1024 * 1024,
        'total_mb': totalMB,
        'total_gb': (totalMB / 1024).round(),
      };
    } else if (systemDetails['type'] == 'macos') {
      final totalBytes = systemDetails['memory_size'] ?? 0;
      memoryInfo = {
        'total_physical': totalBytes,
        'total_mb': (totalBytes / (1024 * 1024)).round(),
        'total_gb': (totalBytes / (1024 * 1024 * 1024)).round(),
      };
    } else if (systemDetails['type'] == 'linux') {
      try {
        final memInfoFromProc = await _getLinuxMemoryInfo();
        memoryInfo.addAll(memInfoFromProc);
      } catch (e) {
        print('Не удалось получить информацию о памяти из /proc/meminfo: $e');
        memoryInfo = {'error': 'Could not read memory info'};
      }
    }

    return memoryInfo;
  }

  static Future<Map<String, dynamic>> _getLinuxMemoryInfo() async {
    try {
      final file = File('/proc/meminfo');
      if (await file.exists()) {
        final content = await file.readAsString();
        final lines = content.split('\n');

        int? totalKB;
        int? freeKB;
        int? availableKB;

        for (final line in lines) {
          if (line.startsWith('MemTotal:')) {
            totalKB = int.tryParse(line.split(RegExp(r'\s+'))[1]);
          } else if (line.startsWith('MemFree:')) {
            freeKB = int.tryParse(line.split(RegExp(r'\s+'))[1]);
          } else if (line.startsWith('MemAvailable:')) {
            availableKB = int.tryParse(line.split(RegExp(r'\s+'))[1]);
          }
        }

        if (totalKB != null) {
          return {
            'total_physical': totalKB * 1024,
            'free_physical': (freeKB ?? 0) * 1024,
            'available_physical': (availableKB ?? 0) * 1024,
            'total_mb': (totalKB / 1024).round(),
            'total_gb': (totalKB / (1024 * 1024)).round(),
            'usage_percent': freeKB != null
                ? ((totalKB - freeKB) / totalKB * 100).round()
                : 0,
          };
        }
      }
    } catch (e) {
      print('Ошибка чтения /proc/meminfo: $e');
    }

    return {'error': 'Could not read memory info'};
  }

  static String _getArchitecture() {
    final version = Platform.version.toLowerCase();
    final environment = Platform.environment;

    if (version.contains('arm64') || version.contains('aarch64')) {
      return 'ARM64';
    } else if (version.contains('arm')) {
      return 'ARM';
    } else if (version.contains('x86_64') || version.contains('amd64')) {
      return 'x64';
    } else if (version.contains('x86') || version.contains('i386')) {
      return 'x86';
    }

    final arch = environment['PROCESSOR_ARCHITECTURE'] ??
        environment['HOSTTYPE'] ??
        environment['MACHTYPE'] ??
        '';

    if (arch.toLowerCase().contains('arm64') ||
        arch.toLowerCase().contains('aarch64')) {
      return 'ARM64';
    } else if (arch.toLowerCase().contains('arm')) {
      return 'ARM';
    } else if (arch.toLowerCase().contains('x64') ||
        arch.toLowerCase().contains('amd64')) {
      return 'x64';
    } else if (arch.toLowerCase().contains('x86')) {
      return 'x86';
    }

    return 'Unknown';
  }

  // Остальные методы остаются без изменений
  static Future<bool> _checkVulkanSupport() async {
    try {
      final executableManager = ExecutableManager.instance;

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
            (output.contains('[0') && output.contains(']'));
      }

      return false;
    } catch (e) {
      print('Ошибка проверки Vulkan: $e');
      return false;
    }
  }

  static Future<List<String>> _getAvailableGPUs() async {
    try {
      final executableManager = ExecutableManager.instance;

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
      final executableManager = ExecutableManager.instance;
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
    final executableManager = ExecutableManager.instance;

    Map<String, dynamic> details = {
      'platform': capabilities.platform,
      'cpu_cores': capabilities.cpuCores,
      'cpu_info': capabilities.cpuInfo,
      'memory_info': capabilities.memoryInfo,
      'system_details': capabilities.systemDetails,
      'hardware_details': capabilities.hardwareDetails,
      'has_vulkan': capabilities.hasVulkan,
      'available_gpus': capabilities.availableGPUs,
      'executable_manager_initialized': await _isExecutableManagerInitialized(),
    };

    if (await _isExecutableManagerInitialized()) {
      try {
        details['waifu2x_path'] = executableManager.waifu2xPath;
        details['ffmpeg_path'] = executableManager.ffmpegPath;
        details['models_dir'] = executableManager.modelsDir;
        details['installation_valid'] =
            await executableManager.validateInstallation();
        details['optimal_settings'] = await getOptimalSettings();
      } catch (e) {
        details['error'] = e.toString();
      }
    }

    return details;
  }

  static Future<Map<String, dynamic>> getOptimalSettings() async {
    final capabilities = await analyzeSystem();

    int recommendedTileSize = 0;
    int recommendedThreads = capabilities.cpuCores;
    bool useGPU =
        capabilities.hasVulkan && capabilities.availableGPUs.isNotEmpty;

    final memoryInfo = capabilities.memoryInfo;
    final totalMemoryGB = capabilities.totalMemoryGB;

    if (totalMemoryGB >= 16) {
      recommendedTileSize = 400;
      recommendedThreads = (capabilities.cpuCores * 0.75).round();
    } else if (totalMemoryGB >= 8) {
      recommendedTileSize = 200;
      recommendedThreads = (capabilities.cpuCores * 0.5).round();
    } else if (totalMemoryGB >= 4) {
      recommendedTileSize = 100;
      recommendedThreads = (capabilities.cpuCores * 0.25).round();
    } else {
      recommendedTileSize = 50;
      recommendedThreads = 1;
    }

    recommendedThreads = recommendedThreads.clamp(1, 8);

    return {
      'recommended_tile_size': recommendedTileSize,
      'recommended_threads': recommendedThreads,
      'use_gpu': useGPU,
      'gpu_device': useGPU ? 0 : -1,
      'cpu_cores': capabilities.cpuCores,
      'memory_gb': totalMemoryGB,
      'platform_optimized': true,
    };
  }
}
