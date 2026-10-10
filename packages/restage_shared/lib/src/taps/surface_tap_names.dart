import 'package:restage_shared/src/flow_document/paywall_screen_assets.dart';
import 'package:restage_shared/src/rfw_formats.dart';
import 'package:restage_shared/src/taps/icon_names.g.dart';

/// Longest name a tappable element or a page is given.
const kSurfaceTapNameLimit = 128;

/// The name a tappable [element] shows: [semanticsOverride] when an enclosing
/// `Semantics` labels it, else its first text, semantics label, tooltip, then
/// icon; null when none is found.
String? surfaceTapElementName(
  ConstructorCall element, {
  String? semanticsOverride,
}) =>
    _bounded(semanticsOverride) ??
    _first(element,
        (call) => call.name == 'Text' ? call.arguments['text'] : null) ??
    _first(element, _semanticsLabelOf) ??
    _first(element, (call) => call.arguments['tooltip']) ??
    _first(element, _iconNameOf);

/// The label a `Semantics` call gives its subtree, or null for any other call.
String? surfaceTapSemanticsLabel(ConstructorCall call) =>
    call.name == 'Semantics' ? _bounded(call.arguments['label']) : null;

/// An icon's name in words, such as Close for `close_rounded`.
String? surfaceIconName(int codepoint, {String? fontFamily}) {
  final name = fontFamily == 'CupertinoIcons'
      ? kCupertinoIconNames[codepoint]
      : kMaterialIconNames[codepoint];
  if (name == null) return null;
  final bare =
      name.replaceAll(_iconSuffix, '').replaceFirst(RegExp('^arrow_'), '');
  return humaniseSurfaceId(bare.isEmpty ? name : bare);
}

/// A surface, screen or step id in words: separators become spaces, the
/// first letter is capitalised, and a paywall screen's prefix is dropped.
String humaniseSurfaceId(String id) {
  final name = isPaywallScreenArtifact(id)
      ? id.substring(kPaywallScreenIdPrefix.length)
      : id;
  if (name.isEmpty) return name;
  final spaced = name.replaceAll('_', ' ').replaceAll('-', ' ');
  return spaced[0].toUpperCase() + spaced.substring(1);
}

/// Style and platform suffixes an icon's name carries beside its meaning.
final RegExp _iconSuffix =
    RegExp(r'(_(rounded|outlined|outline|sharp|filled|fill|ios|new|solid))+$');

Object? _semanticsLabelOf(ConstructorCall call) =>
    surfaceTapSemanticsLabel(call) ??
    call.arguments['semanticsLabel'] ??
    call.arguments['semanticLabel'];

Object? _iconNameOf(ConstructorCall call) {
  if (call.name != 'Icon') return null;
  final codepoint = call.arguments['iconCodepoint'];
  if (codepoint is! int) return null;
  final family = call.arguments['iconFontFamily'];
  return surfaceIconName(codepoint,
      fontFamily: family is String ? family : null);
}

/// The first usable name [pick] finds in [node]'s subtree, depth first.
String? _first(Object? node, Object? Function(ConstructorCall call) pick) {
  if (node is ConstructorCall) {
    if (_bounded(pick(node)) case final found?) return found;
    for (final value in node.arguments.values) {
      if (_first(value, pick) case final found?) return found;
    }
  } else if (node is List) {
    for (final value in node) {
      if (_first(value, pick) case final found?) return found;
    }
  } else if (node is Map) {
    for (final value in node.values) {
      if (_first(value, pick) case final found?) return found;
    }
  }
  return null;
}

/// [value] as a single-line name within the bound, or null when it is not a
/// literal string with visible text.
String? _bounded(Object? value) {
  if (value is! String) return null;
  final name = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (name.isEmpty) return null;
  return name.length <= kSurfaceTapNameLimit
      ? name
      : '${name.substring(0, kSurfaceTapNameLimit - 1)}…';
}
