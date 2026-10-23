import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/audio_service.dart';
import 'widgets/recordings_sheet.dart';
import 'widgets/visualizer_wave.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const JblMicApp());
}

class JblMicApp extends StatelessWidget {
  const JblMicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JBL Live Mic & Recorder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0C0E14),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF5E1E), // JBL Iconic Vibrant Orange
          secondary: Color(0xFF00E5FF), // Cyber Cyan
          surface: Color(0xFF161922),
        ),
        fontFamily: 'sans-serif',
      ),
      home: const MainMicScreen(),
    );
  }
}

class MainMicScreen extends StatefulWidget {
  const MainMicScreen({super.key});

  @override
  State<MainMicScreen> createState() => _MainMicScreenState();
}

class _MainMicScreenState extends State<MainMicScreen>
    with SingleTickerProviderStateMixin {
  final AudioService _audioService = AudioService();

  bool _isMicActive = false;
  bool _isRecording = false;
  double _gain = 1.0;
  double _noiseGateThreshold = 0.035;
  bool _noiseSuppression = true;
  bool _echoCancellation = true;
  bool _bandpassFilter = true;

  double _currentAudioLevel = 0.0;
  bool _isGateOpen = false;
  StreamSubscription? _metricsSubscription;

  // Bluetooth info
  bool _isBtConnected = false;
  String _btDeviceName = 'Memeriksa perangkat...';

  // Recording timer
  Timer? _recordingTimer;
  int _recordingSeconds = 0;

  // Animation controller for pulsing glow
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _initApp();
  }

  Future<void> _initApp() async {
    await _checkBluetoothStatus();

    // Listen to real-time audio metrics (amplitude + gate status)
    _metricsSubscription = _audioService.audioMetricsStream.listen((metrics) {
      if (mounted) {
        setState(() {
          _currentAudioLevel = metrics.level;
          _isGateOpen = metrics.isGateOpen;
        });
      }
    });
  }

  Future<void> _checkBluetoothStatus() async {
    final status = await _audioService.getBluetoothStatus();
    if (mounted) {
      setState(() {
        _isBtConnected = status['isConnected'] as bool? ?? false;
        _btDeviceName =
            status['deviceName'] as String? ?? 'Speaker HP / Kabel';
      });
    }
  }

  Future<void> _toggleLiveMic() async {
    HapticFeedback.heavyImpact();

    if (!_isMicActive) {
      final hasPerm = await _audioService.checkAndRequestPermissions();
      if (!hasPerm) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Izin mikrofon diperlukan untuk menggunakan fitur ini.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      final success = await _audioService.startLiveMic();
      if (success) {
        await _audioService.setGain(_gain);
        await _audioService.setNoiseGateThreshold(_noiseGateThreshold);
        await _audioService.setBandpassFilter(_bandpassFilter);
        await _audioService.setNoiseSuppression(_noiseSuppression);
        await _audioService.setEchoCancellation(_echoCancellation);
        if (mounted) {
          setState(() => _isMicActive = true);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Gagal memulai audio stream. Pastikan mic tidak dipakai aplikasi lain.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } else {
      if (_isRecording) {
        await _toggleRecording();
      }

      await _audioService.stopLiveMic();
      if (mounted) {
        setState(() {
          _isMicActive = false;
          _currentAudioLevel = 0.0;
          _isGateOpen = false;
        });
      }
    }
  }

  Future<void> _toggleRecording() async {
    HapticFeedback.mediumImpact();

    if (!_isRecording) {
      if (!_isMicActive) {
        final started = await _audioService.startLiveMic();
        if (!started) return;
        setState(() => _isMicActive = true);
      }

      final path = await _audioService.startRecording();
      if (path != null) {
        setState(() {
          _isRecording = true;
          _recordingSeconds = 0;
        });
        _recordingTimer =
            Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) {
            setState(() => _recordingSeconds++);
          }
        });
      }
    } else {
      _recordingTimer?.cancel();
      _recordingTimer = null;
      final savedPath = await _audioService.stopRecording();
      setState(() => _isRecording = false);

      if (mounted && savedPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rekaman berhasil disimpan: ${savedPath.split('/').last}'),
            backgroundColor: const Color(0xFF00E5FF),
            action: SnackBarAction(
              label: 'Buka',
              textColor: Colors.black,
              onPressed: _openRecordingsSheet,
            ),
          ),
        );
      }
    }
  }

  void _onGainChanged(double val) {
    setState(() => _gain = val);
    _audioService.setGain(val);
  }

  void _onNoiseGateChanged(double val) {
    setState(() => _noiseGateThreshold = val);
    _audioService.setNoiseGateThreshold(val);
  }

  void _onBandpassChanged(bool val) {
    setState(() => _bandpassFilter = val);
    _audioService.setBandpassFilter(val);
  }

  void _onNoiseSuppressionChanged(bool val) {
    setState(() => _noiseSuppression = val);
    _audioService.setNoiseSuppression(val);
  }

  void _onEchoCancellationChanged(bool val) {
    setState(() => _echoCancellation = val);
    _audioService.setEchoCancellation(val);
  }

  void _openRecordingsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => RecordingsSheet(audioService: _audioService),
    );
  }

  String _formatTimer(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _metricsSubscription?.cancel();
    _recordingTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5E1E),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'JBL',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 1.5,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'LIVE MIC & RECORDER',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                letterSpacing: 1.1,
                color: Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Daftar Rekaman',
            icon: const Icon(Icons.library_music_outlined, color: Colors.white),
            onPressed: _openRecordingsSheet,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Bluetooth Status Bar
              _buildBluetoothCard(),

              const SizedBox(height: 20),

              // Central Mic Power Button with Glow
              _buildMainMicButton(),

              const SizedBox(height: 14),

              // Status Label
              Text(
                _isMicActive
                    ? 'SUARA AKTIF DISALURKAN KE SPEAKER'
                    : 'KETUK UNTUK MENYALAKAN MIC',
                style: TextStyle(
                  color: _isMicActive
                      ? const Color(0xFF00E5FF)
                      : Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),

              const SizedBox(height: 16),

              // Audio Waveform Visualizer
              VisualizerWave(
                level: _currentAudioLevel,
                isActive: _isMicActive,
                isGateOpen: _isGateOpen,
              ),

              const SizedBox(height: 20),

              // Smart Noise Gate Card (CRITICAL FOR BLOCKING DISTANT NOISE & HOWLING)
              _buildNoiseGateCard(),

              const SizedBox(height: 16),

              // Gain Control Card
              _buildGainCard(),

              const SizedBox(height: 16),

              // DSP Filters & Anti-Feedback Card
              _buildDspFiltersCard(),

              const SizedBox(height: 16),

              // Recording Card
              _buildRecordingCard(),

              const SizedBox(height: 16),

              // Anti-Feedback Safety Note
              _buildSafetyTipCard(),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBluetoothCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161922),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isBtConnected
              ? const Color(0xFF00E5FF).withValues(alpha: 0.4)
              : Colors.white10,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isBtConnected
                  ? const Color(0xFF00E5FF).withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.06),
            ),
            child: Icon(
              _isBtConnected ? Icons.bluetooth_audio : Icons.bluetooth_searching,
              color: _isBtConnected ? const Color(0xFF00E5FF) : Colors.white38,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isBtConnected
                            ? const Color(0xFF00E5FF)
                            : Colors.amberAccent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isBtConnected ? 'OUTPUT BLUETOOTH' : 'AUDIO STANDAR',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: _isBtConnected
                            ? const Color(0xFF00E5FF)
                            : Colors.amberAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _btDeviceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Perbarui Status Bluetooth',
            icon: const Icon(Icons.refresh, color: Colors.white54, size: 20),
            onPressed: _checkBluetoothStatus,
          ),
        ],
      ),
    );
  }

  Widget _buildMainMicButton() {
    return GestureDetector(
      onTap: _toggleLiveMic,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_isMicActive)
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFF5E1E).withValues(alpha: 0.2),
                ),
              ),
            ),

          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: _isMicActive
                    ? [const Color(0xFFFF5E1E), const Color(0xFFFF8A00)]
                    : [const Color(0xFF232733), const Color(0xFF1A1D27)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: _isMicActive
                  ? [
                      BoxShadow(
                        color: const Color(0xFFFF5E1E).withValues(alpha: 0.6),
                        blurRadius: 30,
                        spreadRadius: 2,
                      )
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ],
            ),
            child: Center(
              child: Container(
                width: 116,
                height: 116,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isMicActive
                      ? const Color(0xFFFF5E1E)
                      : const Color(0xFF141720),
                  border: Border.all(
                    color: _isMicActive
                        ? Colors.white.withValues(alpha: 0.3)
                        : Colors.white12,
                    width: 2,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isMicActive ? Icons.mic : Icons.mic_off,
                      size: 42,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isMicActive ? 'LIVE' : 'OFF',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.0,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoiseGateCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF161922),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isMicActive && _isGateOpen
              ? const Color(0xFF00E5FF).withValues(alpha: 0.6)
              : Colors.white10,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.shield_outlined, color: Color(0xFF00E5FF), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Peredam Suara Jauh & Denging',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              // Live Gate State Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _isMicActive
                      ? (_isGateOpen
                          ? const Color(0xFF00E5FF).withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.08))
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isMicActive && _isGateOpen
                        ? const Color(0xFF00E5FF)
                        : Colors.white24,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isMicActive
                            ? (_isGateOpen ? const Color(0xFF00E5FF) : Colors.white38)
                            : Colors.white24,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      !_isMicActive
                          ? 'STANDBY'
                          : (_isGateOpen ? 'BICARA TERDETEKSI' : 'SUARA JAUH DIBLOKIR'),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _isMicActive && _isGateOpen
                            ? const Color(0xFF00E5FF)
                            : Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Ambang Batas Suara (Noise Gate Threshold):',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 6),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF00E5FF),
              inactiveTrackColor: Colors.white12,
              thumbColor: const Color(0xFF00E5FF),
              overlayColor: const Color(0xFF00E5FF).withValues(alpha: 0.2),
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Slider(
              value: _noiseGateThreshold,
              min: 0.01,
              max: 0.12,
              divisions: 22,
              onChanged: _onNoiseGateChanged,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Peka (0.01)',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
                TextButton(
                  onPressed: () => _onNoiseGateChanged(0.035),
                  child: const Text('Rekomendasi (0.035)',
                      style: TextStyle(color: Color(0xFF00E5FF), fontSize: 12)),
                ),
                const Text('Ketat (0.12)',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Hanya meloloskan suara saat berbicara dekat HP. Saat hening, suara dari jauh dan dengungan otomatis dibisukan total.',
            style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.3),
          ),
        ],
      ),
    );
  }

  Widget _buildGainCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF161922),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.volume_up, color: Color(0xFFFF5E1E), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Sensitivitas Mic / Volume Penguat',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5E1E).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_gain.toStringAsFixed(1)}x',
                  style: const TextStyle(
                    color: Color(0xFFFF5E1E),
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFFFF5E1E),
              inactiveTrackColor: Colors.white12,
              thumbColor: const Color(0xFFFF5E1E),
              overlayColor: const Color(0xFFFF5E1E).withValues(alpha: 0.2),
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Slider(
              value: _gain,
              min: 0.5,
              max: 3.5,
              divisions: 30,
              onChanged: _onGainChanged,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('0.5x (Halus)',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
                TextButton(
                  onPressed: () => _onGainChanged(1.0),
                  child: const Text('Reset (1.0x)',
                      style: TextStyle(color: Color(0xFF00E5FF), fontSize: 12)),
                ),
                const Text('3.5x (Ekstra)',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDspFiltersCard() {
    return Material(
      color: const Color(0xFF161922),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Colors.white10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.tune, color: Color(0xFF00E5FF), size: 20),
                SizedBox(width: 8),
                Text(
                  'Filter DSP Anti-Melengking',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Filter Anti-Melengking (Speech Bandpass)',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Memotong frekuensi tinggi 4.2kHz yang memicu dengungan',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              value: _bandpassFilter,
              activeThumbColor: const Color(0xFF00E5FF),
              onChanged: _onBandpassChanged,
            ),
            const Divider(color: Colors.white10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Peredam Bising (Noise Suppression)',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Meredam desis angin dan dengung kipas ruangan',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              value: _noiseSuppression,
              activeThumbColor: const Color(0xFF00E5FF),
              onChanged: _onNoiseSuppressionChanged,
            ),
            const Divider(color: Colors.white10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Anti-Feedback (Acoustic Echo Canceler)',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Peredam echo akustik perangkat keras',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              value: _echoCancellation,
              activeThumbColor: const Color(0xFF00E5FF),
              onChanged: _onEchoCancellationChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF161922),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isRecording
              ? Colors.redAccent.withValues(alpha: 0.5)
              : Colors.white10,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isRecording
                  ? Colors.redAccent.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.06),
            ),
            child: Icon(
              _isRecording ? Icons.fiber_manual_record : Icons.mic_none,
              color: _isRecording ? Colors.redAccent : Colors.white60,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isRecording ? 'Merekam Suara...' : 'Perekam Suara',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _isRecording
                      ? 'Durasi: ${_formatTimer(_recordingSeconds)}'
                      : 'Simpan suara ke file WAV beresolusi tinggi',
                  style: TextStyle(
                    color: _isRecording ? Colors.redAccent : Colors.white38,
                    fontSize: 12,
                    fontWeight: _isRecording ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  _isRecording ? Colors.redAccent : const Color(0xFFFF5E1E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: _toggleRecording,
            child: Text(
              _isRecording ? 'Stop' : 'Rekam',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyTipCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.tips_and_updates_outlined, color: Colors.amberAccent, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tips Menghindari Denging:\n1. Bicaralah mendekati mikrofon bawah HP (sekitar 10-20 cm).\n2. Atur slider "Peredam Suara Jauh" ke posisi Rekomendasi (0.035) atau lebih tinggi jika ruangan bising.\n3. Jangan mengarahkan mic HP langsung menghadap ke kisi speaker JBL Go 3.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
