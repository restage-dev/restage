/// The maximum nesting depth of an `inlineSpan` (`Text.rich` / `TextSpan`)
/// wire value.
///
/// Single source of truth shared by two surfaces: the build-time translator
/// (which defers loud when an authored span tree nests deeper than this, so the
/// emitted blob never relies on runtime truncation for correctness) and the
/// runtime decoder (which uses it as a hostile-wire backstop, terminating a
/// pathologically deep tree rather than overflowing the stack). Pinning both to
/// one value is what keeps the translator from ever emitting a tree the decoder
/// would silently truncate.
const int kMaxInlineSpanDepth = 32;

/// No-argument native callbacks installed on inline span recognizers.
const kTextSpanRecognizerVoidCallbacks = <String, Set<String>>{
  'tap': {
    'onTap',
    'onTapCancel',
    'onSecondaryTap',
    'onSecondaryTapCancel',
    'onTertiaryTapCancel'
  },
  'doubleTap': {'onDoubleTap', 'onDoubleTapCancel'},
  'longPress': {
    'onLongPress',
    'onLongPressUp',
    'onLongPressCancel',
    'onSecondaryLongPress',
    'onSecondaryLongPressUp',
    'onSecondaryLongPressCancel',
    'onTertiaryLongPress',
    'onTertiaryLongPressUp',
    'onTertiaryLongPressCancel'
  },
};

/// Fixed native contracts for callbacks receiving the original Flutter details.
const kTextSpanRecognizerDetailCallbacks = <String, Map<String, String>>{
  'tap': {
    'onTapDown': 'flutter.GestureTapDownCallback',
    'onSecondaryTapDown': 'flutter.GestureTapDownCallback',
    'onTertiaryTapDown': 'flutter.GestureTapDownCallback',
    'onTapUp': 'flutter.GestureTapUpCallback',
    'onSecondaryTapUp': 'flutter.GestureTapUpCallback',
    'onTertiaryTapUp': 'flutter.GestureTapUpCallback',
    'onTapMove': 'flutter.GestureTapMoveCallback',
  },
  'doubleTap': {
    'onDoubleTapDown': 'flutter.GestureTapDownCallback',
  },
  'longPress': {
    'onLongPressDown': 'flutter.GestureLongPressDownCallback',
    'onLongPressStart': 'flutter.GestureLongPressStartCallback',
    'onLongPressMoveUpdate': 'flutter.GestureLongPressMoveUpdateCallback',
    'onLongPressEnd': 'flutter.GestureLongPressEndCallback',
    'onSecondaryLongPressDown': 'flutter.GestureLongPressDownCallback',
    'onSecondaryLongPressStart': 'flutter.GestureLongPressStartCallback',
    'onSecondaryLongPressMoveUpdate':
        'flutter.GestureLongPressMoveUpdateCallback',
    'onSecondaryLongPressEnd': 'flutter.GestureLongPressEndCallback',
    'onTertiaryLongPressDown': 'flutter.GestureLongPressDownCallback',
    'onTertiaryLongPressStart': 'flutter.GestureLongPressStartCallback',
    'onTertiaryLongPressMoveUpdate':
        'flutter.GestureLongPressMoveUpdateCallback',
    'onTertiaryLongPressEnd': 'flutter.GestureLongPressEndCallback',
  },
};
