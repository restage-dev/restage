import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_event_lowering.dart';
import 'package:restage_codegen/src/a2ui/a2ui_schema_node.dart';
import 'package:restage_codegen/src/a2ui/a2ui_shape_reflector.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// The interactivity proof — the real-reflector + annotation-read + real-emit
/// legs.
///
/// Resolves the REAL committed interactive `@RestageWidget`-style fixture in
/// `restage_a2ui` with the analyzer, then produces BOTH analyzer-fed seams the
/// way the (deferred) build phase eventually will:
///
/// - the EVENT seam — `reflectType` over each callback constructor parameter →
///   its [A2uiCallbackSignature] (the same reflector leg the data-shape proof
///   uses for rich shapes);
/// - the PAIRING seam — each callback field's
///   `@RestageProperty(writeBackValue:)` annotation metadata
///   (`field.metadata` → the `RestageProperty` annotation →
///   `computeConstantValue().getField('writeBackValue')`), the production-read
///   leg the multi-control case exercises (condition #2: real reflector + real
///   annotation metadata, not a hand-constructed seam).
///
/// It then runs the catalog through the PRODUCTION emitter and regenerates the
/// committed `.g.dart` that `restage_a2ui` renders+drives against real genui.
/// The only test-boundary normalization is rewriting the resolved `file://`
/// fixture URI to the relative import the committed file uses. (The reflector
/// is not yet build-wired; the build-phase auto-wiring — all three read legs —
/// is a tracked follow-up.)
const _fixtureRelativePath =
    '../restage_a2ui/test/generated/interactive_fixture.dart';

/// The committed generated catalog lives in restage_a2ui (which has the genui
/// dependency), beside the fixture it imports.
const _generatedPath =
    '../restage_a2ui/test/generated/interactive_catalog.g.dart';

/// The import the committed `.g.dart` uses for the fixture (the resolved
/// `file://` URI is normalized to this at the test boundary).
const _fixtureImport = 'interactive_fixture.dart';

/// One value property: its catalog name and JSON-shape property type.
typedef _ValueProp = (String name, PropertyType type);

/// Each proof widget: its genui catalog name, the fixture widget class the
/// emitter constructs, the value properties carried by the catalog, and the
/// callback parameters the reflector/annotation legs read.
const _interactiveWidgets = <({
  String catalogName,
  String widgetClass,
  List<_ValueProp> valueProps,
  List<String> callbacks,
})>[
  // Auto single-pair: one ValueChanged<int> + one matching int value prop, no
  // annotation (the zero-annotation acceptance bar).
  (
    catalogName: 'QuickCheck',
    widgetClass: 'QuickCheckFixture',
    valueProps: [('selected', PropertyType.integer)],
    callbacks: ['onSelected'],
  ),
  // List write-back: ValueChanged<List<String>> + a stringList value prop.
  (
    catalogName: 'MultiSelect',
    widgetClass: 'MultiSelectFixture',
    valueProps: [('chosen', PropertyType.stringList)],
    callbacks: ['onChosen'],
  ),
  // Dispatch: a VoidCallback (no value to control).
  (
    catalogName: 'ActionButton',
    widgetClass: 'ActionButtonFixture',
    valueProps: [('label', PropertyType.string)],
    callbacks: ['onPressed'],
  ),
  // Multi-control: auto single-pair fails (two callbacks); each callback's
  // `@RestageProperty(writeBackValue:)` annotation names its value prop.
  (
    catalogName: 'Range',
    widgetClass: 'RangeFixture',
    valueProps: [('low', PropertyType.integer), ('high', PropertyType.integer)],
    callbacks: ['onLow', 'onHigh'],
  ),
];

Future<ResolvedLibraryResult> _resolveFixture() async {
  final abs = File('${Directory.current.path}/$_fixtureRelativePath')
      .resolveSymbolicLinksSync();
  final collection = AnalysisContextCollection(includedPaths: [abs]);
  final context = collection.contextFor(abs);
  final resolved = await context.currentSession.getResolvedLibrary(abs);
  if (resolved is! ResolvedLibraryResult) {
    throw StateError('failed to resolve the fixture: $resolved');
  }
  return resolved;
}

/// The resolved fixture class named [widgetClass] (fails loud if absent).
ClassElement _classFor(ResolvedLibraryResult library, String widgetClass) =>
    library.element.classes.firstWhere(
      (c) => c.name == widgetClass,
      orElse: () => throw StateError("no class '$widgetClass' in the fixture"),
    );

/// The fixture library's URI — derived per-class as `cls.library.identifier`
/// (mirroring the production `flutterType` derivation), used to spell the
/// catalog `flutterType` so the emitter imports + constructs the real fixture.
/// The fixture is one library by construction, so any class's identifier is the
/// same URI.
String _fixtureUri(ResolvedLibraryResult library) =>
    _classFor(library, _interactiveWidgets.first.widgetClass)
        .library
        .identifier;

/// The EVENT seam — `reflectType` over each callback constructor parameter into
/// its classified [A2uiCallbackSignature] (the reflector production-read leg).
A2uiEventSeam _eventSeam(ResolvedLibraryResult library) {
  final seam = <(String, String), A2uiCallbackSignature>{};
  for (final w in _interactiveWidgets) {
    final cls = _classFor(library, w.widgetClass);
    final ctor = cls.constructors.firstWhere(
      (c) => c.name == null || c.name!.isEmpty || c.name == 'new',
      orElse: () =>
          throw StateError("no default constructor on '${w.widgetClass}'"),
    );
    for (final callback in w.callbacks) {
      final formal = ctor.formalParameters.firstWhere(
        (p) => p.name == callback,
        orElse: () =>
            throw StateError("no parameter '$callback' on '${w.widgetClass}'"),
      );
      final result = reflectType(formal.type);
      if (result is! A2uiShapeEventSurface) {
        throw StateError(
          '${w.widgetClass}.$callback should reflect to an event surface, '
          'got $result',
        );
      }
      seam[(w.catalogName, callback)] = result.signature;
    }
  }
  return seam;
}

/// The PAIRING seam — each callback field's `@RestageProperty(writeBackValue:)`
/// annotation metadata (the annotation production-read leg). A callback with no
/// `writeBackValue` is absent from the seam (auto single-pair / dispatch).
A2uiPairingSeam _pairingSeam(ResolvedLibraryResult library) {
  final seam = <(String, String), String>{};
  for (final w in _interactiveWidgets) {
    final cls = _classFor(library, w.widgetClass);
    for (final callback in w.callbacks) {
      final field = cls.fields.firstWhere(
        (f) => f.name == callback,
        orElse: () =>
            throw StateError("no field '$callback' on '${w.widgetClass}'"),
      );
      final annotation = firstAnnotation(field, 'RestageProperty');
      final writeBack = annotation
          ?.computeConstantValue()
          ?.getField('writeBackValue')
          ?.toStringValue();
      if (writeBack != null) {
        seam[(w.catalogName, callback)] = writeBack;
      }
    }
  }
  return seam;
}

/// A test-built catalog whose entries name the fixture widget classes (the
/// emitter constructs them) and carry each value property + each callback (as a
/// required event property the seams then lower).
Catalog _proofCatalog(String fixtureUri) => catalogWith([
      for (final w in _interactiveWidgets)
        entry(
          name: w.catalogName,
          flutterType: '$fixtureUri#${w.widgetClass}',
          properties: [
            for (final v in w.valueProps) prop(v.$1, v.$2, required: true),
            for (final c in w.callbacks)
              prop(c, PropertyType.event, required: true),
          ],
        ),
    ]);

/// The production-emitted interactive catalog, normalized at the test boundary
/// (the resolved `file://` fixture URI → the committed relative import).
String _emitNormalized(ResolvedLibraryResult library) {
  final fixtureUri = _fixtureUri(library);
  final emitted = emitA2uiCatalogDart(
    _proofCatalog(fixtureUri),
    eventSeam: _eventSeam(library),
    pairingSeam: _pairingSeam(library),
  );
  return formatGeneratedDart(
    emitted.replaceAll(fixtureUri, _fixtureImport),
  ).trimRight();
}

void main() {
  // The fixture is immutable, so it is analyzer-resolved ONCE for the whole
  // file (the resolution is the proof's dominant cost); every group derives its
  // seams/emit from this shared result.
  late ResolvedLibraryResult library;

  setUpAll(() async {
    library = await _resolveFixture();
  });

  group('interactive proof — the real reflector + annotation reads', () {
    test('the event seam reflects every callback signature', () {
      final seam = _eventSeam(library);
      expect(
        seam[('QuickCheck', 'onSelected')],
        const A2uiCallbackWriteBack(
          A2uiScalarType.integer,
          nullable: false,
          isList: false,
        ),
      );
      expect(
        seam[('MultiSelect', 'onChosen')],
        const A2uiCallbackWriteBack(
          A2uiScalarType.string,
          nullable: false,
          isList: true,
        ),
      );
      expect(seam[('ActionButton', 'onPressed')], const A2uiCallbackDispatch());
      expect(
        seam[('Range', 'onLow')],
        const A2uiCallbackWriteBack(
          A2uiScalarType.integer,
          nullable: false,
          isList: false,
        ),
      );
      expect(
        seam[('Range', 'onHigh')],
        const A2uiCallbackWriteBack(
          A2uiScalarType.integer,
          nullable: false,
          isList: false,
        ),
      );
    });

    test(
        'the pairing seam reads ONLY the annotated multi-control callbacks '
        '(@RestageProperty(writeBackValue:) metadata)', () {
      final seam = _pairingSeam(library);
      // Exactly the two annotated Range callbacks — the auto-pair / dispatch
      // callbacks carry no writeBackValue and are absent.
      expect(seam, {
        ('Range', 'onLow'): 'low',
        ('Range', 'onHigh'): 'high',
      });
    });
  });

  group('interactive proof — the production emitter regenerates the catalog',
      () {
    test('the committed generated interactive catalog is current (drift guard)',
        () {
      final normalized = _emitNormalized(library);

      expect(
        normalized,
        contains("import '$_fixtureImport' as p0;"),
        reason: 'the emitter should import + prefix the fixture library',
      );
      expect(
        normalized,
        contains('p0.QuickCheckFixture('),
        reason: 'the widget constructor should carry the import prefix',
      );

      final file = File(_generatedPath);
      if (Platform.environment['REGEN_A2UI_DART_GOLDEN'] == '1') {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync('$normalized\n');
      }
      expect(
        file.existsSync(),
        isTrue,
        reason: 'run with REGEN_A2UI_DART_GOLDEN=1 to generate $_generatedPath',
      );
      expect(
        normalized,
        file.readAsStringSync().trimRight(),
        reason: 'the committed interactive catalog has drifted from the '
            'emitter; regenerate with REGEN_A2UI_DART_GOLDEN=1',
      );
    });
  });

  group('interactive proof — scope-correctness vocabulary (the inert subset)',
      () {
    // A codegen-correctness guard: the emitter produces EXACTLY the designed
    // Phase-2 interactive vocabulary — write-back
    // (`dataContext.update` on a `{path}` binding), dispatch (a compile-fixed
    // `dispatchEvent(UserActionEvent)`), and the value-reference oneOf schema —
    // and NONE of the genui producer-driven action surface (a genui `action()`
    // schema, a producer `functionCall` action, or a dynamic/producer-supplied
    // event name). No compliance positioning: A2UI is an emit target.
    late String source;

    setUpAll(() {
      source = _emitNormalized(library);
    });

    test('it emits the write-back vocabulary (path-bound read + update)', () {
      expect(source, contains("value: {'path': _restageA2uiPath_selected}"));
      expect(
        source,
        contains(
          'update(DataPath(_restageA2uiPath_selected), _restageA2uiNext)',
        ),
      );
    });

    test('it emits the dispatch vocabulary with a COMPILE-FIXED event name',
        () {
      expect(source, contains('itemContext.dispatchEvent(UserActionEvent('));
      expect(source, contains("name: 'onPressed'"));
      expect(source, contains('sourceComponentId: itemContext.id'));
    });

    test('it emits the value-reference (oneOf) schema for a write-back value',
        () {
      expect(source, contains('oneOf:'));
      expect(source, contains("'path': S.string()"));
    });

    test('it emits NONE of the genui producer-driven action surface', () {
      // No genui schema helper (we replicate the value-reference shape raw),
      // and therefore no genui `action()` / producer `functionCall` ACTION.
      expect(source, isNot(contains('A2uiSchemas')));
      expect(source, isNot(contains('action(')));
      // The dispatch event name is a fixed string literal, never a runtime
      // value / producer-supplied name.
      expect(source, isNot(contains('name: data[')));
      expect(source, isNot(contains(r'name: $')));
    });
  });

  group('interactive proof — multi-control distinct paths + census', () {
    late A2uiDartCatalogPlan plan;
    late String source;

    setUpAll(() {
      plan = classifyA2uiCatalogDart(
        _proofCatalog(_fixtureUri(library)),
        eventSeam: _eventSeam(library),
        pairingSeam: _pairingSeam(library),
      );
      source = _emitNormalized(library);
    });

    test('the multi-control widget allocates two DISTINCT write-back paths',
        () {
      // The explicit pairings (low/high) resolve to two distinct data paths —
      // no cross-wiring. (A duplicate path is a fail-loud throw by construction
      // — see _writeBackPreludeStatements.)
      expect(source, contains(r"'${itemContext.id}.low'"));
      expect(source, contains(r"'${itemContext.id}.high'"));
      expect(source, contains("value: {'path': _restageA2uiPath_low}"));
      expect(source, contains("value: {'path': _restageA2uiPath_high}"));
      expect(
        source,
        contains('update(DataPath(_restageA2uiPath_low), _restageA2uiNext)'),
      );
      expect(
        source,
        contains('update(DataPath(_restageA2uiPath_high), _restageA2uiNext)'),
      );
    });

    test('every fixture widget lowers fully — no drop, no omission', () {
      // The full from-fixture census: all four widgets emit, with every
      // interactive callback lowered (no scope-out reached on the proof set).
      expect(
        plan.widgets.map((w) => w.entry.name),
        containsAll(['QuickCheck', 'MultiSelect', 'ActionButton', 'Range']),
      );
      expect(plan.coverage.droppedWidgets, isEmpty);
      expect(plan.coverage.omittedFields, isEmpty);
    });

    test('the interactive census: write-backs and dispatches per widget', () {
      A2uiDartWidgetPlan widget(String name) =>
          plan.widgets.firstWhere((w) => w.entry.name == name);
      expect(widget('QuickCheck').writeBacks, hasLength(1));
      expect(widget('QuickCheck').dispatches, isEmpty);
      expect(widget('MultiSelect').writeBacks, hasLength(1));
      expect(widget('ActionButton').dispatches, hasLength(1));
      expect(widget('ActionButton').writeBacks, isEmpty);
      // The multi-control widget carries BOTH explicit write-backs.
      expect(widget('Range').writeBacks, hasLength(2));
    });
  });
}
