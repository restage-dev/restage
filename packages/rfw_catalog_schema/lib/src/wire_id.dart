import 'package:meta/meta.dart';

/// Stable identity for a single catalog entry.
///
/// Wire IDs are the canonical reference for everything addressable from a
/// persisted paywall blob: widgets, properties, structured types, factory
/// variants, unions, and design tokens. Display names and source paths are
/// advisory labels that may change via `rename` events; wire IDs do not.
///
/// **Format.** A single-letter kind prefix (`w` / `p` / `s` / `v` / `u` /
/// `t` / `a`) followed by a zero-padded decimal sequence of at least four
/// digits. Examples: `w0001`, `p0042`, `s0003`, `v0017`, `u0001`, `t0007`,
/// `a0001`.
///
/// **Scope.** Wire IDs are per-library, per-kind. Each library has its own
/// monotonic counter for each kind; two libraries may independently allocate
/// `w0001` without collision. Cross-library references use [WireIdRef] to
/// pair the library namespace with the local wire ID.
@immutable
final class WireId {
  /// Constructs a wire ID from its string [value].
  ///
  /// Validates the canonical public format eagerly: a single-letter kind
  /// prefix from the recognized set followed by the zero-padded decimal
  /// sequence (minimum four digits). Because equality and the codec's
  /// identity maps key on the [value] string, the format must be the single
  /// canonical spelling of `(kind, sequence)`: non-canonical spellings a
  /// leading sign or whitespace (`w+123`, `w 123`), or extra zero-padding
  /// (`w00001`) would name the same entry yet compare unequal, so they are
  /// rejected. Throws [ArgumentError] on malformed input — callers handle
  /// only well-formed wire IDs.
  factory WireId(String value) {
    if (value.length < 5) {
      throw ArgumentError.value(
        value,
        'value',
        'Wire ID must be at least 5 characters: a kind prefix and four digits.',
      );
    }
    final kind = _kindFromPrefix(value.codeUnitAt(0));
    if (kind == null) {
      throw ArgumentError.value(
        value,
        'value',
        'Wire ID prefix must be one of w/p/s/v/u/t/a.',
      );
    }
    // radix: 10 disables `int.tryParse`'s automatic `0x` hex
    // detection so `'w0xab'` is rejected (the suffix isn't a decimal
    // integer).
    final sequence = int.tryParse(value.substring(1), radix: 10);
    if (sequence == null || sequence <= 0) {
      throw ArgumentError.value(
        value,
        'value',
        'Wire ID sequence must be a positive decimal integer. Sequence 0 is '
            'reserved for internal unallocated sentinels.',
      );
    }
    // Equality and the codec's identity maps key on the [value] string, so
    // the value must be the one canonical spelling of (kind, sequence): the
    // kind prefix plus the zero-padded sequence (minimum four digits).
    // `int.tryParse` would otherwise accept a leading sign or surrounding
    // whitespace, and the length check permits extra zero-padding — all
    // forms that name the same entry yet compare unequal to the canonical
    // string. Reject anything that is not already canonical.
    final canonical = '${kind.prefix}${sequence.toString().padLeft(4, '0')}';
    if (value != canonical) {
      throw ArgumentError.value(
        value,
        'value',
        'Wire ID must be in canonical form "$canonical": a kind prefix plus '
            'the zero-padded sequence (minimum four digits). Non-canonical '
            'spellings (leading sign, whitespace, or extra zero-padding) are '
            'rejected.',
      );
    }
    return WireId._(value, kind, sequence);
  }

  const WireId._(this.value, this.kind, this.sequence);

  /// Sentinels by kind. Transitional catalog tooling that constructs an
  /// entry before the allocator has run uses one of these as an internal
  /// placeholder; the allocator detects sentinels (sequence == 0) and
  /// replaces them with real allocations against the per-library event log.
  ///
  /// Sentinels are not valid public wire IDs. They cannot be constructed via
  /// [WireId.new], decoded from canonical catalog JSON, or emitted by
  /// `encodeCatalog`.
  static const WireId unallocatedWidget =
      WireId._('w0000', WireIdKind.widget, 0);

  /// Property-kind sentinel. See [unallocatedWidget].
  static const WireId unallocatedProperty =
      WireId._('p0000', WireIdKind.property, 0);

  /// Structured-kind sentinel. See [unallocatedWidget].
  static const WireId unallocatedStructured =
      WireId._('s0000', WireIdKind.structured, 0);

  /// Variant-kind sentinel. See [unallocatedWidget].
  static const WireId unallocatedVariant =
      WireId._('v0000', WireIdKind.variant, 0);

  /// Union-kind sentinel. See [unallocatedWidget].
  static const WireId unallocatedUnion = WireId._('u0000', WireIdKind.union, 0);

  /// Design-token-kind sentinel. See [unallocatedWidget].
  static const WireId unallocatedDesignToken =
      WireId._('t0000', WireIdKind.designToken, 0);

  /// Factory-parameter-kind sentinel. See [unallocatedWidget].
  static const WireId unallocatedParameter =
      WireId._('a0000', WireIdKind.parameter, 0);

  /// Returns the per-kind unallocated sentinel for [kind]. Equivalent
  /// to [unallocatedWidget] / [unallocatedProperty] / etc., for code
  /// paths that select the kind at runtime. Const contexts should
  /// reference the per-kind constants directly.
  static WireId unallocated(WireIdKind kind) {
    switch (kind) {
      case WireIdKind.widget:
        return unallocatedWidget;
      case WireIdKind.property:
        return unallocatedProperty;
      case WireIdKind.structured:
        return unallocatedStructured;
      case WireIdKind.variant:
        return unallocatedVariant;
      case WireIdKind.union:
        return unallocatedUnion;
      case WireIdKind.designToken:
        return unallocatedDesignToken;
      case WireIdKind.parameter:
        return unallocatedParameter;
    }
  }

  /// Whether this wire ID is the unallocated sentinel for its kind.
  /// Real allocations are monotonically increasing starting at
  /// sequence 1; sentinels carry sequence 0.
  bool get isUnallocated => sequence == 0;

  /// String form of the wire ID, e.g. `'w0001'`.
  final String value;

  /// The wire ID's kind, derived from its prefix character.
  final WireIdKind kind;

  /// The wire ID's monotonic sequence number, derived from its suffix
  /// digits. Two wire IDs with the same kind and sequence are equal.
  final int sequence;

  @override
  bool operator ==(Object other) => other is WireId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;

  static WireIdKind? _kindFromPrefix(int codeUnit) {
    switch (codeUnit) {
      case 0x77: // 'w'
        return WireIdKind.widget;
      case 0x70: // 'p'
        return WireIdKind.property;
      case 0x73: // 's'
        return WireIdKind.structured;
      case 0x76: // 'v'
        return WireIdKind.variant;
      case 0x75: // 'u'
        return WireIdKind.union;
      case 0x74: // 't'
        return WireIdKind.designToken;
      case 0x61: // 'a'
        return WireIdKind.parameter;
      default:
        return null;
    }
  }
}

/// What kind of catalog entry a [WireId] addresses.
enum WireIdKind {
  /// Widget entry (`w0001`).
  widget('w'),

  /// Property entry, either on a widget or on a structured type's field
  /// list (`p0001`). Library-scoped — two properties in the same library
  /// never share a wire ID even across different owners.
  property('p'),

  /// Structured (value-type) entry (`s0001`). Examples: `BoxDecoration`,
  /// `TextStyle`, `LinearGradient`, customer `AcmeColor`.
  structured('s'),

  /// Factory variant on a structured type (`v0001`). Covers named
  /// constructors, static factory methods, static getters, and static
  /// const fields.
  variant('v'),

  /// Discriminated union entry (`u0001`). Members are structured types.
  union('u'),

  /// Design token entry (`t0001`). Durable named values blobs may
  /// reference for color, length, typography, etc.
  designToken('t'),

  /// Callable parameter entry (`a0001`). Parameters are owned by a
  /// factory variant and are referenced by native decompose transforms.
  parameter('a');

  const WireIdKind(this.prefix);

  /// Single-character prefix used in the [WireId.value] string form.
  final String prefix;
}

/// Cross-library reference to a [WireId].
///
/// Use to point at entries that may live in a different library namespace
/// than the referrer. Examples: a `Container` property referencing
/// `restage.core`'s `t0005` (`surface`) design token, or a customer paywall
/// referencing a `restage_material` widget entry.
@immutable
final class WireIdRef {
  /// Const constructor.
  const WireIdRef({required this.library, required this.wireId});

  /// Library namespace the [wireId] belongs to (e.g. `'restage.core'`,
  /// `'acme.design_system'`).
  final String library;

  /// The wire ID within [library]. The kind is encoded in the wire ID
  /// itself.
  final WireId wireId;

  @override
  bool operator ==(Object other) =>
      other is WireIdRef && other.library == library && other.wireId == wireId;

  @override
  int get hashCode => Object.hash(library, wireId);

  @override
  String toString() => '$library:$wireId';
}
