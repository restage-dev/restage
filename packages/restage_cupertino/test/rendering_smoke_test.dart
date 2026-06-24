// Catalog-walker rendering smoke for the restage.cupertino library.
//
// Iterates `kRegistry.widgets`, synthesises a minimal-valid-props rfw
// source fragment per widget, composes them into one root Column, and
// renders the tree once via the rfw Runtime. For every catalog entry
// the factory's top-level returned widget must be of the expected
// Flutter type — proving the generated factory function instantiates
// the right Flutter widget class without throwing.
//
// The assertion is structural rather than `find.byType`-based: each
// `LocalWidgetLibrary` builder is wrapped to emit a private
// `_SmokeMarker(name, child)` whose `child` is exactly what the
// factory returned. Per-entry assertions find markers by name and
// type-check `marker.child.runtimeType`. This stays robust against
// incidental Flutter widgets that compound Cupertino widgets
// internally compose — without the wrap, the internals could
// silently satisfy a `find.byType` assertion even if the matching
// factory had thrown.
//
// The walker wraps in CupertinoApp + Container + SingleChildScrollView
// so widgets that need a CupertinoTheme ancestor (CupertinoNavigationBar,
// CupertinoListTile, CupertinoTextField) get one and the column doesn't
// overflow the test viewport.
//
// Widgets that won't lay out as a Column child (e.g. CupertinoPageScaffold
// wants to be the tree root; the wheel pickers fill available vertical
// space) get a dedicated `testWidgets` block driven by the
// `_rootOnlyPaywallBodies` map below.
//
// Named-constructor variants (CupertinoButton.filled,
// CupertinoListSection.insetGrouped) all instantiate the same base
// class and `runtimeType`-match the same way; `_flutterTypeFor`
// collapses entry names to the base class accordingly.

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart' as core;
import 'package:restage_cupertino/restage_cupertino.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' show parseLibraryFile;
import 'package:rfw/rfw.dart' hide WidgetLibrary;

const LibraryName _coreLibrary = LibraryName(<String>['restage', 'core']);
const LibraryName _cupertinoLibrary =
    LibraryName(<String>['restage', 'cupertino']);
const LibraryName _rootLibrary = LibraryName(<String>['restage', 'paywall']);

/// Catalog entries that won't lay out as a Column child (they want
/// unbounded constraints) — each maps to the rfw expression mounted
/// as the CupertinoApp `home` in a dedicated `testWidgets` block.
///
/// `CupertinoPageScaffold` wants to be the tree root; the wheel
/// pickers (`CupertinoDatePicker`, `CupertinoTimerPicker`,
/// `CupertinoPicker`) fill available vertical space via
/// `RenderListWheelViewport` and need a parent that provides a bounded
/// height — neither shape lays out inside a Column wrapped in a
/// SingleChildScrollView.
const Map<String, String> _rootOnlyPaywallBodies = <String, String>{
  'CupertinoPageScaffold': 'CupertinoPageScaffold(child: Text(text: "smoke"))',
  'CupertinoDatePicker': 'CupertinoDatePicker()',
  'CupertinoTimerPicker': 'CupertinoTimerPicker()',
  'CupertinoPicker':
      'CupertinoPicker(itemExtent: 32.0, children: [Text(text: "smoke")])',
};

/// Curated minimal rfw fragments for catalog entries with required
/// properties the generic synthesiser can't construct. Three flavours:
///
/// 1. Required `source.child(...)` slots — CupertinoButton/Filled
///    need `child:`; CupertinoListTile needs `title:`. The factory-
///    generated `source.child` throws if the rfw source omits the slot.
/// 2. Required scalar properties without a literal `defaultValue` —
///    `CupertinoSwitch.value` is `bool`, required by curation, and
///    the factory now throws `ArgumentError` on missing.
/// 3. Constructor-asserted children: list sections render with empty
///    children at the rfw layer (factory uses `childList`, which
///    defaults to []), but CupertinoListSection asserts
///    children.isNotEmpty in its constructor — supply at least one
///    CupertinoListTile as a child.
const Map<String, String> _curatedMinimalRfwSource = <String, String>{
  'CupertinoButton': 'CupertinoButton(child: Text(text: "smoke"))',
  'CupertinoButtonFilled': 'CupertinoButtonFilled(child: Text(text: "smoke"))',
  'CupertinoListSection':
      'CupertinoListSection(children: [CupertinoListTile(title: Text(text: "smoke"))])',
  'CupertinoListSectionInsetGrouped':
      'CupertinoListSectionInsetGrouped(children: [CupertinoListTile(title: Text(text: "smoke"))])',
  'CupertinoListTile': 'CupertinoListTile(title: Text(text: "smoke"))',
  'CupertinoSwitch': 'CupertinoSwitch(value: false)',
  'CupertinoSlider': 'CupertinoSlider(value: 0.0)',
  'CupertinoCheckbox': 'CupertinoCheckbox(value: false)',
};

String _minimalRfwSourceFor(WidgetEntry entry) =>
    _curatedMinimalRfwSource[entry.name] ?? '${entry.name}()';

String _composeWalkerSource(Iterable<WidgetEntry> entries) {
  final fragments = entries.map(_minimalRfwSourceFor).join(',\n      ');
  return '''
import restage.core;
import restage.cupertino;

widget Paywall = Column(
  children: [
      $fragments,
  ],
);
''';
}

/// Maps `entry.name` to the corresponding Flutter [Type]. Named-
/// constructor variants (CupertinoButton.filled,
/// CupertinoListSection.insetGrouped) collapse to the base class.
Type _flutterTypeFor(String entryName) {
  switch (entryName) {
    case 'CupertinoActivityIndicator':
      return CupertinoActivityIndicator;
    case 'CupertinoButton':
    case 'CupertinoButtonFilled':
      return CupertinoButton;
    case 'CupertinoListSection':
    case 'CupertinoListSectionInsetGrouped':
      return CupertinoListSection;
    case 'CupertinoListTile':
      return CupertinoListTile;
    case 'CupertinoNavigationBar':
      return CupertinoNavigationBar;
    case 'CupertinoPageScaffold':
      return CupertinoPageScaffold;
    case 'CupertinoSwitch':
      return CupertinoSwitch;
    case 'CupertinoTextField':
      return CupertinoTextField;
    case 'CupertinoSlider':
      return CupertinoSlider;
    case 'CupertinoDatePicker':
      return CupertinoDatePicker;
    case 'CupertinoTimerPicker':
      return CupertinoTimerPicker;
    case 'CupertinoPicker':
      return CupertinoPicker;
    case 'CupertinoSearchTextField':
      return CupertinoSearchTextField;
    case 'CupertinoCheckbox':
      return CupertinoCheckbox;
  }
  throw StateError(
    'rendering_smoke_test: no Flutter Type mapping for catalog entry '
    '"$entryName" — add a case to _flutterTypeFor.',
  );
}

Runtime _buildRuntime(String paywallSource) => Runtime()
  ..update(
      _coreLibrary, _wrapLocalLibraryForSmoke(core.buildCoreWidgetLibrary()))
  ..update(_cupertinoLibrary,
      _wrapLocalLibraryForSmoke(buildCupertinoWidgetLibrary()))
  ..update(_rootLibrary, parseLibraryFile(paywallSource));

/// Wraps each builder in a `LocalWidgetLibrary` so the result of every
/// factory invocation is enclosed in a `_SmokeMarker(name, child:
/// factoryReturn)`. The marker preserves the factory's top-level
/// returned widget as its `child` for direct type inspection at
/// assertion time.
LocalWidgetLibrary _wrapLocalLibraryForSmoke(LocalWidgetLibrary library) {
  return LocalWidgetLibrary(<String, LocalWidgetBuilder>{
    for (final entry in library.widgets.entries)
      entry.key: (BuildContext ctx, DataSource source) => _SmokeMarker(
            name: entry.key,
            child: entry.value(ctx, source),
          ),
  });
}

/// Test-only marker the smoke wrap inserts above each rfw factory's
/// returned widget. The marker's `build` returns its `child` unchanged,
/// so layout matches the unwrapped tree; the per-entry assertion finds
/// the marker by name and checks `child.runtimeType`.
class _SmokeMarker extends StatelessWidget {
  const _SmokeMarker({required this.name, required this.child});

  final String name;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

void _expectRendered(WidgetEntry entry) {
  final markers = find
      .byWidgetPredicate(
          (widget) => widget is _SmokeMarker && widget.name == entry.name)
      .evaluate();
  expect(
    markers,
    isNotEmpty,
    reason: 'no _SmokeMarker emitted for ${entry.name} — the factory '
        'either threw or rfw substituted an ErrorWidget',
  );
  final expectedType = _flutterTypeFor(entry.name);
  for (final element in markers) {
    final marker = element.widget as _SmokeMarker;
    expect(
      marker.child.runtimeType,
      expectedType,
      reason: 'factory for ${entry.name} returned ${marker.child.runtimeType}, '
          'expected $expectedType (catalog flutterType: ${entry.flutterType})',
    );
  }
}

void main() {
  group('restage_cupertino rendering smoke', () {
    testWidgets('every catalog widget renders into the tree', (tester) async {
      final allEntries = kRegistry.widgets;
      expect(allEntries, isNotEmpty,
          reason: 'kRegistry must have widgets for the smoke to be meaningful');

      final walkerEntries = allEntries
          .where((w) => !_rootOnlyPaywallBodies.containsKey(w.name))
          .toList();

      final runtime = _buildRuntime(_composeWalkerSource(walkerEntries));
      final data = DynamicContent();

      // CupertinoApp provides a CupertinoTheme ancestor for widgets
      // that look one up (CupertinoNavigationBar, CupertinoListTile,
      // CupertinoTextField). SingleChildScrollView prevents
      // RenderFlex overflow when the catalog widgets stack in a
      // Column inside the test viewport.
      await tester.pumpWidget(
        CupertinoApp(
          home: SingleChildScrollView(
            child: RemoteWidget(
              runtime: runtime,
              data: data,
              widget: const FullyQualifiedWidgetName(_rootLibrary, 'Paywall'),
              onEvent: (_, __) {},
            ),
          ),
        ),
      );
      await tester.pump();

      for (final entry in walkerEntries) {
        _expectRendered(entry);
      }
    });

    // One `testWidgets` per `_rootOnlyPaywallBodies` entry. Each mounts
    // its rfw expression as the CupertinoApp `home` so layout receives
    // the full screen-sized BoxConstraints.
    for (final MapEntry(key: entryName, value: paywallBody)
        in _rootOnlyPaywallBodies.entries) {
      testWidgets('$entryName renders as a CupertinoApp root', (tester) async {
        final entry = kRegistry.findByName(entryName, WidgetLibrary.cupertino)!;
        final runtime = _buildRuntime('''
import restage.core;
import restage.cupertino;
widget Paywall = $paywallBody;
''');
        await tester.pumpWidget(
          CupertinoApp(
            home: RemoteWidget(
              runtime: runtime,
              data: DynamicContent(),
              widget: const FullyQualifiedWidgetName(_rootLibrary, 'Paywall'),
              onEvent: (_, __) {},
            ),
          ),
        );
        await tester.pump();
        _expectRendered(entry);
      });
    }
  });
}
