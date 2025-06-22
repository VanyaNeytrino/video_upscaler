import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_upscaler/services/executable_manager.dart';
import 'package:video_upscaler/services/video_processing_service.dart';
import 'package:video_upscaler/services/system_info_service.dart';
import 'package:video_upscaler/models/processing_config.dart';

void main() {
  runApp(VideoUpscalerApp());
}

class VideoUpscalerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Upscaler',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: VideoUpscalerHome(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class VideoUpscalerHome extends StatefulWidget {
  @override
  _VideoUpscalerHomeState createState() => _VideoUpscalerHomeState();
}

class _VideoUpscalerHomeState extends State<VideoUpscalerHome> {
  final VideoProcessingService _processingService = VideoProcessingService();

  String? _inputVideoPath;
  String? _outputVideoPath;
  bool _isInitialized = false;
  String _currentProgress = 'Запуск приложения...';
  double _progressPercentage = 0.0;
  Map<String, dynamic>? _systemInfo;

  int _scaleFactor = 2;
  int _scaleNoise = 1;
  String _modelType = 'cunet';
  int _framerate = 30;

  @override
  void initState() {
    super.initState();
    _initializeApp();

    _processingService.progressStream.listen((progress) {
      if (mounted) {
        setState(() {
          _currentProgress = progress;
        });
      }
    });

    _processingService.percentageStream.listen((percentage) {
      if (mounted) {
        setState(() {
          _progressPercentage = percentage;
        });
      }
    });
  }

  Future<void> _initializeApp() async {
    try {
      setState(() {
        _currentProgress = 'Инициализация ExecutableManager...';
        _progressPercentage = 10.0;
      });

      await ExecutableManager().initializeExecutables();

      setState(() {
        _currentProgress = 'Проверка системы...';
        _progressPercentage = 50.0;
      });

      final systemDetails = await SystemInfoService.getSystemDetails();

      setState(() {
        _currentProgress = 'Приложение готово к работе';
        _progressPercentage = 100.0;
        _isInitialized = true;
        _systemInfo = systemDetails;
      });

      print('=== ИНФОРМАЦИЯ О СИСТЕМЕ ===');
      systemDetails.forEach((key, value) {
        print('$key: $value');
      });
      print('========================');
    } catch (e) {
      setState(() {
        _currentProgress = 'Ошибка инициализации: $e';
        _progressPercentage = 0.0;
        _isInitialized = false;
      });

      if (mounted) {
        _showErrorDialog('Ошибка инициализации', e.toString());
      }
    }
  }

  Future<void> _selectInputVideo() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        dialogTitle: 'Выберите видео для обработки',
      );

      if (result != null && result.files.single.path != null) {
        final videoPath = result.files.single.path!;

        setState(() {
          _inputVideoPath = videoPath;
        });

        try {
          final videoInfo = await _processingService.getVideoInfo(videoPath);
          print('Информация о выбранном видео:');
          print(videoInfo['info']);
        } catch (e) {
          print('Не удалось получить информацию о видео: $e');
        }
      }
    } catch (e) {
      _showErrorDialog('Ошибка выбора файла', e.toString());
    }
  }

  Future<void> _selectOutputPath() async {
    try {
      String? result = await FilePicker.platform.saveFile(
        dialogTitle: 'Выберите путь для сохранения',
        fileName: 'upscaled_video.mp4',
        type: FileType.video,
      );

      if (result != null) {
        setState(() {
          _outputVideoPath = result;
        });
      }
    } catch (e) {
      _showErrorDialog('Ошибка выбора пути', e.toString());
    }
  }

  Future<void> _startProcessing() async {
    if (!_isInitialized) {
      _showErrorDialog('Ошибка', 'Приложение не инициализировано');
      return;
    }

    if (_inputVideoPath == null || _outputVideoPath == null) {
      _showErrorDialog('Ошибка', 'Выберите входной и выходной файлы');
      return;
    }

    try {
      final config = ProcessingConfig(
        inputVideoPath: _inputVideoPath!,
        outputPath: _outputVideoPath!,
        scaleNoise: _scaleNoise,
        scaleFactor: _scaleFactor,
        framerate: _framerate,
        modelType: _modelType,
      );

      final outputPath = await _processingService.processVideo(config);

      if (mounted) {
        _showSuccessDialog('Успех!', 'Видео успешно обработано:\n$outputPath');
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Ошибка обработки', e.toString());
      }
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(child: Text(message)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('OK'),
              ),
            ],
          ),
    );
  }

  void _showSuccessDialog(String title, String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('OK'),
              ),
            ],
          ),
    );
  }

  Widget _buildSystemInfoCard() {
    if (_systemInfo == null) return SizedBox.shrink();

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Информация о системе',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            SizedBox(height: 8),
            Text('Платформа: ${_systemInfo!['platform']}'),
            Text('CPU ядер: ${_systemInfo!['cpu_cores']}'),
            Text(
              'Vulkan: ${_systemInfo!['has_vulkan'] ? "Поддерживается" : "Не поддерживается"}',
            ),
            Text(
              'GPU: ${(_systemInfo!['available_gpus'] as List).length} устройств',
            ),
            if (_systemInfo!['installation_size'] != null)
              Text(
                'Размер установки: ${(_systemInfo!['installation_size'] / 1024 / 1024).toStringAsFixed(1)} MB',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsCard() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Настройки обработки',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Text('Масштаб: '),
                Expanded(
                  child: Slider(
                    value: _scaleFactor.toDouble(),
                    min: 1,
                    max: 4,
                    divisions: 3,
                    label: '${_scaleFactor}x',
                    onChanged:
                        _processingService.isProcessing
                            ? null
                            : (value) {
                              setState(() {
                                _scaleFactor = value.toInt();
                              });
                            },
                  ),
                ),
                Text('${_scaleFactor}x'),
              ],
            ),

            Row(
              children: [
                Text('Шумоподавление: '),
                Expanded(
                  child: Slider(
                    value: _scaleNoise.toDouble(),
                    min: 0,
                    max: 3,
                    divisions: 3,
                    label: _scaleNoise.toString(),
                    onChanged:
                        _processingService.isProcessing
                            ? null
                            : (value) {
                              setState(() {
                                _scaleNoise = value.toInt();
                              });
                            },
                  ),
                ),
                Text(_scaleNoise.toString()),
              ],
            ),

            Row(
              children: [
                Text('Модель: '),
                Expanded(
                  child: DropdownButton<String>(
                    value: _modelType,
                    isExpanded: true,
                    onChanged:
                        _processingService.isProcessing
                            ? null
                            : (value) {
                              setState(() {
                                _modelType = value!;
                              });
                            },
                    items: [
                      DropdownMenuItem(
                        value: 'cunet',
                        child: Text('CUNet (универсальная)'),
                      ),
                      DropdownMenuItem(
                        value: 'anime',
                        child: Text('Anime (для аниме/арт)'),
                      ),
                      DropdownMenuItem(
                        value: 'photo',
                        child: Text('Photo (для фотографий)'),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            Row(
              children: [
                Text('FPS: '),
                Expanded(
                  child: Slider(
                    value: _framerate.toDouble(),
                    min: 24,
                    max: 60,
                    divisions: 6,
                    label: _framerate.toString(),
                    onChanged:
                        _processingService.isProcessing
                            ? null
                            : (value) {
                              setState(() {
                                _framerate = value.toInt();
                              });
                            },
                  ),
                ),
                Text(_framerate.toString()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Video Upscaler'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSystemInfoCard(),
            SizedBox(height: 16),

            Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Входное видео',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed:
                          _processingService.isProcessing
                              ? null
                              : _selectInputVideo,
                      icon: Icon(Icons.video_file),
                      label: Text('Выбрать видео'),
                    ),
                    SizedBox(height: 8),
                    Text(
                      _inputVideoPath ?? 'Видео не выбрано',
                      style: TextStyle(
                        color:
                            _inputVideoPath != null
                                ? Colors.green
                                : Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),

            Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Выходное видео',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed:
                          _processingService.isProcessing
                              ? null
                              : _selectOutputPath,
                      icon: Icon(Icons.save),
                      label: Text('Выбрать путь сохранения'),
                    ),
                    SizedBox(height: 8),
                    Text(
                      _outputVideoPath ?? 'Путь не выбран',
                      style: TextStyle(
                        color:
                            _outputVideoPath != null
                                ? Colors.green
                                : Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),

            _buildSettingsCard(),
            SizedBox(height: 20),

            ElevatedButton.icon(
              onPressed:
                  (!_isInitialized || _processingService.isProcessing)
                      ? null
                      : _startProcessing,
              icon:
                  _processingService.isProcessing
                      ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : Icon(Icons.play_arrow),
              label: Text(
                _processingService.isProcessing
                    ? 'Обработка...'
                    : 'Начать обработку',
              ),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 16),
                textStyle: TextStyle(fontSize: 16),
              ),
            ),

            if (_processingService.isProcessing)
              Padding(
                padding: EdgeInsets.only(top: 8),
                child: ElevatedButton.icon(
                  onPressed: () => _processingService.stopProcessing(),
                  icon: Icon(Icons.stop),
                  label: Text('Остановить'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),

            SizedBox(height: 20),

            Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Прогресс',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: _progressPercentage / 100,
                      backgroundColor: Colors.grey[300],
                    ),
                    SizedBox(height: 8),
                    Text(
                      '${_progressPercentage.toStringAsFixed(1)}% - $_currentProgress',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _processingService.dispose();
    super.dispose();
  }
}
