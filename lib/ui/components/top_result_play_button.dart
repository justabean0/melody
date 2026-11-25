import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/song.dart';
import '../../providers/playback_provider.dart';

/// Synchronized Top Result play/pause button with a flush theme-colored progress ring.
///
/// Rebuilds are tightly scoped so position ticks only repaint the circular ring
/// without rebuilding the surrounding SearchScreen or Top Result card.
class TopResultPlayButton extends StatelessWidget {
  final Song song;

  const TopResultPlayButton({
    super.key,
    required this.song,
  });

  static const double _buttonDiameter = 42.0;
  static const double _touchTargetSize = 48.0;
  static const double _ringStrokeWidth = 2.8;

  @override
  Widget build(BuildContext context) {
    return Selector<PlaybackProvider, ({bool isCurrent, bool isPlaying})>(
      selector: (_, playback) {
        final isCurrent = playback.currentSong?.id == song.id;
        return (
          isCurrent: isCurrent,
          isPlaying: isCurrent && playback.isPlaying,
        );
      },
      builder: (context, state, _) {
        return SizedBox(
          width: _touchTargetSize,
          height: _touchTargetSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              IconButton.filledTonal(
                icon: Icon(
                  state.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
                iconSize: 26,
                tooltip: state.isPlaying ? 'Pause' : 'Play',
                style: IconButton.styleFrom(
                  fixedSize: const Size(_buttonDiameter, _buttonDiameter),
                  minimumSize: const Size(_buttonDiameter, _buttonDiameter),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
                onPressed: () {
                  final playback = context.read<PlaybackProvider>();
                  if (playback.currentSong?.id == song.id) {
                    playback.togglePlayPause();
                  } else {
                    playback.playSong(song);
                  }
                },
              ),
              if (state.isCurrent)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: _ScopedProgressRingHost(
                      buttonDiameter: _buttonDiameter,
                      strokeWidth: _ringStrokeWidth,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ScopedProgressRingHost extends StatelessWidget {
  final double buttonDiameter;
  final double strokeWidth;

  const _ScopedProgressRingHost({
    required this.buttonDiameter,
    required this.strokeWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<PlaybackProvider,
        ({Duration position, Duration duration, bool isLoading})>(
      selector: (_, playback) => (
        position: playback.position,
        duration: playback.duration,
        isLoading: playback.isLoading,
      ),
      builder: (_, playbackState, __) {
        final progress = playbackState.duration > Duration.zero
            ? (playbackState.position.inMilliseconds /
                    playbackState.duration.inMilliseconds)
                .clamp(0.0, 1.0)
            : 0.0;
        return _TopResultProgressRing(
          progress: progress,
          isLoading: playbackState.isLoading,
          buttonDiameter: buttonDiameter,
          strokeWidth: strokeWidth,
        );
      },
    );
  }
}

class _TopResultProgressRing extends StatefulWidget {
  final double progress;
  final bool isLoading;
  final double buttonDiameter;
  final double strokeWidth;

  const _TopResultProgressRing({
    required this.progress,
    required this.isLoading,
    required this.buttonDiameter,
    required this.strokeWidth,
  });

  @override
  State<_TopResultProgressRing> createState() => _TopResultProgressRingState();
}

class _TopResultProgressRingState extends State<_TopResultProgressRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinController;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.isLoading) {
      _spinController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _TopResultProgressRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLoading && !_spinController.isAnimating) {
      _spinController.repeat();
    } else if (!widget.isLoading && _spinController.isAnimating) {
      _spinController.stop();
    }
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final trackColor = primaryColor.withAlpha(51);

    if (widget.isLoading) {
      return AnimatedBuilder(
        animation: _spinController,
        builder: (_, __) => CustomPaint(
          painter: TopResultProgressRingPainter(
            progress: widget.progress,
            isIndeterminate: true,
            rotationFraction: _spinController.value,
            activeColor: primaryColor,
            trackColor: trackColor,
            innerButtonDiameter: widget.buttonDiameter,
            strokeWidth: widget.strokeWidth,
          ),
        ),
      );
    }

    return CustomPaint(
      painter: TopResultProgressRingPainter(
        progress: widget.progress,
        isIndeterminate: false,
        rotationFraction: 0.0,
        activeColor: primaryColor,
        trackColor: trackColor,
        innerButtonDiameter: widget.buttonDiameter,
        strokeWidth: widget.strokeWidth,
      ),
    );
  }
}

/// CustomPainter drawing a flush circular progress ring tightly hugging the button border.
class TopResultProgressRingPainter extends CustomPainter {
  final double progress;
  final bool isIndeterminate;
  final double rotationFraction;
  final Color activeColor;
  final Color trackColor;
  final double innerButtonDiameter;
  final double strokeWidth;

  const TopResultProgressRingPainter({
    required this.progress,
    required this.isIndeterminate,
    required this.rotationFraction,
    required this.activeColor,
    required this.trackColor,
    required this.innerButtonDiameter,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Position inner edge of stroke directly on innerButtonDiameter / 2 with zero gap.
    final ringRadius = (innerButtonDiameter / 2) + (strokeWidth / 2);
    final rect = Rect.fromCircle(center: center, radius: ringRadius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, ringRadius, trackPaint);

    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    if (isIndeterminate) {
      final startAngle = (-math.pi / 2) + (rotationFraction * 2 * math.pi);
      const sweepAngle = math.pi * 0.75;
      canvas.drawArc(rect, startAngle, sweepAngle, false, activePaint);
    } else if (progress > 0.0) {
      const startAngle = -math.pi / 2;
      final sweepAngle = 2 * math.pi * progress.clamp(0.0, 1.0);
      canvas.drawArc(rect, startAngle, sweepAngle, false, activePaint);
    }
  }

  @override
  bool shouldRepaint(covariant TopResultProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isIndeterminate != isIndeterminate ||
        oldDelegate.rotationFraction != rotationFraction ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.innerButtonDiameter != innerButtonDiameter ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
