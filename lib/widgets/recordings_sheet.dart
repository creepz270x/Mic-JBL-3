import 'dart:async';
import 'package:flutter/material.dart';
import '../models/recording_item.dart';
import '../services/audio_service.dart';

class RecordingsSheet extends StatefulWidget {
  final AudioService audioService;

  const RecordingsSheet({super.key, required this.audioService});

  @override
  State<RecordingsSheet> createState() => _RecordingsSheetState();
}

class _RecordingsSheetState extends State<RecordingsSheet> {
  List<RecordingItem> _recordings = [];
  bool _isLoading = true;

  String? _currentlyPlayingPath;
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    _loadRecordings();
  }

  Future<void> _loadRecordings() async {
    setState(() => _isLoading = true);
    final list = await widget.audioService.loadSavedRecordings();
    if (mounted) {
      setState(() {
        _recordings = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _togglePlay(RecordingItem item) async {
    if (_currentlyPlayingPath == item.path) {
      if (_isPlaying) {
        await widget.audioService.pauseAudio();
        setState(() => _isPlaying = false);
      } else {
        await widget.audioService.resumeAudio();
        setState(() => _isPlaying = true);
        _startProgressTimer();
      }
    } else {
      await widget.audioService.stopAudio();
      _progressTimer?.cancel();
      final success = await widget.audioService.playAudio(item.path);
      if (success) {
        setState(() {
          _currentlyPlayingPath = item.path;
          _isPlaying = true;
          _currentPosition = Duration.zero;
        });
        _startProgressTimer();
      }
    }
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 300), (t) async {
      final status = await widget.audioService.getPlaybackStatus();
      if (!mounted) {
        t.cancel();
        return;
      }
      final isPlaying = status['isPlaying'] as bool? ?? false;
      final pos = status['position'] as int? ?? 0;
      final dur = status['duration'] as int? ?? 0;

      setState(() {
        _isPlaying = isPlaying;
        _currentPosition = Duration(milliseconds: pos);
        if (dur > 0) {
          _totalDuration = Duration(milliseconds: dur);
        }
        if (!isPlaying && pos >= dur && dur > 0) {
          // Finished playback
          _currentlyPlayingPath = null;
          t.cancel();
        }
      });
    });
  }

  Future<void> _deleteRecording(RecordingItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E222D),
        title: const Text('Hapus Rekaman?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Rekaman "${item.name}" akan dihapus permanen.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (_currentlyPlayingPath == item.path) {
        await widget.audioService.stopAudio();
        _progressTimer?.cancel();
        _currentlyPlayingPath = null;
        _isPlaying = false;
      }
      await widget.audioService.deleteRecording(item.path);
      await _loadRecordings();
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    widget.audioService.stopAudio();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.only(top: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF12151D),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            width: 48,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.folder_special, color: Color(0xFFFF5E1E)),
                    const SizedBox(width: 10),
                    Text(
                      'Daftar Rekaman (${_recordings.length})',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white70),
                  onPressed: _loadRecordings,
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 24),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF5E1E)))
                : _recordings.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.mic_none, size: 64, color: Colors.white24),
                            SizedBox(height: 12),
                            Text(
                              'Belum ada rekaman suara',
                              style: TextStyle(
                                  color: Colors.white60, fontSize: 16),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Gunakan tombol Rekam di layar utama',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        itemCount: _recordings.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = _recordings[index];
                          final isPlayingThis =
                              _currentlyPlayingPath == item.path && _isPlaying;

                          return Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1B1E29),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isPlayingThis
                                    ? const Color(0xFFFF5E1E)
                                        .withValues(alpha: 0.5)
                                    : Colors.white.withValues(alpha: 0.06),
                              ),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    GestureDetector(
                                      onTap: () => _togglePlay(item),
                                      child: Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: LinearGradient(
                                            colors: isPlayingThis
                                                ? [
                                                    const Color(0xFFFF5E1E),
                                                    const Color(0xFFFF8A00)
                                                  ]
                                                : [
                                                    Colors.white12,
                                                    Colors.white10
                                                  ],
                                          ),
                                        ),
                                        child: Icon(
                                          isPlayingThis
                                              ? Icons.pause
                                              : Icons.play_arrow,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Text(
                                                item.formattedDate,
                                                style: const TextStyle(
                                                  color: Colors.white54,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                width: 3,
                                                height: 3,
                                                decoration: const BoxDecoration(
                                                  color: Colors.white38,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                item.formattedSize,
                                                style: const TextStyle(
                                                  color: Color(0xFF00E5FF),
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.white38),
                                      onPressed: () => _deleteRecording(item),
                                    ),
                                  ],
                                ),
                                if (_currentlyPlayingPath == item.path) ...[
                                  const SizedBox(height: 8),
                                  SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius: 6),
                                      overlayShape:
                                          const RoundSliderOverlayShape(
                                              overlayRadius: 10),
                                      trackHeight: 3,
                                      activeTrackColor: const Color(0xFFFF5E1E),
                                      inactiveTrackColor: Colors.white12,
                                      thumbColor: const Color(0xFFFF5E1E),
                                    ),
                                    child: Slider(
                                      value: _currentPosition.inMilliseconds
                                          .toDouble()
                                          .clamp(
                                            0.0,
                                            _totalDuration.inMilliseconds
                                                .toDouble()
                                                .clamp(
                                                    1.0, double.infinity),
                                          ),
                                      max: _totalDuration.inMilliseconds
                                          .toDouble()
                                          .clamp(1.0, double.infinity),
                                      onChanged: (val) {
                                        widget.audioService
                                            .seekAudio(val.toInt());
                                      },
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _formatDuration(_currentPosition),
                                          style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 11),
                                        ),
                                        Text(
                                          _formatDuration(_totalDuration),
                                          style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
