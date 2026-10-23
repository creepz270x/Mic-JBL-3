import 'dart:math';
import 'package:flutter/material.dart';

class VisualizerWave extends StatefulWidget {
  final double level; // 0.0 to 1.0
  final bool isActive;
  final bool isGateOpen;

  const VisualizerWave({
    super.key,
    required this.level,
    required this.isActive,
    required this.isGateOpen,
  });

  @override
  State<VisualizerWave> createState() => _VisualizerWaveState();
}

class _VisualizerWaveState extends State<VisualizerWave>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  final List<double> _barHeights = List.filled(24, 0.05);
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 60),
    )..addListener(_updateBars);
    _animController.repeat();
  }

  void _updateBars() {
    if (!mounted) return;
    setState(() {
      for (int i = 0; i < _barHeights.length; i++) {
        if (widget.isActive && widget.isGateOpen) {
          // Voice active & gate open
          final baseLevel = widget.level;
          final noise = (_random.nextDouble() * 0.3) - 0.15;
          final target = (baseLevel * 1.6 + noise).clamp(0.12, 1.0);
          _barHeights[i] = _barHeights[i] + (target - _barHeights[i]) * 0.4;
        } else if (widget.isActive && !widget.isGateOpen) {
          // Mic is on, but gate is closed (ambient room noise blocked)
          _barHeights[i] = _barHeights[i] + (0.04 - _barHeights[i]) * 0.25;
        } else {
          // Idle state
          _barHeights[i] = _barHeights[i] + (0.04 - _barHeights[i]) * 0.2;
        }
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF161922),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isActive
              ? (widget.isGateOpen
                  ? const Color(0xFFFF5E1E).withValues(alpha: 0.6)
                  : const Color(0xFF00E5FF).withValues(alpha: 0.25))
              : Colors.white10,
        ),
        boxShadow: widget.isActive && widget.isGateOpen
            ? [
                BoxShadow(
                  color: const Color(0xFFFF5E1E).withValues(alpha: 0.2),
                  blurRadius: 16,
                  spreadRadius: 1,
                )
              ]
            : [],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(_barHeights.length, (index) {
          final heightFactor = _barHeights[index];
          final color = widget.isActive
              ? (widget.isGateOpen
                  ? Color.lerp(
                      const Color(0xFF00E5FF),
                      const Color(0xFFFF5E1E),
                      heightFactor,
                    )!
                  : Colors.white24)
              : Colors.white12;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 50),
            width: 4,
            height: 54 * heightFactor,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
              boxShadow: widget.isActive && widget.isGateOpen && heightFactor > 0.4
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.6),
                        blurRadius: 6,
                        spreadRadius: 1,
                      )
                    ]
                  : [],
            ),
          );
        }),
      ),
    );
  }
}
