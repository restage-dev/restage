/// Reason a paywall was dismissed.
enum DismissReason {
  /// User explicitly closed the paywall (tapped close, swiped down, etc.).
  userClose,

  /// Paywall dismissed programmatically (e.g. via controller).
  programmatic,
}

/// Snake-cases a camelCase identifier (e.g. `userClose` → `user_close`).
String _snakeCase(String camel) {
  final buf = StringBuffer();
  for (var i = 0; i < camel.length; i++) {
    final c = camel.codeUnitAt(i);
    if (c >= 0x41 && c <= 0x5A) {
      // Uppercase: prefix with underscore (unless first char) and lowercase.
      if (i > 0) buf.writeCharCode(0x5F); // '_'
      buf.writeCharCode(c + 0x20);
    } else {
      buf.writeCharCode(c);
    }
  }
  return buf.toString();
}

T? _enumFromWire<T extends Enum>(List<T> values, String wire) {
  for (final v in values) {
    if (_snakeCase(v.name) == wire) return v;
  }
  return null;
}

/// Wire-form (snake_case) helpers for [DismissReason].
extension DismissReasonWire on DismissReason {
  /// Snake-case name suitable for analytics + cross-system serialization.
  String get wireName => _snakeCase(name);

  /// Parse a wire-form string back to a [DismissReason]. Falls back to
  /// [DismissReason.programmatic] for unrecognized strings.
  static DismissReason fromWire(String wire) =>
      _enumFromWire(DismissReason.values, wire) ?? DismissReason.programmatic;
}
