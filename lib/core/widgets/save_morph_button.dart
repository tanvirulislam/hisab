import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import 'motion.dart';

enum SaveButtonPhase { idle, busy, done }

/// A full-width save button that shrinks to a circle while saving, then turns
/// green and draws a tick (D20). [onDone] runs once the tick is drawn: that is
/// when the screen should close, so the user sees that it worked.
class SaveMorphButton extends StatefulWidget {
  const SaveMorphButton({
    super.key,
    required this.label,
    required this.phase,
    required this.onPressed,
    required this.onDone,
  });

  final String label;
  final SaveButtonPhase phase;
  final VoidCallback onPressed;
  final VoidCallback onDone;

  static const height = 52.0;

  @override
  State<SaveMorphButton> createState() => _SaveMorphButtonState();
}

class _SaveMorphButtonState extends State<SaveMorphButton> with SingleTickerProviderStateMixin {
  static const _shrink = Duration(milliseconds: 280);

  // The tick waits for the circle to finish shrinking, then draws.
  late final AnimationController _tick = AnimationController(vsync: this, duration: const Duration(milliseconds: 560));
  late final Animation<double> _draw = CurvedAnimation(
    parent: _tick,
    curve: const Interval(0.45, 1, curve: Motion.enter),
  );

  @override
  void didUpdateWidget(SaveMorphButton old) {
    super.didUpdateWidget(old);
    if (widget.phase == SaveButtonPhase.done && old.phase != SaveButtonPhase.done) {
      if (Motion.reduced(context)) {
        _tick.value = 1;
        WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone());
      } else {
        _tick.forward(from: 0).then((_) => widget.onDone());
      }
    } else if (widget.phase == SaveButtonPhase.idle) {
      _tick.value = 0;
    }
  }

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = widget.phase == SaveButtonPhase.done;
    final round = widget.phase != SaveButtonPhase.idle;
    final background = done ? context.financeColors.income : scheme.primary;
    return LayoutBuilder(
      // heightFactor 1: in a bottom bar, a plain Center would take the whole screen height.
      builder: (context, box) => Align(
        heightFactor: 1,
        child: AnimatedContainer(
          duration: Motion.of(context, _shrink),
          curve: Motion.enter,
          width: round ? SaveMorphButton.height : box.maxWidth,
          height: SaveMorphButton.height,
          child: Material(
            color: background,
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: round ? null : widget.onPressed,
              child: Center(
                child: switch (widget.phase) {
                  SaveButtonPhase.idle => FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check, color: scheme.onPrimary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          widget.label,
                          maxLines: 1,
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onPrimary),
                        ),
                      ],
                    ),
                  ),
                  SaveButtonPhase.busy => SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: scheme.onPrimary),
                  ),
                  SaveButtonPhase.done => Semantics(
                    label: widget.label,
                    child: CustomPaint(size: const Size.square(26), painter: _TickPainter(_draw, Colors.white)),
                  ),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tick drawn along its length as [progress] runs from 0 to 1.
class _TickPainter extends CustomPainter {
  _TickPainter(this.progress, this.color) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.2, size.height * 0.52)
      ..lineTo(size.width * 0.41, size.height * 0.72)
      ..lineTo(size.width * 0.8, size.height * 0.3);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * progress.value), paint);
    }
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.color != color;
}
