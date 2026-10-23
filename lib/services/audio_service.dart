import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../models/recording_item.dart';

class AudioMetrics {
  final double level;
  final bool isGateOpen;

  const AudioMetrics({required this.level, required this.isGateOpen});
}

class AudioService {
  static const MethodChannel _methodChannel =
      MethodChannel('com.example.rec_sound_mic/audio');
  static const EventChannel _eventChannel =
      EventChannel('com.example.rec_sound_mic/audio_level');

  Stream<AudioMetrics>? _audioMetricsStream;

  Stream<AudioMetrics> get audioMetricsStream {
    _audioMetricsStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) {
          if (event is Map) {
            final level = (event['level'] as num?)?.toDouble() ?? 0.0;
            final isGateOpen = event['isGateOpen'] as bool? ?? false;
            return AudioMetrics(level: level, isGateOpen: isGateOpen);
          } else if (event is num) {
            return AudioMetrics(level: event.toDouble(), isGateOpen: false);
          }
          return const AudioMetrics(level: 0.0, isGateOpen: false);
        })
        .handleError((_) => const AudioMetrics(level: 0.0, isGateOpen: false));
    return _audioMetricsStream!;
  }

  Future<bool> checkAndRequestPermissions() async {
    try {
      final bool granted =
          await _methodChannel.invokeMethod('requestPermissions') ?? false;
      return granted;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<bool> startLiveMic() async {
    try {
      final bool success =
          await _methodChannel.invokeMethod('startLiveMic') ?? false;
      return success;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<bool> stopLiveMic() async {
    try {
      final bool success =
          await _methodChannel.invokeMethod('stopLiveMic') ?? false;
      return success;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<bool> isLiveMicActive() async {
    try {
      final bool active =
          await _methodChannel.invokeMethod('isLiveMicActive') ?? false;
      return active;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<void> setGain(double gain) async {
    try {
      await _methodChannel.invokeMethod('setGain', {'gain': gain});
    } on PlatformException catch (_) {}
  }

  Future<void> setNoiseGateThreshold(double threshold) async {
    try {
      await _methodChannel.invokeMethod(
          'setNoiseGateThreshold', {'threshold': threshold});
    } on PlatformException catch (_) {}
  }

  Future<void> setBandpassFilter(bool enabled) async {
    try {
      await _methodChannel.invokeMethod(
          'setBandpassEnabled', {'enabled': enabled});
    } on PlatformException catch (_) {}
  }

  Future<void> setNoiseSuppression(bool enabled) async {
    try {
      await _methodChannel.invokeMethod(
          'setNoiseSuppression', {'enabled': enabled});
    } on PlatformException catch (_) {}
  }

  Future<void> setEchoCancellation(bool enabled) async {
    try {
      await _methodChannel.invokeMethod(
          'setEchoCancellation', {'enabled': enabled});
    } on PlatformException catch (_) {}
  }

  Future<String> _getRecordingsDirectoryPath() async {
    final docDir = await getApplicationDocumentsDirectory();
    final recDir = Directory('${docDir.path}/Recordings');
    if (!await recDir.exists()) {
      await recDir.create(recursive: true);
    }
    return recDir.path;
  }

  Future<String?> startRecording() async {
    try {
      final dirPath = await _getRecordingsDirectoryPath();
      final timestamp =
          DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filePath = '$dirPath/JBL_REC_$timestamp.wav';

      final bool success = await _methodChannel
              .invokeMethod('startRecording', {'path': filePath}) ??
          false;

      return success ? filePath : null;
    } on PlatformException catch (_) {
      return null;
    }
  }

  Future<String?> stopRecording() async {
    try {
      final String? savedPath =
          await _methodChannel.invokeMethod('stopRecording');
      return savedPath;
    } on PlatformException catch (_) {
      return null;
    }
  }

  Future<bool> isRecording() async {
    try {
      final bool active =
          await _methodChannel.invokeMethod('isRecording') ?? false;
      return active;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<bool> playAudio(String path) async {
    try {
      return await _methodChannel.invokeMethod('playAudio', {'path': path}) ??
          false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<void> pauseAudio() async {
    try {
      await _methodChannel.invokeMethod('pauseAudio');
    } on PlatformException catch (_) {}
  }

  Future<void> resumeAudio() async {
    try {
      await _methodChannel.invokeMethod('resumeAudio');
    } on PlatformException catch (_) {}
  }

  Future<void> stopAudio() async {
    try {
      await _methodChannel.invokeMethod('stopAudio');
    } on PlatformException catch (_) {}
  }

  Future<void> seekAudio(int positionMs) async {
    try {
      await _methodChannel
          .invokeMethod('seekAudio', {'position': positionMs});
    } on PlatformException catch (_) {}
  }

  Future<Map<String, dynamic>> getPlaybackStatus() async {
    try {
      final res = await _methodChannel.invokeMethod('getPlaybackStatus');
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
    } on PlatformException catch (_) {}
    return {'isPlaying': false, 'position': 0, 'duration': 0};
  }

  Future<Map<String, dynamic>> getBluetoothStatus() async {
    try {
      final res =
          await _methodChannel.invokeMethod('getBluetoothStatus');
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
    } on PlatformException catch (_) {}
    return {
      'isConnected': false,
      'deviceName': 'Speaker HP / Kabel',
      'deviceType': 'INTERNAL',
    };
  }

  Future<List<RecordingItem>> loadSavedRecordings() async {
    final dirPath = await _getRecordingsDirectoryPath();
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];

    final List<FileSystemEntity> entities = await dir.list().toList();
    final List<RecordingItem> items = [];

    for (var entity in entities) {
      if (entity is File && entity.path.endsWith('.wav')) {
        items.add(RecordingItem.fromFile(entity));
      }
    }

    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  Future<bool> deleteRecording(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
    } catch (_) {}
    return false;
  }
}
