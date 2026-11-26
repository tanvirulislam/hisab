import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/presentation/app_formats.dart';
import '../utils/money.dart';

/// Animation timings and small animated building blocks (D20).
///
/// Every animation takes its duration from [Motion.of], so the system
/// "remove animations" setting turns them all off: they jump to the end.
abstract final class Motion {
  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [d], or zero when the user asked the system for no animations.
  static Duration of(BuildContext context, Duration d) => reduced(context) ? Duration.zero : d;

  /// Fast out, gentle settle: the curve for things arriving on screen.
  static const Curve enter = Curves.easeOutCubic;

  /// [delay] then [length], as one curve over the whole time, so a single
  /// implicit animation can start late without a timer.
  static Curve delayed(Duration delay, Duration length, {Curve curve = enter}) {
    final total = delay + length;
    if (total == Duration.zero || delay == Duration.zero) return curve;
    return Interval(delay.inMicroseconds / total.inMicroseconds, 1, curve: curve);
  }
}

/// A money figure that counts up from zero when it first appears and runs
/// to the new value when it changes, instead of jumping (D20).
class CountUpMoney extends ConsumerWidget {
  const CountUpMoney({super.key, required this.value, this.style, this.format, this.maxLines});

  final Money value;
  final TextStyle? style;

  /// How to show an amount; the app's money format when null.
  final String Function(Money)? format;
  final int? maxLines;

  static const duration = Duration(milliseconds: 800);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final show = format ?? ref.watch(appFormatsProvider).money.format;
    final end = value.paisa.toDouble();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: end),
      duration: Motion.of(context, duration),
      curve: Motion.enter,
      builder: (context, v, _) {
        // Whole taka while moving, so no paisa flicker; the exact amount at the end.
        final shown = v == end ? value : Money((v / 100).round() * 100);
        return Text(
          show(shown),
          maxLines: maxLines,
          style: (style ?? const TextStyle()).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        );
      },
    );
  }
}

/// Fades its child in while it rises a little, once, when it first appears.
/// [index] staggers siblings: each starts [step] after the one before.
class RiseIn extends StatelessWidget {
  const RiseIn({super.key, this.index = 0, required this.child});

  final int index;
  final Widget child;

  static const step = Duration(milliseconds: 60);
  static const length = Duration(milliseconds: 420);

  @override
  Widget build(BuildContext context) {
    final delay = step * index;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.of(context, delay + length),
      curve: Motion.delayed(delay, length),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, 16 * (1 - t)), child: child),
      ),
    );
  }
}

/// Shakes its child sideways once, after [delay]: draws the eye to a figure
/// that is over its limit.
class ShakeOnce extends StatelessWidget {
  const ShakeOnce({super.key, this.delay = Duration.zero, required this.child});

  final Duration delay;
  final Widget child;

  static const length = Duration(milliseconds: 420);

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: Motion.of(context, delay + length),
    curve: Motion.delayed(delay, length, curve: Curves.linear),
    child: child,
    builder: (context, t, child) =>
        Transform.translate(offset: Offset(math.sin(t * math.pi * 4) * 4 * (1 - t), 0), child: child),
  );
}

/// Grows its child from 70% past full size and back, once, when it first
/// appears. Give it a new key to play it again.
class PopIn extends StatelessWidget {
  const PopIn({super.key, required this.child});

  final Widget child;

  static final _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.7, end: 1.22), weight: 55),
    TweenSequenceItem(tween: Tween(begin: 1.22, end: 1), weight: 45),
  ]);

  @override
  Widget build(BuildContext context) {
    const delay = Duration(milliseconds: 120);
    const length = Duration(milliseconds: 420);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.of(context, delay + length),
      curve: Motion.delayed(delay, length),
      child: child,
      builder: (context, t, child) => Transform.scale(scale: _scale.transform(t.clamp(0.0, 1.0)), child: child),
    );
  }
}

/// A list row that, when [animate] is set as it first appears, opens up
/// from nothing and starts tinted, fading to normal: "this one is new".
/// Rows already there pass `animate: false` and show as they are.
class RowReveal extends StatefulWidget {
  const RowReveal({super.key, required this.animate, required this.child});

  final bool animate;
  final Widget child;

  @override
  State<RowReveal> createState() => _RowRevealState();
}

class _RowRevealState extends State<RowReveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
    value: widget.animate ? 0 : 1,
  );
  late final Animation<double> _size = CurvedAnimation(
    parent: _c,
    curve: const Interval(0, 0.25, curve: Motion.enter),
  );
  late final Animation<double> _tint = CurvedAnimation(parent: _c, curve: const Interval(0.3, 1));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.animate && _c.value == 0) {
      if (Motion.reduced(context)) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tint = Theme.of(context).colorScheme.secondaryContainer;
    return SizeTransition(
      sizeFactor: _size,
      alignment: Alignment.topCenter,
      child: AnimatedBuilder(
        animation: _tint,
        child: widget.child,
        // A Material, not a ColoredBox: list tiles paint their ink on it.
        builder: (context, child) => Material(
          color: _c.isCompleted ? Colors.transparent : tint.withValues(alpha: 1 - _tint.value),
          child: child,
        ),
      ),
    );
  }
}
