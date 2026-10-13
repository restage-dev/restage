import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:restage_codegen/src/build_body.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/measurement/measurement_source_discovery.dart';
import 'package:restage_codegen/src/onboarding/onboarding_helpers.dart';
import 'package:restage_codegen/src/onboarding/onboarding_source_visitor.dart';
import 'package:restage_codegen/src/source_state.dart';
import 'package:restage_codegen/src/source_visitor.dart';
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:restage_codegen/src/widget_classifier.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _customLibrary = WidgetLibrary.custom('acme.design');
final _sourceId = AssetId('app', 'lib/surface.dart');

Catalog _catalog({bool publishWidgets = true}) => catalogWith([
      entry(
        name: 'Text',
        flutterType: 'package:flutter/widgets.dart#Text',
        properties: [prop('data', PropertyType.string, positional: true)],
      ),
      entry(
        name: 'Column',
        flutterType: 'package:flutter/widgets.dart#Column',
        childrenSlot: ChildrenSlot.list,
        properties: [prop('children', PropertyType.widgetList)],
      ),
      if (publishWidgets)
        entry(
          name: 'Badge',
          library: _customLibrary,
          flutterType: 'package:acme_kit/kit.dart#Badge',
          properties: const [],
        ),
    ]);

void main() {
  test('only custom widget packages admit dependency helpers', () {
    final catalog = catalogWith([
      for (final type in [
        'package:acme_kit/kit.dart#Badge',
        'package:acme_kit/other.dart#Card',
        'package:second_kit/widgets.dart#Card',
        'package:restage_brand/widgets.dart#BrandWidget',
        'file:///widgets.dart#LocalWidget',
      ])
        entry(
          name: type.split('#').last,
          library: _customLibrary,
          flutterType: type,
          properties: const [],
        ),
      entry(
        name: 'BuiltIn',
        flutterType: 'package:unrelated/widgets.dart#BuiltIn',
        properties: const [],
      ),
    ]);
    expect(
      artifactHelperPackages(catalog),
      {'acme_kit', 'second_kit', 'restage_brand'},
    );
    expect(artifactHelperPackages(kEmptyCatalog), isEmpty);
  });

  test('custom packages with the Restage prefix admit helpers', () async {
    final catalog = catalogWith([
      entry(
        name: 'BrandWidget',
        library: _customLibrary,
        flutterType: 'package:restage_brand/widgets.dart#BrandWidget',
        properties: const [],
      ),
    ]);
    final admitted = artifactHelperPackages(catalog);
    expect(identical(admitted, artifactHelperPackages(catalog)), isTrue);
    expect(() => admitted.add('unrelated'), throwsUnsupportedError);
    await _resolve((resolver, library) async {
      final expression = await _build(resolver, library, 'BrandProbe');
      final calls = _Calls();
      expression.accept(calls);
      expect(calls.calls, hasLength(1));
      expect(
        isArtifactHelperInvocation(
          calls.calls.single,
          admittedHelperPackages: admitted,
        ),
        isTrue,
      );
    });
  });

  test('admission uses resolved declarations and keeps own helpers', () async {
    await _resolve((resolver, library) async {
      final expression = await _build(resolver, library, 'Probe');
      final calls = _Calls();
      expression.accept(calls);
      final admitted = artifactHelperPackages(_catalog());
      for (final call in calls.calls) {
        final name = call.toSource();
        final isOwn = name == '_own()' || name == 'local()';
        expect(isArtifactHelperInvocation(call), isOwn, reason: name);
        expect(
          isArtifactHelperInvocation(
            call,
            admittedHelperPackages: admitted,
          ),
          isOwn || name == 'kit.badge()' || name == 'kit.Kit.badge()',
          reason: name,
        );
      }
    });
  });

  test('admitted dependency helpers explain unsupported return types',
      () async {
    await _resolve((resolver, library) async {
      final expression = await _build(resolver, library, 'ReturnTypeProbe');
      final result = ExpressionTranslator(
        catalog: _catalog(),
        helpers: HelperRegistry(),
      ).translate(expression);
      expect(result.issues.single.code, IssueCode.customWidgetInliningDeferred);
      expect(
        result.issues.single.message,
        "The helper 'Kit.dynamicValue' cannot be inlined: "
        'a helper must return a widget or a value of a class type.',
      );
    });
  });

  test('reachable helpers retain dependency elements and refusals', () async {
    await _resolve((resolver, library) async {
      final expression = await _build(resolver, library, 'Probe');
      final reachable = await reachableArtifactHelpers(
        [expression],
        astNodeFor: (fragment) => resolver.astNodeFor(fragment, resolve: true),
        admittedHelperPackages: artifactHelperPackages(_catalog()),
      );
      expect(reachable.recursive, isNull);
      final helpers = reachable.helpers.keys.toList();
      expect(
        helpers.map((helper) => helper.name),
        unorderedEquals(['_own', 'local', 'badge', 'badge', 'label']),
      );
      expect(
        helpers.where(
          (helper) => helper.library?.identifier == 'package:acme_kit/kit.dart',
        ),
        hasLength(3),
      );
      final refused = await _build(resolver, library, 'Refused');
      final refusedHelpers = await reachableArtifactHelpers(
        [refused],
        astNodeFor: (fragment) => resolver.astNodeFor(fragment, resolve: true),
        admittedHelperPackages: artifactHelperPackages(_catalog()),
      );
      expect(refusedHelpers.helpers, isEmpty);
      final result = ExpressionTranslator(
        catalog: _catalog(),
        helpers: HelperRegistry(),
      ).translate(refused);
      expect(result.issues.single.code, IssueCode.customWidgetInliningDeferred);
      expect(
        result.issues.single.message,
        contains('initialized final or const locals'),
      );
      expect(result.issues.single.location, isNotEmpty);
    });
  });

  test('source visitors pass the same optional helper admission', () async {
    await _resolve((resolver, library) async {
      final catalog = _catalog();
      final defaultScreen = await visitOnboardingSources(library, _sourceId);
      final screen = await visitOnboardingSources(
        library,
        _sourceId,
        catalog: catalog,
      );
      final paywall = await visitPaywallSources(
        library,
        _sourceId,
        catalog: catalog,
      );
      expect(defaultScreen.issues, isEmpty);
      expect(defaultScreen.sources.single.build.helpers, isEmpty);
      expect(screen.issues, isEmpty);
      expect(paywall.issues, isEmpty);
      for (final build in [
        screen.sources.single.build,
        paywall.sources.single.build,
      ]) {
        expect(build.helpers.keys.map((helper) => helper.name), ['labels']);
      }
    });
  });

  test('classifier derives dependency admission from its catalog', () async {
    await _resolve((resolver, library) async {
      final widget = library.getClass('Composed')!;
      final classifier = WidgetClassifier(
        catalog: _catalog(),
        astNodeFor: (fragment) => resolver.astNodeFor(fragment, resolve: true),
      );
      expect(await classifier.classify(widget), isA<ComposableWidget>());
      expect(
        classifier.blueprints[customWidgetKey(widget)]!.inlined.helpers.keys
            .map((helper) => helper.name),
        unorderedEquals(['badge', 'label']),
      );
      final defaultClassifier = WidgetClassifier(
        catalog: _catalog(publishWidgets: false),
        astNodeFor: (fragment) => resolver.astNodeFor(fragment, resolve: true),
      );
      expect(await defaultClassifier.classify(widget), isA<ImperativeWidget>());
    });
  });

  test('static walks and translation expand dependency helper lists', () async {
    await _resolve((resolver, library) async {
      final build = await _blueprint(resolver, library, 'Welcome');
      final constructors = <String>[];
      visitStaticallyAdmittedExpressions(
        build.rootExpression,
        inlined: build.inlined,
        admittedHelperPackages: artifactHelperPackages(_catalog()),
        visit: (expression, _) {
          if (expression is InstanceCreationExpression) {
            constructors.add(expression.constructorName.type.name.lexeme);
          }
        },
      );
      expect(constructors, ['Column', 'Text', 'Text']);
      final result = ExpressionTranslator(
        catalog: _catalog(),
        helpers: HelperRegistry(),
      ).translate(build.rootExpression, rootInlined: build.inlined);
      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        'Column(children: [Text(data: "One"), Text(data: "Two")])',
      );
    });
  });

  test('custom widget catalogs preserve dedicated SDK event lowering',
      () async {
    final expression = await parseExpressionFromSourceForTest(
      """
import 'package:restage/restage.dart';
abstract final class Events {
  static const next = SurfaceEvent<void>('next');
}
Object x() => surfaceEvent(Events.next);
""",
      rootPackage: 'apps_examples',
    );
    expect(
      isArtifactHelperInvocation(
        expression as MethodInvocation,
        admittedHelperPackages: artifactHelperPackages(_catalog()),
      ),
      isFalse,
    );
    final result = ExpressionTranslator(
      catalog: _catalog(),
      helpers: HelperRegistry()..registerAll(onboardingHelpers),
    ).translate(expression);
    expect(result.issues, isEmpty);
    expect(result.dsl, 'event "next" {}');
  });

  test('measurement derives admission and keeps helper occurrence identity',
      () async {
    await _resolve((resolver, library) async {
      final build = await _blueprint(resolver, library, 'Welcome');
      MeasurementSourceDiscoveryResult discover(Catalog catalog) =>
          MeasurementSourceDiscovery.discover(
            MeasurementSourceDiscoveryInput(
              authority: MeasurementSourceAuthority.screen,
              sourceClass: library.getClass('Welcome')!,
              rootExpression: build.rootExpression,
              catalog: catalog,
              rootHelpers: build.helpers,
            ),
          );
      final result = discover(_catalog());
      expect(
        result.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
        reason: result.rejectionReason,
      );
      expect(result.nodes, hasLength(3));
      expect(
        result.nodes.map((node) => node.structuralOccurrenceKey).toSet(),
        hasLength(3),
      );
      expect(result.events, isEmpty);
      expect(
        discover(_catalog(publishWidgets: false)).disposition,
        MeasurementSourceDiscoveryDisposition.rejected,
      );
    });
  });
}

Future<T> _resolve<T>(Future<T> Function(Resolver, LibraryElement) action) =>
    resolveSources(
      const {
        'flutter|lib/widgets.dart': '''
class Widget { const Widget(); }
class BuildContext {}
class StatelessWidget extends Widget { const StatelessWidget(); }
class Text extends Widget { const Text(this.data); final String data; }
class Column extends Widget {
  const Column({required this.children});
  final List<Widget> children;
}
''',
        'restage|lib/annotations.dart': '''
import 'package:flutter/widgets.dart';
class ScreenSource {
  const ScreenSource({required this.id});
  final String id;
}
class PaywallSource {
  const PaywallSource({required this.id});
  final String id;
}
Widget special() => const Text('Dedicated');
''',
        'acme_kit|lib/kit.dart': '''
import 'package:flutter/widgets.dart';
Widget badge() => Kit.label();
List<Widget> labels() => const [Text('One'), Text('Two')];
Widget refused() { var text = 'Mutable'; return Text(text); }
class Kit {
  static Widget badge() => const Text('Static');
  static Widget label() => const Text('Nested');
  static dynamic dynamicValue() => const Text('Dynamic');
  Widget instance() => const Text('Instance');
}
''',
        'restage_brand|lib/widgets.dart': '''
import 'package:flutter/widgets.dart';
Widget heading() => const Text('Brand');
''',
        'unrelated|lib/helpers.dart': '''
import 'package:flutter/widgets.dart';
Widget badge() => const Text('Unrelated');
''',
        'app|lib/surface.dart': '''
import 'package:flutter/widgets.dart';
import 'package:restage/annotations.dart';
import 'package:restage/annotations.dart' as sdk;
import 'package:acme_kit/kit.dart' as kit;
import 'package:acme_kit/kit.dart' show Kit;
import 'package:unrelated/helpers.dart' as other;
import 'package:restage_brand/widgets.dart' as brand;
Widget local() => const Text('Local');
class Probe extends StatelessWidget {
  Widget _own() => const Text('Own');
  Widget build(BuildContext context) => Column(children: [
    _own(), local(), kit.badge(), kit.Kit.badge(), other.badge(),
    sdk.special(), kit.Kit().instance(),
  ]);
}
class ReturnTypeProbe extends StatelessWidget {
  Widget build(BuildContext context) => Kit.dynamicValue();
}
class BrandProbe extends StatelessWidget {
  Widget build(BuildContext context) => brand.heading();
}
class Refused extends StatelessWidget {
  Widget build(BuildContext context) => kit.refused();
}
class Composed extends StatelessWidget {
  Widget build(BuildContext context) => kit.badge();
}
@ScreenSource(id: 'welcome')
class Welcome extends StatelessWidget {
  Widget build(BuildContext context) => Column(children: [...kit.labels()]);
}
@PaywallSource(id: 'offer')
class Offer extends StatelessWidget {
  Widget build(BuildContext context) => Column(children: [...kit.labels()]);
}
''',
      },
      (resolver) async =>
          await action(resolver, await resolver.libraryFor(_sourceId)),
      resolverFor: 'app|lib/surface.dart',
    );

Future<Expression> _build(
  Resolver resolver,
  LibraryElement library,
  String name,
) async {
  final method = library
      .getClass(name)!
      .methods
      .singleWhere((method) => method.name == 'build');
  final node = await resolver.astNodeFor(method.firstFragment, resolve: true);
  expect(node, isA<MethodDeclaration>());
  return extractInlinableBuildBody((node! as MethodDeclaration).body)!
      .expression;
}

Future<SourceBuildBlueprint> _blueprint(
  Resolver resolver,
  LibraryElement library,
  String name,
) async {
  final issues = <Issue>[];
  final build = await extractSourceBuildBlueprint(
    sourceClass: library.getClass(name)!,
    library: library,
    astNodeFor: (fragment) => resolver.astNodeFor(fragment, resolve: true),
    catalog: _catalog(),
    issues: issues,
    location: 'surface.dart#$name',
  );
  expect(issues, isEmpty);
  expect(build, isNotNull);
  return build!;
}

final class _Calls extends RecursiveAstVisitor<void> {
  final List<MethodInvocation> calls = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    calls.add(node);
    super.visitMethodInvocation(node);
  }
}
