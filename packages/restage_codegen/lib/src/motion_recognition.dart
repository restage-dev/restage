import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';

/// The motion adopt-target vocabulary and deferral message.
///
/// Imperative animation — an `AnimationController`, a directly-constructed
/// Flutter spring, or a package-backed motion system (e.g. `motor` / `cue`) —
/// cannot be transpiled to a declarative paywall blob. Unlike the
/// number/currency idiom, it also cannot be **auto-substituted**: an
/// `AnimationController` has no by-construction equivalent that would pass the
/// semantic-rewrite oracle, so the catalog motion widgets are only ever NAMED
/// in a deferral diagnostic (manual adoption), never silently swapped in.
///
/// This file is the single source of the adopt-target vocabulary, the message,
/// and the element-gated spring recogniser — pure, with no dependency on the
/// deferral sites. The wiring that emits the message where imperative animation
/// is classified is integrated separately.

/// The motion widget that replaces a spring/physics entrance.
const String kRestageSpringWidget = 'RestageMotion';

/// The motion widget that replaces a simple fade-in entrance.
const String kRestageFadeWidget = 'RestageFadeIn';

/// The motion widget that replaces a looping attention animation.
const String kRestagePulseWidget = 'RestagePulse';

/// The motion widget that replaces a staggered list reveal.
const String kRestageStaggerWidget = 'RestageStagger';

/// The full adopt-target vocabulary.
const Set<String> kMotionAdoptTargets = {
  kRestageSpringWidget,
  kRestageFadeWidget,
  kRestagePulseWidget,
  kRestageStaggerWidget,
};

/// The `State`-field types that signal imperative animation — an
/// `AnimationController` and its companions. Element-gated on `package:flutter/`
/// (see [isImperativeMotionType]).
const Set<String> _kImperativeMotionTypeNames = {
  'AnimationController',
  'Animation',
  'CurvedAnimation',
  'Ticker',
};

/// Whether [type] is an imperative-motion controller type — an
/// `AnimationController` / `Animation` / `CurvedAnimation` / `Ticker` from
/// `package:flutter/`. This is the State-level motion signal: a custom widget
/// whose `State` holds a field of this type is driving imperative animation, so
/// its (already-deferred) diagnostic NAMES the catalog motion widgets to adopt.
///
/// Element-gated by design: a customer class that merely shares one of these
/// names, or an unresolved type, yields false — never a wrong hint (the same
/// look-alike discipline as [springAdoptTarget]).
///
/// `Timer` (`dart:async`) is deliberately NOT included: a Timer is ambiguous
/// (a countdown animation vs analytics / polling / debounce), so naming a
/// motion widget on it would be a wrong hint.
bool isImperativeMotionType(DartType? type) {
  if (type is! InterfaceType) return false;
  final element = type.element;
  if (!_kImperativeMotionTypeNames.contains(element.name)) return false;
  return element.library.identifier.startsWith('package:flutter/');
}

/// The catalog motion widget a directly-constructed spring should adopt, or
/// null when [expr] is not a Flutter spring construction.
///
/// Recognises `SpringDescription(...)` / `SpringSimulation(...)` from
/// `package:flutter/` — the imperative substrate [kRestageSpringWidget] wraps.
/// Element-gated: a customer class that merely shares the name, or an
/// unresolved reference, yields null — never a wrong hint. (Resolved by design,
/// mirroring the number-format recogniser.)
String? springAdoptTarget(InstanceCreationExpression expr) {
  final typeName = expr.constructorName.type.name.lexeme;
  if (typeName != 'SpringDescription' && typeName != 'SpringSimulation') {
    return null;
  }
  final libraryUri =
      expr.constructorName.type.element?.library?.identifier ?? '';
  if (!libraryUri.startsWith('package:flutter/')) return null;
  return kRestageSpringWidget;
}

/// The deferral diagnostic for an imperative-animation construct — names the
/// catalog motion widget(s) to adopt. With a specific [adoptTarget] (e.g. the
/// result of [springAdoptTarget]) it leads with that widget; otherwise it lists
/// the family by use-case. Manual-adopt only: imperative motion is never
/// auto-substituted (see the file-level note).
String motionDeferMessage([String? adoptTarget]) {
  const base = 'Imperative animation (AnimationController / SpringSimulation, '
      'or a package-backed motion system such as motor or cue) is not a '
      'supported paywall expression.';
  if (adoptTarget == kRestageSpringWidget) {
    return '$base Use the catalog widget `$kRestageSpringWidget` for a spring '
        'entrance — it runs the spring inside a compiled widget, so the '
        'paywall stays declarative.';
  }
  return '$base For a spring entrance use `$kRestageSpringWidget`; for a '
      'simple fade-in `$kRestageFadeWidget`; for a looping pulse '
      '`$kRestagePulseWidget`; for a staggered list reveal '
      '`$kRestageStaggerWidget`. Each runs its controller inside a compiled '
      'widget, so the paywall stays declarative.';
}
