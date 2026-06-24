import 'dart:math' as math;

import 'package:flutter/physics.dart';

/// A named spring "feel" for the motion widgets ([RestageMotion],
/// [RestageStagger]).
///
/// Presets are the primary, declarative surface — a developer picks a feel by
/// name rather than tuning physics. Each preset is defined by an Apple-style
/// (duration, bounce) pair (see [springDescriptionFor]); the spring widgets
/// expose optional `duration`/`bounce` overrides as an escape hatch for the
/// rare case a preset is not quite right.
///
/// The values mirror the spring vocabulary established by the wider Flutter
/// motion ecosystem (e.g. the `motor` package's `CupertinoMotion` presets), so
/// the feels are familiar and calibrated rather than invented.
enum RestageSpring {
  /// A general-purpose, critically damped settle with no overshoot. The
  /// sensible default. (500ms, bounce 0.0)
  smooth,

  /// A lively settle with a small, tasteful overshoot. (500ms, bounce 0.15)
  snappy,

  /// A playful, clearly visible overshoot. (500ms, bounce 0.30)
  bouncy,

  /// A fast, responsive feel for elements that should track quickly.
  /// (150ms, bounce 0.14)
  interactive,

  /// A slow, soft settle for unhurried content. (800ms, bounce 0.0)
  gentle,

  /// A quick, no-overshoot snap for layout-like positional settles.
  /// (250ms, bounce 0.0)
  stiff,
}

/// The (durationMs, bounce) calibration for each [RestageSpring] preset.
const Map<RestageSpring, (int, double)> _kPresetTuning = {
  RestageSpring.smooth: (500, 0.0),
  RestageSpring.snappy: (500, 0.15),
  RestageSpring.bouncy: (500, 0.30),
  RestageSpring.interactive: (150, 0.14),
  RestageSpring.gentle: (800, 0.0),
  RestageSpring.stiff: (250, 0.0),
};

// Fail-safe clamps. No wire value (a preset, an escape-hatch override, or a
// controller duration decoded from a paywall blob) may produce a non-settling
// spring or a non-positive animation duration — a zero/negative damping spring
// oscillates forever, and a zero/negative controller duration asserts in
// AnimationController (and divides by zero in a repeating animation). These
// bounds guarantee a finite, positive-damping, settling spring and a finite,
// strictly-positive duration for any input.
const int _kMinDurationMicros =
    50 * Duration.microsecondsPerMillisecond; // 50ms
const int _kMaxDurationMicros = 10 * Duration.microsecondsPerSecond; // 10s
const double _kMinDurationSeconds =
    _kMinDurationMicros / Duration.microsecondsPerSecond;
const double _kMaxDurationSeconds =
    _kMaxDurationMicros / Duration.microsecondsPerSecond;
const double _kMaxBounce = 0.99; // bounce 1.0 => ratio 0 => undamped (runaway)
const double _kMinBounce = -0.99; // bounce -1.0 => 1/(1+bounce) diverges

/// Clamps a wire-supplied animation [duration] to the safe, strictly-positive
/// range shared across the motion widgets, falling back to [fallback] when it
/// is null. A null/zero/negative/absurd duration would otherwise assert in (or
/// divide by zero inside) an [AnimationController]; this guarantees every motion
/// controller is built with a finite, positive duration regardless of the blob.
Duration sanitizeMotionDuration(
  Duration? duration, {
  required Duration fallback,
}) {
  final micros = (duration ?? fallback)
      .inMicroseconds
      .clamp(_kMinDurationMicros, _kMaxDurationMicros);
  return Duration(microseconds: micros);
}

/// Builds the Flutter [SpringDescription] for a [RestageSpring] preset,
/// optionally overriding the preset's duration and/or bounce.
///
/// ## The duration+bounce model (mass = 1)
///
/// This implements Apple's designer-facing spring parameterization (the same
/// model Flutter adopted in `SpringDescription.withDurationAndBounce`, which we
/// do not call directly to keep the package's Flutter floor low). With mass
/// fixed at 1:
///
/// ```
/// stiffness    = (2π / durationSeconds)²
/// dampingRatio = 1 − bounce               (bounce ≥ 0, the underdamped side)
/// dampingRatio = 1 / (1 + bounce)         (bounce < 0, the overdamped side)
/// ```
///
/// `bounce` is intuitive: 0 settles with no overshoot (critically damped),
/// positive overshoots (bouncier), negative is sluggish. `duration` is the
/// perceptual settle time.
///
/// Mass = 1 is deliberate: the Flutter 3.32 underdamped-formula correction only
/// changed springs with mass ≠ 1, so a mass-1 spring behaves identically across
/// Flutter 3.24 → current. The result feeds [SpringSimulation].
///
/// `durationOverride` and `bounceOverride` are independent: a null override
/// keeps the preset's value for that field, a non-null one replaces it. Both
/// are clamped to a safe range so no input can yield a non-settling spring.
SpringDescription springDescriptionFor(
  RestageSpring preset, {
  Duration? durationOverride,
  double? bounceOverride,
}) {
  final (presetMs, presetBounce) = _kPresetTuning[preset]!;

  // Resolve to microseconds first so the preset (ms) and override (a Duration)
  // share one unit, then convert once.
  final durationMicros = durationOverride?.inMicroseconds ??
      presetMs * Duration.microsecondsPerMillisecond;
  final durationSeconds = (durationMicros / Duration.microsecondsPerSecond)
      .clamp(_kMinDurationSeconds, _kMaxDurationSeconds);
  final bounce =
      (bounceOverride ?? presetBounce).clamp(_kMinBounce, _kMaxBounce);

  final stiffness = math.pow(2 * math.pi / durationSeconds, 2).toDouble();
  final dampingRatio = bounce >= 0 ? 1 - bounce : 1 / (1 + bounce);

  return SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: stiffness,
    ratio: dampingRatio,
  );
}
