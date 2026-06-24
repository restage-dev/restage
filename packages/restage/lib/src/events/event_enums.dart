/// Reason a paywall was dismissed.
enum DismissReason {
  /// User explicitly closed the paywall (tapped close, swiped down, etc.).
  userClose,

  /// Paywall dismissed because a purchase completed successfully.
  purchaseCompleted,

  /// Paywall dismissed because a purchase entered the pending state.
  purchasePending,

  /// Paywall dismissed because a restore returned active entitlements.
  restoreCompleted,

  /// Paywall dismissed programmatically (e.g. via controller).
  programmatic,
}

/// StoreKit `.pending` / Play `PENDING` reason discrimination.
enum PendingReason {
  /// Family-organizer approval required (StoreKit Ask to Buy).
  askToBuy,

  /// Payment is processing (e.g. SEPA, Boleto).
  paymentPending,

  /// Pending for an unspecified reason.
  unknown,
}

/// Why an entitlement was revoked.
enum RevokeReason {
  /// Subscription expired and did not renew.
  expired,

  /// Purchase was refunded.
  refunded,

  /// Entitlement was server-side revoked (e.g. fraud, manual).
  revoked,

  /// Replaced by an upgrade to a different SKU.
  upgraded,
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

/// Wire-form (snake_case) helpers for [DismissReason], [PendingReason], and
/// [RevokeReason]. `wireName` serializes an enum value to its snake-case wire
/// form (for analytics and cross-system serialization). The `fromWire` parsers
/// ([DismissReasonWire.fromWire], [PendingReasonWire.fromWire]) are a public
/// utility for host code and custom [BillingGateway] implementations that need
/// to map a wire-form string back to a typed enum — the SDK takes typed enum
/// values on its own event paths and does not call `fromWire` internally.
extension DismissReasonWire on DismissReason {
  /// Snake-case name suitable for analytics + cross-system serialization.
  String get wireName => _snakeCase(name);

  /// Parse a wire-form string back to a [DismissReason]. Falls back to
  /// [DismissReason.programmatic] for unrecognized strings.
  static DismissReason fromWire(String wire) =>
      _enumFromWire(DismissReason.values, wire) ?? DismissReason.programmatic;
}

/// Wire-form (snake_case) helpers for [PendingReason].
extension PendingReasonWire on PendingReason {
  /// Snake-case name suitable for analytics + cross-system serialization.
  String get wireName => _snakeCase(name);

  /// Parse a wire-form string back to a [PendingReason]. Falls back to
  /// [PendingReason.unknown] for unrecognized strings.
  static PendingReason fromWire(String wire) =>
      _enumFromWire(PendingReason.values, wire) ?? PendingReason.unknown;
}

/// Wire-form (snake_case) helpers for [RevokeReason].
extension RevokeReasonWire on RevokeReason {
  /// Snake-case name suitable for analytics + cross-system serialization.
  String get wireName => _snakeCase(name);
}
