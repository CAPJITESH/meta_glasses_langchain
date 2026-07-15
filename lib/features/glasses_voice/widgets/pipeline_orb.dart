/// lib/features/glasses_voice/widgets/pipeline_orb.dart
///
/// The pipeline's state made visible (Section 10): one animated orb whose
/// motion + color IS the assistant's status. Each [PipelinePhase] gets a
/// distinct treatment so the state is readable without reading text:
///
///   idle      — slow, dim breathing
///   listening — cyan pulse rings radiating inward attention
///   thinking  — amber orbiting arcs (deliberate "working" motion; a designed
///               wait feels shorter than a blank one)
///   speaking  — green equalizer bars breathing outward
///   error     — still coral ring, no motion
///
/// Pure Flutter animation (CustomPainter + one AnimationController); no
/// packages, no images.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../data/glasses_pipeline.dart';

class PipelineOrb extends StatefulWidget {
  const PipelineOrb({super.key, required this.phase, this.size = 180});

  final PipelinePhase phase;
  final double size;

  @override
  State<PipelineOrb> createState() => _PipelineOrbState();
}

class _PipelineOrbState extends State<PipelineOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _phaseColor(PhaseColors colors) {
    switch (widget.phase) {
      case PipelinePhase.idle:
        return colors.idle;
      case PipelinePhase.listening:
        return colors.listening;
      case PipelinePhase.thinking:
        return colors.thinking;
      case PipelinePhase.speaking:
        return colors.speaking;
      case PipelinePhase.error:
        return colors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<PhaseColors>()!;
    final color = _phaseColor(colors);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: _OrbPainter(
          phase: widget.phase,
          color: color,
          t: _controller.value,
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({required this.phase, required this.color, required this.t});

  final PipelinePhase phase;
  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    switch (phase) {
      case PipelinePhase.idle:
        _paintCore(canvas, center, r, breathe: 0.06, glow: 0.25);
      case PipelinePhase.listening:
        _paintCore(canvas, center, r, breathe: 0.04, glow: 0.5);
        _paintPulseRings(canvas, center, r);
      case PipelinePhase.thinking:
        _paintCore(canvas, center, r, breathe: 0.03, glow: 0.4);
        _paintOrbitArcs(canvas, center, r);
      case PipelinePhase.speaking:
        _paintCore(canvas, center, r, breathe: 0.02, glow: 0.4);
        _paintBars(canvas, center, r);
      case PipelinePhase.error:
        _paintCore(canvas, center, r, breathe: 0, glow: 0.3);
        canvas.drawCircle(
          center,
          r * 0.78,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = color,
        );
    }
  }

  /// Soft glowing core shared by every phase.
  void _paintCore(
    Canvas canvas,
    Offset center,
    double r, {
    required double breathe,
    required double glow,
  }) {
    final wave = math.sin(t * 2 * math.pi);
    final coreR = r * (0.42 + breathe * wave);

    canvas.drawCircle(
      center,
      coreR * 1.9,
      Paint()
        ..color = color.withValues(alpha: glow * 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
    );
    canvas.drawCircle(
      center,
      coreR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0.95),
            color.withValues(alpha: 0.55),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: coreR)),
    );
  }

  /// Listening: two rings expanding outward and fading, phase-offset.
  void _paintPulseRings(Canvas canvas, Offset center, double r) {
    for (final offset in [0.0, 0.5]) {
      final p = (t + offset) % 1.0;
      final ringR = r * (0.5 + 0.48 * p);
      canvas.drawCircle(
        center,
        ringR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1 - p)
          ..color = color.withValues(alpha: (1 - p) * 0.7),
      );
    }
  }

  /// Thinking: two arcs orbiting at different speeds.
  void _paintOrbitArcs(Canvas canvas, Offset center, double r) {
    final rect = Rect.fromCircle(center: center, radius: r * 0.72);
    final inner = Rect.fromCircle(center: center, radius: r * 0.58);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.5
      ..color = color.withValues(alpha: 0.9);
    canvas.drawArc(rect, t * 2 * math.pi, math.pi * 0.6, false, paint);
    canvas.drawArc(
      inner,
      -t * 2 * math.pi * 1.6,
      math.pi * 0.35,
      false,
      paint..color = color.withValues(alpha: 0.5),
    );
  }

  /// Speaking: five vertical bars, each bobbing on its own phase.
  void _paintBars(Canvas canvas, Offset center, double r) {
    const barCount = 5;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = r * 0.09
      ..color = color;
    final spread = r * 0.24;
    for (var i = 0; i < barCount; i++) {
      final x = center.dx + (i - (barCount - 1) / 2) * spread;
      final wave = math.sin((t * 2 + i * 0.35) * 2 * math.pi);
      final h = r * (0.28 + 0.22 * wave.abs());
      canvas.drawLine(
        Offset(x, center.dy - h),
        Offset(x, center.dy + h),
        paint..color = color.withValues(alpha: 0.6 + 0.4 * wave.abs()),
      );
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.t != t || old.phase != phase || old.color != color;
}
