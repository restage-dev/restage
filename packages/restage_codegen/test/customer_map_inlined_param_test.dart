// A map bound to an INLINED custom widget's PARAMETER is refused at build
// time.
//
// A map-shaped property is carried on the wire as an entry list
// (`[{key: k, value: v}]`) so its keys survive; the generated factory
// reconstructs the Dart `Map` from that list. A custom widget's parameter
// carries no such shape — only a numeric flag — so a map bound there lowers
// through the GENERIC map arm to the natural key-keyed spelling `{k: v}`,
// while the property it feeds inside the definition body still decodes the
// entry list.
//
// Nothing downstream can tell the two apart. The emitted blob parses, catalog
// validation passes, the bytes round-trip, and the factory's list check fails
// only when the surface renders — the worst failure shape this transpiler
// admits, because a build that says nothing is a build the author trusts. The
// refusal below converts it into a readable build-time error.
//
// The conditional case is not a duplicate of the literal case: the check reads
// the ARGUMENT expression rather than the branches, so a conditional whose
// branches are maps is caught once. The single-diagnostic assertion is what
// pins that; a per-branch check would pass every other assertion here while
// reporting the same problem twice.
//
// Records are deliberately NOT refused. A record literal lowers to the same
// label-keyed spelling its decoder reads, so it carries its own shape and
// crosses this seam intact. The record case below pins that boundary, so
// widening this refusal to every structured value fails here rather than
// silently rejecting authoring that works.
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/paywall_helpers.dart';
import 'package:restage_codegen/src/widget_classifier.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// A catalog widget with one map-shaped property, and one whose property is
/// the record marker — the two structured shapes a parameter can carry.
final Catalog _catalog = catalogWith([
  entry(
    name: 'FieldNotes',
    category: WidgetCategory.decoration,
    flutterType: 'package:restage_codegen/_e2e_probe.dart#FieldNotes',
    properties: [
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'glossary',
        type: PropertyType.unknown,
        description: '',
        required: true,
        valueShape: ScalarShape.opaqueStringKeyedMap(),
      ),
    ],
  ),
  entry(
    name: 'Badge',
    category: WidgetCategory.decoration,
    flutterType: 'package:restage_codegen/_e2e_probe.dart#Badge',
    properties: [
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'spec',
        type: PropertyType.unknown,
        description: '',
        required: true,
        valueShape: ScalarShape.opaqueRecord(),
      ),
    ],
  ),
]);

const String _stubs = '''
$kClassifierStubs

class FieldNotes extends StatelessWidget {
  const FieldNotes({required this.glossary});
  final Map<String, String> glossary;
  Widget build(BuildContext context) => const Widget();
}

class Badge extends StatelessWidget {
  const Badge({required this.spec});
  final ({String label, int count}) spec;
  Widget build(BuildContext context) => const Widget();
}
''';

/// A custom widget that takes a map and forwards it to the map-shaped slot —
/// the shape whose call site this refusal guards.
const String _notesWidget = '''
@RestageWidget(name: 'AcmeNotes',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout, description: 'n')
class AcmeNotes extends StatelessWidget {
  const AcmeNotes({required this.notes});
  @RestageProperty(description: 'n')
  final Map<String, String> notes;
  Widget build(BuildContext context) => FieldNotes(glossary: notes);
}
''';

/// The record-shaped sibling, which must keep working.
const String _badgeWidget = '''
@RestageWidget(name: 'AcmeBadge',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout, description: 'b')
class AcmeBadge extends StatelessWidget {
  const AcmeBadge({required this.spec});
  @RestageProperty(description: 's')
  final ({String label, int count}) spec;
  Widget build(BuildContext context) => Badge(spec: spec);
}
''';

void main() {
  test('a map literal at an inlined parameter is refused', () async {
    final r = await _translate(
      '$_notesWidget\n'
      "Object x() => AcmeNotes(notes: <String, String>{'a': '1'});",
    );

    expect(r.issues, hasLength(1));
    expect(r.issues.single.code, IssueCode.unsupportedCollectionFlow);
    // The diagnostic must name the property and the widget, or an author
    // cannot find the call site it refers to.
    expect(r.issues.single.message, contains("'notes'"));
    expect(r.issues.single.message, contains("'AcmeNotes'"));
    // Paired absence: the refusal exists to keep the key-keyed spelling out of
    // the blob. Asserting only the diagnostic would stay green if the argument
    // were emitted alongside it.
    expect(r.dsl, isNot(contains('a: "1"')));
  });

  test('a conditional of maps is refused ONCE, at the argument', () async {
    final r = await _translate(
      '$_notesWidget\nconst bool kAnnual = true;\n'
      "Object x() => AcmeNotes(notes: kAnnual ? <String, String>{'a': '1'} "
      ": <String, String>{'b': '2'});",
    );

    // The single diagnostic is the observable that the check reads the
    // argument rather than recursing into the branches. A per-branch check
    // reports the same problem twice, which reads to an author as two
    // separate mistakes.
    expect(r.dsl, isNot(contains('a: "1"')));
    expect(r.dsl, isNot(contains('b: "2"')));
    expect(r.issues, hasLength(1));
    expect(r.issues.single.code, IssueCode.unsupportedCollectionFlow);
  });

  test('the refusal is a build error, not an informational deferral', () async {
    // The whole value of this guard is that the build STOPS. An informational
    // code would leave the build green and the guard decorative, so pin the
    // disposition rather than only the code.
    final r = await _translate(
      '$_notesWidget\n'
      "Object x() => AcmeNotes(notes: <String, String>{'a': '1'});",
    );

    expect(r.issues.single.code.isInformational, isFalse);
  });

  group('the refusal is scoped to the parameter seam', () {
    test('the same map AT its declaring slot still routes to the entry list',
        () async {
      // The control. Were the gate reading the value's type instead of the
      // parameter binding, this would refuse too — and the refusal would have
      // removed the feature it was written to protect.
      final r = await _translate(
        "Object x() => FieldNotes(glossary: <String, String>{'a': '1'});",
      );

      expect(r.issues, isEmpty);
      expect(r.dsl, 'FieldNotes(glossary: [{key: "a", value: "1"}])');
    });

    test('a record at an inlined parameter is unaffected', () async {
      final r = await _translate(
        "$_badgeWidget\nObject x() => AcmeBadge(spec: (label: 'p', count: 2));",
      );

      expect(r.issues, isEmpty);
      expect(r.dsl, 'AcmeBadge(spec: {count: 2, label: "p"})');
    });
  });
}

/// The translation of [body] against [_catalog], with custom widgets
/// classified the way a real build classifies them.
Future<({String dsl, List<Issue> issues})> _translate(String body) async {
  const rootPackage = 'restage_codegen';
  final readerWriter =
      await readerWriterWithFilesystemSources(rootPackage: rootPackage);
  const assetKey = '$rootPackage|lib/_e2e_probe.dart';
  final source = '$_stubs\n\n$body';
  readerWriter.testing.writeString(AssetId.parse(assetKey), source);

  ({String dsl, List<Issue> issues})? result;
  await testBuilder(
    _TranslateBuilder((r) => result = r),
    {assetKey: source},
    rootPackage: rootPackage,
    readerWriter: readerWriter,
  );
  final resolved = result;
  if (resolved == null) {
    throw StateError('the translation probe did not run');
  }
  return resolved;
}

/// Runs classify → translate over the probe library's `x` expression.
class _TranslateBuilder implements Builder {
  _TranslateBuilder(this.onResult);

  final void Function(({String dsl, List<Issue> issues})) onResult;

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.translated'],
      };

  @override
  Future<void> build(BuildStep step) async {
    if (!step.inputId.path.endsWith('_e2e_probe.dart')) return;
    final library = await step.inputLibrary;
    final fn = library.topLevelFunctions.firstWhere((f) => f.name == 'x');
    final resolved = await library.session.getResolvedLibraryByElement(library);
    if (resolved is! ResolvedLibraryResult) {
      throw StateError('the translation probe library did not resolve');
    }
    final node = resolved.getFragmentDeclaration(fn.firstFragment)?.node;
    final body =
        node is FunctionDeclaration ? node.functionExpression.body : null;
    if (body is! ExpressionFunctionBody) {
      throw StateError('the translation probe needs `Object x() => <root>;`');
    }

    final helpers = HelperRegistry()..registerAll(paywallHelpers);
    final classification = await classifyReferencedCustomWidgets(
      rootExpressions: [body.expression],
      catalog: _catalog,
      helpers: helpers,
      astNodeFor: (fragment) =>
          step.resolver.astNodeFor(fragment, resolve: true),
    );
    final translation = ExpressionTranslator(
      catalog: _catalog,
      helpers: helpers,
      customWidgetClassifications: classification.classifications,
      customWidgetBlueprints: classification.blueprints,
    ).translate(body.expression);

    onResult((dsl: translation.dsl, issues: translation.issues));
  }
}
