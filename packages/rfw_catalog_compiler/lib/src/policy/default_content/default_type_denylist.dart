// packages/rfw_catalog_compiler/lib/src/policy/default_content/default_type_denylist.dart

/// Exact-match type display names that never become catalog property
/// types. Curated against the framework primitives, restoration / key
/// types, reactivity surfaces, imperative controllers / focus nodes,
/// painter / clipper surfaces, locale / matrix / route types, and
/// layout / hit-testing primitives whose values cannot round-trip
/// through the catalog wire format.
const Set<String> kBuiltInTypeDenylist = {
  // Element / context / framework primitives.
  'BuildContext',
  'Element',
  'RenderObject',
  'State',

  // Keys.
  'Key',
  'LocalKey',
  'GlobalKey',
  'UniqueKey',
  'ValueKey',
  'ObjectKey',

  // Restoration.
  'RestorationId',
  'RestorationBucket',

  // Reactivity / async primitives.
  'Listenable',
  'ValueListenable',
  'ChangeNotifier',
  'Future',
  'Stream',
  'Animation',
  'TickerProvider',

  // Imperative controllers / nodes / providers.
  'TextEditingController',
  'ScrollController',
  'FocusNode',
  'FocusScopeNode',
  'PageController',
  'TabController',

  // Painters / clippers / drawing primitives.
  'CustomPainter',
  'CustomClipper',
  'PreferredSizeWidget',
  'Shader',
  'ImageProvider',
  'AssetBundle',

  // Localization / locales.
  'Locale',

  // Matrices, routes, navigation primitives.
  'Matrix4',
  'RouteSettings',
  'Navigator',
  'PageRoute',
  'Route',

  // Layout / hit-testing primitives the catalog doesn't surface broadly.
  // `BoxConstraints` is denylisted by default; the widgets that surface it
  // (`Container` / `AnimatedContainer`) un-cut it per-widget via their
  // flat-scalar decompose recipe (`minWidth` / `maxWidth` / `minHeight` /
  // `maxHeight` hoist onto flat real slots). Denylisting it globally keeps it
  // off widgets with no consumer — i.e. no orphan structured entry.
  'BoxConstraints',
  'MouseCursor',
  'SystemMouseCursors',
  'HitTestBehavior',
  'DragStartBehavior',

  // Scroll / text-layout enums and abstractions the catalog doesn't surface.
  // (`ScrollViewKeyboardDismissBehavior` is a clean 2-member enum that DOES
  // round-trip through the wire format, so it is surfaced, not denylisted.)
  'TextBaseline',
  'ScrollPhysics',
};

/// Type-display-name suffix patterns.
const Set<String> kBuiltInTypeDenylistSuffixes = {
  'Controller',
  'Node',
  'Builder',
  'Configuration',
};
