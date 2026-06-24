/// The `data.theme.*` shipped-blob contract — the dot-paths a transpiled
/// custom widget may reference, and that the SDK publishes into a rendered
/// paywall's `DynamicContent`.
///
/// Single source of truth shared by the SDK's theme publisher and the
/// codegen-side translator's contract validation, so the two cannot drift.
/// Once a blob referencing any of these paths ships, the contract is
/// **additive-only**: a renamed, removed, or retyped key would silently
/// break a live blob — additions are safe (a blob that doesn't reference
/// the new key is unaffected), but rename / remove / retype is a wire
/// break.
///
/// The namespace is **blob-global**: the SDK publishes one `data.theme.*`
/// namespace into a rendered paywall's `DynamicContent`, with no per-subtree
/// or per-context dimension — a given theme path denotes the same value
/// anywhere in a blob. Build-time transpilation depends on this when it hoists
/// an optional property's theme-derived default to the call site: the hoisted
/// reference is an identity transform only because the path is
/// position-independent. **Do not introduce subtree-scoped `data.theme.*`
/// resolution without revisiting that call-site-completion design** — it would
/// silently change the meaning of every hoisted default. (Guarded by the
/// `blob-global theme invariant` test in `restage_codegen`.)
library;

/// Every in-contract dot path — `<namespace>.<key>` — joined with `.`.
///
/// A consumer-side path-equality check is `kThemeContractPaths.contains(path)`
/// where `path` is the joined segments of a `Theme.of(c).<x>(.<y>)` chain.
const Set<String> kThemeContractPaths = {
  // colorScheme.<role> — every non-deprecated ColorScheme colour role.
  ..._kColorSchemeRoles,
  // iconTheme.<key> — nullable fields; consumer falls through to its own
  // default when a key is omitted at population time.
  'iconTheme.color',
  'iconTheme.size',
  // defaultTextStyle.<key> — nullable; same fallthrough as iconTheme.
  'defaultTextStyle.color',
  'defaultTextStyle.fontSize',
  'defaultTextStyle.fontWeight',
};

/// The wire-value kind a contract path publishes — the type axis of the
/// `data.theme.*` contract. Paired with every path in
/// [kThemeContractPathKinds] so a consumer binding a path to a typed slot
/// can validate compatibility without keeping its own per-path type table.
enum ThemeContractValueKind {
  /// A 32-bit ARGB integer colour.
  color,

  /// A double-valued dimension (an icon size, a font size).
  size,

  /// A `w100`–`w900` font-weight token string.
  fontWeight,
}

/// Every in-contract dot path mapped to the [ThemeContractValueKind] it
/// publishes. Keys are exactly [kThemeContractPaths] — an addition to the
/// contract must extend both (consumers guard the pairing with tests).
/// The same additive-only rule applies: a published path's kind is part of
/// the wire contract and must not change.
final Map<String, ThemeContractValueKind> kThemeContractPathKinds =
    Map.unmodifiable(<String, ThemeContractValueKind>{
  for (final role in _kColorSchemeRoles) role: ThemeContractValueKind.color,
  'iconTheme.color': ThemeContractValueKind.color,
  'iconTheme.size': ThemeContractValueKind.size,
  'defaultTextStyle.color': ThemeContractValueKind.color,
  'defaultTextStyle.fontSize': ThemeContractValueKind.size,
  'defaultTextStyle.fontWeight': ThemeContractValueKind.fontWeight,
});

/// The in-contract `colorScheme.<role>` paths — every non-deprecated
/// `ColorScheme` colour role the SDK's `populateThemeData` writes. The
/// deprecated roles `background`, `onBackground`, and `surfaceVariant`
/// are excluded by design.
const Set<String> _kColorSchemeRoles = {
  'colorScheme.primary',
  'colorScheme.onPrimary',
  'colorScheme.primaryContainer',
  'colorScheme.onPrimaryContainer',
  'colorScheme.primaryFixed',
  'colorScheme.primaryFixedDim',
  'colorScheme.onPrimaryFixed',
  'colorScheme.onPrimaryFixedVariant',
  'colorScheme.secondary',
  'colorScheme.onSecondary',
  'colorScheme.secondaryContainer',
  'colorScheme.onSecondaryContainer',
  'colorScheme.secondaryFixed',
  'colorScheme.secondaryFixedDim',
  'colorScheme.onSecondaryFixed',
  'colorScheme.onSecondaryFixedVariant',
  'colorScheme.tertiary',
  'colorScheme.onTertiary',
  'colorScheme.tertiaryContainer',
  'colorScheme.onTertiaryContainer',
  'colorScheme.tertiaryFixed',
  'colorScheme.tertiaryFixedDim',
  'colorScheme.onTertiaryFixed',
  'colorScheme.onTertiaryFixedVariant',
  'colorScheme.error',
  'colorScheme.onError',
  'colorScheme.errorContainer',
  'colorScheme.onErrorContainer',
  'colorScheme.surface',
  'colorScheme.onSurface',
  'colorScheme.surfaceDim',
  'colorScheme.surfaceBright',
  'colorScheme.surfaceContainerLowest',
  'colorScheme.surfaceContainerLow',
  'colorScheme.surfaceContainer',
  'colorScheme.surfaceContainerHigh',
  'colorScheme.surfaceContainerHighest',
  'colorScheme.onSurfaceVariant',
  'colorScheme.outline',
  'colorScheme.outlineVariant',
  'colorScheme.shadow',
  'colorScheme.scrim',
  'colorScheme.inverseSurface',
  'colorScheme.onInverseSurface',
  'colorScheme.inversePrimary',
  'colorScheme.surfaceTint',
};
