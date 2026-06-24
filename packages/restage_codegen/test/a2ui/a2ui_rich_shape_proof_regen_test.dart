import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_schema_node.dart';
import 'package:restage_codegen/src/a2ui/a2ui_shape_reflector.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// The data-shape fidelity proof — the real-reflector + real-emit legs.
///
/// Resolves the REAL committed `@RestageWidget`-style fixture in `restage_a2ui`
/// with the analyzer, reflects each widget's data parameter into a rich shape
/// node via the REAL reflector (condition #2: real reflector, not
/// hand-constructed IR), runs the nodes through the PRODUCTION emitter, and
/// regenerates the committed `.g.dart` that `restage_a2ui` renders against real
/// genui. The only test-boundary normalization is rewriting the resolved
/// `file://` fixture URI to the relative import the committed file uses — the
/// uniform-prefix emission (`pN.Type`) is untouched, so the render proves the
/// real prefix output. (The reflector is not yet build-wired; the build-phase
/// auto-wiring is a tracked follow-up.)
const _fixtureRelativePath =
    '../restage_a2ui/test/generated/rich_shape_fixture.dart';

/// The committed generated catalog lives in restage_a2ui (which has the genui
/// dependency), beside the fixture it imports.
const _generatedPath =
    '../restage_a2ui/test/generated/rich_shape_catalog.g.dart';

/// The import the committed `.g.dart` uses for the fixture (the resolved
/// `file://` URI is normalized to this at the test boundary).
const _fixtureImport = 'rich_shape_fixture.dart';

/// Each proof widget: its genui catalog name, the fixture widget class the
/// emitter constructs, and the single data parameter reflected for it.
const _proofWidgets =
    <({String catalogName, String widgetClass, String param})>[
  (catalogName: 'PlanCard', widgetClass: 'PlanCardFixture', param: 'plan'),
  (
    catalogName: 'FeatureGrid',
    widgetClass: 'FeatureGridFixture',
    param: 'features',
  ),
  (catalogName: 'Glossary', widgetClass: 'GlossaryFixture', param: 'terms'),
  (catalogName: 'MetaBar', widgetClass: 'MetaBarFixture', param: 'meta'),
  (catalogName: 'LinkCard', widgetClass: 'LinkCardFixture', param: 'link'),
  (
    catalogName: 'CommentThread',
    widgetClass: 'CommentThreadFixture',
    param: 'root',
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

/// Reflects [param] of [widgetClass] in [library] into its data-shape node,
/// failing the test if the reflector scoped it out (the framework `key`
/// parameter is never reflected — the test reflects only the data parameter).
A2uiSchemaNode _reflectDataParam(
  ResolvedLibraryResult library,
  String widgetClass,
  String param,
) {
  final element = library.element.classes.firstWhere(
    (c) => c.name == widgetClass,
    orElse: () => throw StateError("no class '$widgetClass' in the fixture"),
  );
  final ctor = element.constructors.firstWhere(
    (c) => c.name == null || c.name!.isEmpty || c.name == 'new',
    orElse: () => throw StateError("no default constructor on '$widgetClass'"),
  );
  final formal = ctor.formalParameters.firstWhere(
    (p) => p.name == param,
    orElse: () => throw StateError("no parameter '$param' on '$widgetClass'"),
  );
  final result = reflectType(formal.type);
  expect(
    result,
    isA<A2uiShapeResolved>(),
    reason: '$widgetClass.$param should resolve, got $result',
  );
  return (result as A2uiShapeResolved).node;
}

/// The reflector's rich-shape map keyed on (catalog name, data parameter).
A2uiRichShapes _richShapes(ResolvedLibraryResult library) => {
      for (final w in _proofWidgets)
        (w.catalogName, w.param):
            _reflectDataParam(library, w.widgetClass, w.param),
    };

/// The resolved fixture's library URI (carried on a reflected class node).
String _fixtureUri(A2uiRichShapes shapes) {
  final node = shapes[('PlanCard', 'plan')]! as ObjectNode;
  return (node.construction! as A2uiClassConstruction).libraryUri!;
}

/// A test-built catalog whose entries name the fixture widget classes (the
/// emitter constructs them) and carry the single required data property each.
Catalog _proofCatalog(String fixtureUri) => catalogWith([
      for (final w in _proofWidgets)
        entry(
          name: w.catalogName,
          flutterType: '$fixtureUri#${w.widgetClass}',
          properties: [prop(w.param, PropertyType.structured, required: true)],
        ),
    ]);

void main() {
  group('rich-shape proof — the real reflector reads the real fixture', () {
    late ResolvedLibraryResult library;

    setUpAll(() async {
      library = await _resolveFixture();
    });

    test(
        'the nested data class reflects with its fields, required set, '
        'nullable enum + nullable string', () {
      final node = _reflectDataParam(library, 'PlanCardFixture', 'plan');
      expect(node, isA<ObjectNode>());
      final object = node as ObjectNode;
      final construction = object.construction;
      expect(construction, isA<A2uiClassConstruction>());
      expect((construction! as A2uiClassConstruction).dartTypeName, 'PlanTier');
      expect(object.nullable, isFalse);
      expect(
        object.fields.keys,
        containsAll(['name', 'price', 'badge', 'tagline']),
      );
      expect(object.required, {'name', 'price'});
      expect(object.fields['name'], const ScalarNode(A2uiScalarType.string));
      expect(object.fields['price'], const ScalarNode(A2uiScalarType.number));
      final badge = object.fields['badge'];
      expect(badge, isA<EnumNode>());
      expect((badge! as EnumNode).members, ['none', 'popular', 'bestValue']);
      expect(badge.nullable, isTrue);
      expect(
        object.fields['tagline'],
        const ScalarNode(A2uiScalarType.string, nullable: true),
      );
    });

    test('the list-of-objects reflects as a ListNode over an ObjectNode', () {
      final node = _reflectDataParam(library, 'FeatureGridFixture', 'features');
      expect(node, isA<ListNode>());
      final element = (node as ListNode).element;
      expect(element, isA<ObjectNode>());
      final object = element as ObjectNode;
      expect(
        (object.construction! as A2uiClassConstruction).dartTypeName,
        'PlanFeature',
      );
      expect(object.required, {'label', 'included'});
      expect(
        object.fields['included'],
        const ScalarNode(A2uiScalarType.boolean),
      );
    });

    test('the String-keyed map reflects as a MapNode', () {
      final node = _reflectDataParam(library, 'GlossaryFixture', 'terms');
      expect(node, isA<MapNode>());
      expect(
        (node as MapNode).valueType,
        const ScalarNode(A2uiScalarType.string),
      );
    });

    test('the named record reflects as a record ObjectNode', () {
      final node = _reflectDataParam(library, 'MetaBarFixture', 'meta');
      expect(node, isA<ObjectNode>());
      final object = node as ObjectNode;
      expect(object.construction, isA<A2uiRecordConstruction>());
      expect(object.required, {'title', 'count'});
      expect(object.fields['title'], const ScalarNode(A2uiScalarType.string));
      expect(object.fields['count'], const ScalarNode(A2uiScalarType.integer));
    });

    test('the path-field object reflects (the binding-sentinel hazard shape)',
        () {
      final node = _reflectDataParam(library, 'LinkCardFixture', 'link');
      expect(node, isA<ObjectNode>());
      final object = node as ObjectNode;
      expect(
        (object.construction! as A2uiClassConstruction).dartTypeName,
        'LinkData',
      );
      // The field literally named `path` is carried as data, not a binding.
      expect(object.fields['path'], const ScalarNode(A2uiScalarType.string));
      expect(object.required, {'path', 'label'});
    });

    test(
        'the self-recursive object reflects with a RefNode back-edge on the '
        'nullable nested-class field', () {
      final node = _reflectDataParam(library, 'CommentThreadFixture', 'root');
      expect(node, isA<ObjectNode>());
      final object = node as ObjectNode;
      final construction = object.construction! as A2uiClassConstruction;
      expect(construction.dartTypeName, 'Comment');
      expect(object.defId, isNotNull);
      expect(object.fields['text'], const ScalarNode(A2uiScalarType.string));
      // `reply` is the same type → a RefNode (cycle) back to the object's
      // defId, and nullable.
      final reply = object.fields['reply'];
      expect(reply, isA<RefNode>());
      expect((reply! as RefNode).defId, object.defId);
      expect(reply.nullable, isTrue);
      // `text` is required, `reply` (optional + nullable) is not.
      expect(object.required, {'text'});
    });

    test('the proof covers exactly the fixture widgets', () {
      final widgetNames = library.element.classes
          .map((c) => c.name)
          .where((n) => n != null && n.endsWith('Fixture'))
          .toSet();
      expect(widgetNames, {for (final w in _proofWidgets) w.widgetClass});
    });
  });

  group('rich-shape proof — the production emitter regenerates the catalog',
      () {
    test('the committed generated rich-shape catalog is current (drift guard)',
        () async {
      final library = await _resolveFixture();
      final shapes = _richShapes(library);
      final fixtureUri = _fixtureUri(shapes);
      final catalog = _proofCatalog(fixtureUri);

      final emitted = emitA2uiCatalogDart(catalog, richShapes: shapes);
      // Test-boundary URI normalization (URI string only): the resolved
      // `file://` fixture URI → the relative import the committed file uses.
      // The uniform-prefix spellings (`pN.Type`) are untouched, so the render
      // proof exercises the REAL prefix emission; re-formatting collapses the
      // (now short) import the long file:// URI had wrapped across two lines.
      final normalized = formatGeneratedDart(
        emitted.replaceAll(fixtureUri, _fixtureImport),
      ).trimRight();
      expect(
        normalized,
        contains("import '$_fixtureImport' as p0;"),
        reason: 'the emitter should import + prefix the fixture library',
      );
      expect(
        normalized,
        contains('p0.PlanCardFixture('),
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
        reason: 'the committed rich-shape catalog has drifted from the '
            'emitter; regenerate with REGEN_A2UI_DART_GOLDEN=1',
      );
    });
  });
}
