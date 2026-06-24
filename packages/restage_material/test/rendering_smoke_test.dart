// Catalog-walker rendering smoke for the restage.material library.
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
// incidental Flutter widgets that compound material widgets
// internally compose (Card → Material+InkWell+Padding,
// ListTile → Material+InkWell+Row, etc.) — without the wrap, the
// internals could silently satisfy a `find.byType` assertion even
// if the matching factory had thrown.
//
// Adding a new entry to `kRegistry` automatically extends the smoke;
// at most a curated minimal-props entry is needed when a widget has
// non-defaultable required arguments that the generic synthesiser
// can't construct (most commonly a `source.child(...)` slot, which
// throws if the rfw source omits it).
//
// Widgets that themselves want to BE the tree root — `Scaffold`,
// `MaterialApp` — fail to lay out when nested inside the main
// walker's Column (they want unbounded constraints). They get a
// dedicated `testWidgets` each, rendered without the main walker's
// MaterialApp+Scaffold wrapper.
//
// Named-constructor variants (Card vs Card.filled vs Card.outlined,
// FilledButton vs FilledButton.tonal) all instantiate the same base
// class and `runtimeType`-match the same way; `_flutterTypeFor`
// collapses entry names to the base class accordingly. Variant-level
// distinction needs a different mechanism.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart' as core;
import 'package:restage_material/restage_material.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' show parseLibraryFile;
import 'package:rfw/rfw.dart' hide Switch, WidgetLibrary;

const LibraryName _coreLibrary = LibraryName(<String>['restage', 'core']);
const LibraryName _materialLibrary =
    LibraryName(<String>['restage', 'material']);
const LibraryName _rootLibrary = LibraryName(<String>['restage', 'paywall']);

/// Catalog entries that won't lay out as a Column child (they want
/// unbounded constraints). Each gets a dedicated `testWidgets` block
/// below; the main walker excludes them.
const Set<String> _rootOnlyEntries = <String>{'MaterialApp', 'Scaffold'};

/// Curated minimal rfw fragments for catalog entries with required
/// properties the generic synthesiser can't construct. Three flavours:
///
/// 1. Required `source.child(...)` slots — buttons need `child:` (or
///    `icon:` + `label:` for the .icon variants); IconButton needs
///    `icon:`. The factory-generated `source.child` throws if the rfw
///    source omits the slot.
/// 2. Required scalar properties without a literal `defaultValue` —
///    the factory now throws `ArgumentError` on missing required
///    scalars and required `iconData` synthetics (the catalog-level
///    `required: true` enforcement). Cases here: `Checkbox.value` and
///    `Switch.value` (bool), and `Icon.iconCodepoint` (int synthetic
///    that wraps as `IconData`). Codepoint 0xe87d is `visibility` from
///    the Material icon font — any valid codepoint works for the smoke.
/// 3. Most non-button widgets fall through to the generic empty-args
///    fragment (`<EntryName>()`).
const Map<String, String> _curatedMinimalRfwSource = <String, String>{
  'ActionChip': 'ActionChip(label: Text(text: "smoke"))',
  'Checkbox': 'Checkbox(value: false)',
  'CheckboxListTile': 'CheckboxListTile(value: false)',
  'Chip': 'Chip(label: Text(text: "smoke"))',
  'ChoiceChip': 'ChoiceChip(label: Text(text: "smoke"), selected: false)',
  'ElevatedButton': 'ElevatedButton(child: Text(text: "smoke"))',
  'ExpressCheckoutButton': 'ExpressCheckoutButton()',
  'ExpansionTile': 'ExpansionTile(title: Text(text: "smoke"))',
  'FilledButton': 'FilledButton(child: Text(text: "smoke"))',
  'FilledButtonTonal': 'FilledButtonTonal(child: Text(text: "smoke"))',
  'FilterChip': 'FilterChip(label: Text(text: "smoke"))',
  'Icon': 'Icon(iconCodepoint: 0xe87d)',
  'IconButton': 'IconButton(icon: Icon(iconCodepoint: 0xe87d))',
  // InkWell has no intrinsic size; give it a finite child so the
  // surrounding Column doesn't hit "infinite size during layout".
  'InkWell': 'InkWell(child: Text(text: "smoke"))',
  // LinearProgressIndicator fills its parent's width; bound it in a
  // SizedBox so it can lay out inside the Column.
  'LinearProgressIndicator':
      'SizedBox(width: 100.0, child: LinearProgressIndicator())',
  // RestageDraggableSheet hosts a DraggableScrollableSheet, which sizes
  // itself as a fraction of its parent's bounded height; wrap it in a
  // SizedBox so it can lay out inside the smoke test's Column. Requires
  // `child` (slot). At its default peek it lays out cleanly; the
  // drag/expand paths are covered by the widget's own tests.
  'RestageDraggableSheet': 'SizedBox(width: 100.0, height: 100.0, '
      'child: RestageDraggableSheet(child: Text(text: "smoke")))',
  // RestagePager hosts a PageView which wants unbounded constraints
  // in its scroll axis; bound it in a SizedBox so it can lay out
  // inside the smoke test's Column.
  'RestagePager': 'SizedBox(width: 100.0, height: 100.0, '
      'child: RestagePager(children: [Text(text: "smoke")]))',
  // RestageModalSheet requires `open` (scalar) + `child` (slot). With
  // open=false it returns the widget but renders nothing (a closed
  // sheet), so it lays out cleanly in the Column without an active
  // slide animation or the open-state Stack's unbounded expansion. The
  // open=true render/drag path is covered by the widget's own tests.
  'RestageModalSheet':
      'RestageModalSheet(open: false, child: Text(text: "smoke"))',
  // RestageRadioGroupString / RestageDropdownString require a non-empty
  // `items` option-list (each option a `{value, label}` map); the factories
  // assert on a missing list — the required-prop convention, like
  // RestagePager's children. A single option lays out cleanly in the Column.
  'RestageRadioGroupString':
      'RestageRadioGroupString(items: [{value: "a", label: "A"}], '
          'selected: "a")',
  'RestageDropdownString':
      'RestageDropdownString(items: [{value: "a", label: "A"}], '
          'selected: "a")',
  // RestageToggleButtons requires a non-empty `children` list (widget-list
  // slot) + the parallel `isSelected` boolean list; the factory asserts on a
  // missing `isSelected` (the required-prop convention). Equal lengths so the
  // wrapper's well-formed-wire path renders the real ToggleButtons.
  'RestageToggleButtons':
      'RestageToggleButtons(children: [Text(text: "A"), Text(text: "B")], '
          'isSelected: [true, false])',
  // RestageSegmentedButtonString requires a non-empty `items` option-list
  // (the same required-prop convention as the radio group / dropdown); the
  // `selected` slot is a stringList of the selected values (a list, not a
  // scalar). A single selected option lays out cleanly.
  'RestageSegmentedButtonString':
      'RestageSegmentedButtonString(items: [{value: "a", label: "A"}], '
          'selected: ["a"])',
  'OutlinedButton': 'OutlinedButton(child: Text(text: "smoke"))',
  'OutlinedButtonIcon': 'OutlinedButtonIcon(icon: Icon(iconCodepoint: 0xe87d), '
      'label: Text(text: "smoke"))',
  'Package': 'Package(slot: "primary", child: Text(text: "smoke"))',
  // Scrollbar's Stack-based layout asks for unbounded space; wrap in a
  // finite-sized SizedBox and give the inner child finite dims too.
  'Scrollbar': 'SizedBox(width: 100.0, height: 50.0, '
      'child: Scrollbar(child: SizedBox(width: 100.0, height: 50.0)))',
  'Slider': 'Slider(value: 0.5)',
  'Switch': 'Switch(value: false)',
  'SwitchListTile': 'SwitchListTile(value: false)',
  'Tab': 'Tab(text: "smoke")',
  'TextButton': 'TextButton(child: Text(text: "smoke"))',
  'TextButtonIcon': 'TextButtonIcon(icon: Icon(iconCodepoint: 0xe87d), '
      'label: Text(text: "smoke"))',
  // Tooltip needs an anchor child; without one, the build path's
  // MouseRegion / Semantics layers get unbounded constraints.
  'Tooltip': 'Tooltip(message: "smoke", child: Text(text: "smoke"))',
};

/// Factory-function defaults handle most missing properties (`source.v`
/// returns null, `optionalChild` returns null, `voidHandler` returns
/// null, `handler` returns null). Widgets that route through
/// `source.child(...)` are required and live in [_curatedMinimalRfwSource].
String _minimalRfwSourceFor(WidgetEntry entry) =>
    _curatedMinimalRfwSource[entry.name] ?? '${entry.name}()';

String _composeWalkerSource(Iterable<WidgetEntry> entries) {
  final fragments = entries.map(_minimalRfwSourceFor).join(',\n      ');
  return '''
import restage.core;
import restage.material;

widget Paywall = Column(
  children: [
      $fragments,
  ],
);
''';
}

/// Maps `entry.name` to the corresponding Flutter [Type]. Named-
/// constructor variants (Card.filled, FilledButton.tonal, etc.) map to
/// the same base class — Flutter has no distinct Type per named
/// constructor.
Type _flutterTypeFor(String entryName) {
  switch (entryName) {
    case 'ActionChip':
      return ActionChip;
    case 'AppBar':
      return AppBar;
    case 'Badge':
      return Badge;
    case 'Card':
    case 'CardFilled':
    case 'CardOutlined':
      return Card;
    case 'Checkbox':
      return Checkbox;
    case 'CheckboxListTile':
      return CheckboxListTile;
    case 'Chip':
      return Chip;
    case 'ChoiceChip':
      return ChoiceChip;
    case 'CircularProgressIndicator':
      return CircularProgressIndicator;
    case 'Divider':
      return Divider;
    case 'ElevatedButton':
      return ElevatedButton;
    case 'ExpansionTile':
      return ExpansionTile;
    case 'ExpressCheckoutButton':
      return ExpressCheckoutButton;
    case 'FilledButton':
    case 'FilledButtonTonal':
      return FilledButton;
    case 'FilterChip':
      return FilterChip;
    case 'FloatingActionButton':
      return FloatingActionButton;
    case 'Icon':
      return Icon;
    case 'IconButton':
      return IconButton;
    case 'InkWell':
      return InkWell;
    case 'LinearProgressIndicator':
      return LinearProgressIndicator;
    case 'ListTile':
      return ListTile;
    case 'RestagePager':
      return RestagePager;
    case 'RestageModalSheet':
      return RestageModalSheet;
    case 'RestageDraggableSheet':
      return RestageDraggableSheet;
    case 'RestageRadioGroupString':
      return RestageRadioGroup<String>;
    case 'RestageDropdownString':
      return RestageDropdown<String>;
    case 'RestageToggleButtons':
      return RestageToggleButtons;
    case 'RestageSegmentedButtonString':
      return RestageSegmentedButton<String>;
    case 'MaterialApp':
      return MaterialApp;
    case 'OutlinedButton':
    case 'OutlinedButtonIcon':
      return OutlinedButton;
    case 'Package':
      return Package;
    case 'Scaffold':
      return Scaffold;
    case 'Scrollbar':
      return Scrollbar;
    case 'Slider':
      return Slider;
    case 'Switch':
      return Switch;
    case 'SwitchListTile':
      return SwitchListTile;
    case 'Tab':
      return Tab;
    case 'TextButton':
    case 'TextButtonIcon':
      return TextButton;
    case 'TextField':
      return TextField;
    case 'Tooltip':
      return Tooltip;
  }
  throw StateError(
    'rendering_smoke_test: no Flutter Type mapping for catalog entry '
    '"$entryName" — add a case to _flutterTypeFor.',
  );
}

Runtime _buildRuntime(String paywallSource) => Runtime()
  ..update(
      _coreLibrary, _wrapLocalLibraryForSmoke(core.buildCoreWidgetLibrary()))
  ..update(
      _materialLibrary, _wrapLocalLibraryForSmoke(buildMaterialWidgetLibrary()))
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
  group('restage_material rendering smoke', () {
    testWidgets('every catalog widget renders into the tree', (tester) async {
      final allEntries = kRegistry.widgets;
      expect(allEntries, isNotEmpty,
          reason: 'kRegistry must have widgets for the smoke to be meaningful');

      final walkerEntries =
          allEntries.where((w) => !_rootOnlyEntries.contains(w.name)).toList();

      final runtime = _buildRuntime(_composeWalkerSource(walkerEntries));
      final data = DynamicContent();

      // Wrap in MaterialApp + Scaffold so widgets that need a Material
      // ancestor (AppBar, ListTile, Switch, Checkbox, IconButton) get
      // one. SingleChildScrollView prevents RenderFlex overflow when
      // many widgets stack in a Column inside the test viewport.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RemoteWidget(
                runtime: runtime,
                data: data,
                widget: const FullyQualifiedWidgetName(_rootLibrary, 'Paywall'),
                onEvent: (_, __) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      for (final entry in walkerEntries) {
        _expectRendered(entry);
      }
    });

    // MaterialApp and Scaffold need to be the root of their tree (they
    // expect unbounded constraints). Each gets its own testWidgets so
    // the surrounding wrapper can match what they expect.

    testWidgets('Scaffold renders as a Material-app root', (tester) async {
      await _pumpRootOnly(
        tester,
        entryName: 'Scaffold',
        paywallSource: '''
import restage.core;
import restage.material;
widget Paywall = Scaffold(body: Text(text: "smoke"));
''',
        wrap: (paywall) => MaterialApp(home: paywall),
      );
    });

    testWidgets('MaterialApp renders as the tree root', (tester) async {
      await _pumpRootOnly(
        tester,
        entryName: 'MaterialApp',
        paywallSource: '''
import restage.core;
import restage.material;
widget Paywall = MaterialApp(home: Text(text: "smoke"));
''',
        wrap: (paywall) =>
            Directionality(textDirection: TextDirection.ltr, child: paywall),
      );
    });
  });
}

/// Renders one root-only catalog entry, wrapping the rfw-rendered
/// paywall in a per-entry Flutter widget that supplies whatever
/// ancestor the entry requires.
Future<void> _pumpRootOnly(
  WidgetTester tester, {
  required String entryName,
  required String paywallSource,
  required Widget Function(Widget paywall) wrap,
}) async {
  final entry = kRegistry.findByName(entryName, WidgetLibrary.material)!;
  final runtime = _buildRuntime(paywallSource);
  await tester.pumpWidget(
    wrap(
      RemoteWidget(
        runtime: runtime,
        data: DynamicContent(),
        widget: const FullyQualifiedWidgetName(_rootLibrary, 'Paywall'),
        onEvent: (_, __) {},
      ),
    ),
  );
  await tester.pump();
  _expectRendered(entry);
}
