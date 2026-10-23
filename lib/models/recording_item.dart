import 'dart:io';
import 'package:intl/intl.dart';

class RecordingItem {
  final String path;
  final String name;
  final DateTime createdAt;
  final int sizeBytes;

  RecordingItem({
    required this.path,
    required this.name,
    required this.createdAt,
    required this.sizeBytes,
  });

  factory RecordingItem.fromFile(File file) {
    final stat = file.statSync();
    return RecordingItem(
      path: file.path,
      name: file.uri.pathSegments.last,
      createdAt: stat.modified,
      sizeBytes: stat.size,
    );
  }

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String get formattedDate {
    return DateFormat('dd MMM yyyy, HH:mm:ss').format(createdAt);
  }
}
