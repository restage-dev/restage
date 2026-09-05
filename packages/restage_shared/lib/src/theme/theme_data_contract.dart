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
final Set<String> kThemeContractPaths = Set.unmodifiable(<String>{
  // colorScheme.<role> — every non-deprecated ColorScheme colour role.
  ..._kColorSchemeRoles,
  // iconTheme.<key> — nullable fields; consumer falls through to its own
  // default when a key is omitted at population time.
  'iconTheme.color',
  'iconTheme.size',
  // defaultTextStyle.<key> — nullable; same fallthrough as iconTheme. Carries
  // the same fields as a textTheme style, so the two families stay symmetric.
  for (final field in kThemeContractTextThemeFieldKinds.keys)
    'defaultTextStyle.$field',
  // textTheme.<style>.<field> — the Material text-theme styles, each with
  // the same nullable-field fallthrough as defaultTextStyle.
  ..._kTextThemePaths,
  // The ambient theme's brightness, as a `light` / `dark` token string.
  'brightness',
});

/// The `TextTheme` styles the contract publishes — the Material 3 style names,
/// each carrying [kThemeContractTextThemeFieldKinds].
const List<String> kThemeContractTextThemeStyles = [
  'displayLarge',
  'displayMedium',
  'displaySmall',
  'headlineLarge',
  'headlineMedium',
  'headlineSmall',
  'titleLarge',
  'titleMedium',
  'titleSmall',
  'bodyLarge',
  'bodyMedium',
  'bodySmall',
  'labelLarge',
  'labelMedium',
  'labelSmall',
];

/// The `TextStyle` fields a published style carries, mapped to the wire kind
/// each publishes — every field a catalog `TextStyle` slot holds as a scalar
/// or a list of scalars, so a whole-style read binds the style the host set
/// rather than a subset of it.
///
/// `letterSpacing`, `wordSpacing`, `height` and `decorationThickness` are
/// doubles like `fontSize`, so they share its [ThemeContractValueKind.size]
/// kind. `decoration` publishes the token naming one of `underline`,
/// `overline`, `lineThrough` and `none`; a value combining more than one line
/// has no token, so its key is omitted and the slot falls through to its own
/// default.
///
/// Not carried: `shadows`, `fontFeatures`, `fontVariations`, `foreground`,
/// `background`, `locale`, `debugLabel` and `inherit`. Write a literal
/// `TextStyle` to set any of those.
///
/// The same set backs every `textTheme.<style>` and `defaultTextStyle`.
const Map<String, ThemeContractValueKind> kThemeContractTextThemeFieldKinds = {
  'color': ThemeContractValueKind.color,
  'backgroundColor': ThemeContractValueKind.color,
  'fontFamily': ThemeContractValueKind.text,
  'fontFamilyFallback': ThemeContractValueKind.textList,
  'fontSize': ThemeContractValueKind.size,
  'fontWeight': ThemeContractValueKind.fontWeight,
  'fontStyle': ThemeContractValueKind.fontStyle,
  'letterSpacing': ThemeContractValueKind.size,
  'wordSpacing': ThemeContractValueKind.size,
  'height': ThemeContractValueKind.size,
  'leadingDistribution': ThemeContractValueKind.leadingDistribution,
  'textBaseline': ThemeContractValueKind.textBaseline,
  'overflow': ThemeContractValueKind.textOverflow,
  'decoration': ThemeContractValueKind.textDecoration,
  'decorationColor': ThemeContractValueKind.color,
  'decorationStyle': ThemeContractValueKind.textDecorationStyle,
  'decorationThickness': ThemeContractValueKind.size,
};

/// Every `textTheme.<style>.<field>` path, one per style × field pair.
final Set<String> _kTextThemePaths = Set.unmodifiable(<String>{
  for (final style in kThemeContractTextThemeStyles)
    for (final field in kThemeContractTextThemeFieldKinds.keys)
      'textTheme.$style.$field',
});

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

  /// A plain string, such as a font family name.
  text,

  /// A `normal` / `italic` font-style token string, named for the `FontStyle`
  /// member it denotes so an enum-by-name decoder resolves it.
  fontStyle,

  /// A list of plain strings, such as the fallback font families.
  textList,

  /// An `underline` / `overline` / `lineThrough` / `none` token naming the
  /// `TextDecoration` value it denotes. A decoration combining more than one
  /// line has no token and is not published.
  textDecoration,

  /// A `TextDecorationStyle` member name, resolved by an enum-by-name decoder.
  textDecorationStyle,

  /// A `TextLeadingDistribution` member name, resolved by an enum-by-name
  /// decoder.
  leadingDistribution,

  /// A `TextBaseline` member name, resolved by an enum-by-name decoder.
  textBaseline,

  /// A `TextOverflow` member name, resolved by an enum-by-name decoder.
  textOverflow,

  /// A `light` / `dark` brightness token string. No catalog slot accepts it;
  /// it exists to be branched on, not assigned.
  brightness,
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
  for (final entry in kThemeContractTextThemeFieldKinds.entries)
    'defaultTextStyle.${entry.key}': entry.value,
  'brightness': ThemeContractValueKind.brightness,
  for (final style in kThemeContractTextThemeStyles)
    for (final entry in kThemeContractTextThemeFieldKinds.entries)
      'textTheme.$style.${entry.key}': entry.value,
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
