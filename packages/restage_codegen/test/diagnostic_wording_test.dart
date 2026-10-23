import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Checks diagnostic wording for unsupported custom-widget constructs.
/// Deferred diagnostics say “does not yet”; structural limits say
/// “a delivered surface cannot express”. IssueCode identifies the category.
/// Behavior tests cover recognition, compilation and classification separately.
const String _key = 'package:restage_codegen/_expr_probe.dart#AcmeWidget';

const String _contextLookupMessage =
    "'Palette.of(context)' reads from the running app. Pass the value in as a "
    'constructor input, or use Theme.of(context).';

const String _staticFinalMessage =
    "'Styles.title' is static final, so its value exists only in the running "
    'app. Make it const, or pass it in as a constructor input.';

const String _acmeWidgetSource = '''
  class AcmeWidget { const AcmeWidget(); }
  Object x() => const AcmeWidget();
''';

ExpressionTranslator _translatorWith(WidgetClassification classification) =>
    ExpressionTranslator(
      catalog: kEmptyCatalog,
      helpers: HelperRegistry(),
      customWidgetClassifications: {_key: classification},
    );

void main() {
  group('Diagnostic wording — Deferred category', () {
    test(
        'customWidgetInliningDeferred surfaces the deferred verb '
        '("does not yet")', () async {
      final translator = _translatorWith(
        ComposableWidget(
          _key,
          requiredMechanisms: const {InliningMechanism.declarativeState},
          composedCustomWidgets: const [],
        ),
      );
      final expr = await parseExpressionFromSourceForTest(_acmeWidgetSource);
      final result = translator.translate(expr);

      expect(result.issues.single.code, IssueCode.customWidgetInliningDeferred);
      expect(
        result.issues.single.capabilityGapSubject,
        'customWidget:AcmeWidget',
      );
      expect(
        result.issues.single.message,
        contains('does not yet'),
        reason: 'Deferred messages must use the "does not yet" verb so the '
            'custom reads it as a future-codegen-unlockable shape, not as '
            'a structural RFW boundary.',
      );
      expect(
        result.issues.single.message,
        isNot(contains('cannot express')),
        reason: 'Structural-category verbs must not leak into the '
            'deferred-category message.',
      );
    });

    test(
        'customWidgetUnclassified umbrella message uses the deferred '
        'verb ("does not yet")', () async {
      final translator = _translatorWith(
        const UnclassifiableWidget(
          _key,
          reason: 'build() body is not a single returned expression',
        ),
      );
      final expr = await parseExpressionFromSourceForTest(_acmeWidgetSource);
      final result = translator.translate(expr);

      expect(result.issues.single.code, IssueCode.customWidgetUnclassified);
      expect(
        result.issues.single.message,
        contains('does not yet'),
        reason: 'The unclassified-widget umbrella message is deferred-shaped '
            'per the IssueCode doc ("may well be transpilable; the transpiler '
            'simply cannot tell") — the verb must signal that.',
      );
      expect(
        result.issues.single.message,
        isNot(contains('cannot express')),
        reason: 'Structural-category verbs must not leak into the '
            'unclassified-widget umbrella message.',
      );
    });
  });

  group('Diagnostic wording — Structural category', () {
    test(
        'customWidgetImperative surfaces the structural verb '
        '("cannot express")', () async {
      final translator = _translatorWith(
        ImperativeWidget(
          _key,
          blockers: const [
            Blocker(
              kind: BlockerKind.customPainter,
              location: '$_key@9:7',
              detail: 'CustomPaint(painter: ChartPainter())',
            ),
          ],
        ),
      );
      final expr = await parseExpressionFromSourceForTest(_acmeWidgetSource);
      final result = translator.translate(expr);

      expect(result.issues.single.code, IssueCode.customWidgetImperative);
      expect(
        result.issues.single.message,
        contains('cannot express'),
        reason: 'Structural messages must use the "cannot express" verb so '
            'the custom reads it as an RFW capability boundary, not as a '
            'future-codegen-unlockable shape.',
      );
      expect(
        result.issues.single.message,
        isNot(contains('does not yet')),
        reason: 'Deferred-category verbs must not leak into the '
            'structural-category message.',
      );
    });
  });

  group('Reclassification — reducible-blocker disposition', () {
    Future<Issue> issueFor(WidgetClassification c) async {
      final result = _translatorWith(c)
          .translate(await parseExpressionFromSourceForTest(_acmeWidgetSource));
      return result.issues.single;
    }

    test('a dartCall blocker reads "not supported yet", not "cannot express"',
        () async {
      // A dart call is reducible-in-principle (could become a recipe / helper /
      // auto-substitution), so it must NOT be sold as a capability boundary.
      final issue = await issueFor(
        ImperativeWidget(
          _key,
          blockers: const [
            Blocker(
              kind: BlockerKind.dartCall,
              location: '$_key@9:7',
              detail: 'formatPrice(amount)',
            ),
          ],
        ),
      );
      expect(issue.code, IssueCode.customWidgetUnsupportedReducible);
      expect(issue.message, contains('not supported in delivered surfaces'));
      expect(issue.message, isNot(contains('cannot express')));
      expect(issue.message, isNot(contains('later')));
    });

    test('a widget with no catalog entry says how to add one', () async {
      final issue = await issueFor(
        ImperativeWidget(
          _key,
          blockers: const [
            Blocker(
              kind: BlockerKind.unrecognisedComposedWidget,
              location: '$_key@9:7',
              detail: 'VIcon(name)',
            ),
          ],
        ),
      );
      expect(
        issue.message,
        allOf(
          startsWith("The custom widget 'AcmeWidget' has no catalog entry"),
          contains('VIcon(name)'),
          contains("renders from your app's compiled code"),
          contains('@RestageLibrary'),
        ),
      );
    });

    test('an unrecognisedComposedWidget blocker is reducible', () async {
      final issue = await issueFor(
        ImperativeWidget(
          _key,
          blockers: const [
            Blocker(
              kind: BlockerKind.unrecognisedComposedWidget,
              location: '$_key@9:7',
              detail: 'FancyChart()',
            ),
          ],
        ),
      );
      expect(issue.code, IssueCode.customWidgetUnsupportedReducible);
    });

    test('composesImperativeWidget INHERITS a reducible child', () async {
      // A parent composing a merely-reducible child is itself reducible-not-yet
      // — the override carries the child's disposition up.
      final issue = await issueFor(
        ImperativeWidget(
          _key,
          blockers: const [
            Blocker(
              kind: BlockerKind.composesImperativeWidget,
              location: '$_key@9:7',
              detail: 'InnerWidget()',
              dispositionOverride: CustomWidgetDisposition.reducible,
            ),
          ],
        ),
      );
      expect(issue.code, IssueCode.customWidgetUnsupportedReducible);
    });

    test('composesImperativeWidget with a dead-end child stays a dead end',
        () async {
      final issue = await issueFor(
        ImperativeWidget(
          _key,
          blockers: const [
            Blocker(
              kind: BlockerKind.composesImperativeWidget,
              location: '$_key@9:7',
              detail: 'InnerPainter()',
              dispositionOverride: CustomWidgetDisposition.deadEnd,
            ),
          ],
        ),
      );
      expect(issue.code, IssueCode.customWidgetImperative);
    });

    test('a mixed widget (any dead-end blocker) is a dead end', () async {
      // A single genuine boundary makes the whole widget a dead end, even
      // alongside a reducible blocker — the message names the dead-end one.
      final issue = await issueFor(
        ImperativeWidget(
          _key,
          blockers: const [
            Blocker(
              kind: BlockerKind.dartCall,
              location: '$_key@9:7',
              detail: 'formatPrice(amount)',
            ),
            Blocker(
              kind: BlockerKind.customPainter,
              location: '$_key@10:7',
              detail: 'CustomPaint(painter: ChartPainter())',
            ),
          ],
        ),
      );
      expect(issue.code, IssueCode.customWidgetImperative);
      expect(issue.message, contains('CustomPaint'));
    });

    test('customWidgetDispositionFor groups the four codes into three', () {
      expect(
        customWidgetDispositionFor(IssueCode.customWidgetInliningDeferred),
        CustomWidgetDisposition.reducible,
      );
      expect(
        customWidgetDispositionFor(IssueCode.customWidgetUnsupportedReducible),
        CustomWidgetDisposition.reducible,
      );
      expect(
        customWidgetDispositionFor(IssueCode.customWidgetImperative),
        CustomWidgetDisposition.deadEnd,
      );
      expect(
        customWidgetDispositionFor(IssueCode.customWidgetUnclassified),
        CustomWidgetDisposition.indeterminate,
      );
      expect(customWidgetDispositionFor(IssueCode.unknownWidget), isNull);
    });
  });

  group('Diagnostic wording — values and widgets from the running app', () {
    test('a widget its package left out of the catalog says why', () async {
      const reason = "property 'icon' targets 'Glyph' whose closure is not "
          'fully renderable (Glyph: dash: Unsupported structured field)';
      final translator = ExpressionTranslator(
        catalog: const Catalog(
          schemaVersion: kSupportedSchemaVersion,
          generatedAt: '1970-01-01T00:00:00Z',
          libraries: {},
          widgets: [],
          exclusions: [
            PropertyExclusion(
              widget: 'AcmeWidget',
              property: 'icon',
              target: 'rfw',
              reason: reason,
              location: '$_key.icon',
            ),
          ],
        ),
        helpers: HelperRegistry(),
        customWidgetClassifications: {
          _key: const UnclassifiableWidget(_key, reason: 'opaque'),
        },
      );
      final result = translator.translate(
        await parseExpressionFromSourceForTest(_acmeWidgetSource),
      );
      expect(
        result.issues.single.message,
        "'AcmeWidget' is left out of the catalog: $reason.",
      );
    });

    test(
        'an exclusion of a same-named widget in another library is not '
        'cited', () async {
      final translator = ExpressionTranslator(
        catalog: const Catalog(
          schemaVersion: kSupportedSchemaVersion,
          generatedAt: '1970-01-01T00:00:00Z',
          libraries: {},
          widgets: [],
          exclusions: [
            PropertyExclusion(
              widget: 'AcmeWidget',
              property: '',
              target: 'rfw',
              reason: 'another package',
              location: 'package:other/widgets.dart#AcmeWidget',
            ),
          ],
        ),
        helpers: HelperRegistry(),
        customWidgetClassifications: {
          _key: const UnclassifiableWidget(_key, reason: 'opaque'),
        },
      );
      final result = translator.translate(
        await parseExpressionFromSourceForTest(_acmeWidgetSource),
      );
      expect(
        result.issues.single.message,
        isNot(contains('left out of the catalog')),
      );
    });

    test("another package's builder widget points at host data", () async {
      final result = ExpressionTranslator(
        catalog: kEmptyCatalog,
        helpers: HelperRegistry(),
      ).translate(
        await parseExpressionFromSourceForTest(
          '''
          import 'package:flutter/widgets.dart';
          import 'package:acme_state/acme_state.dart';
          Object x() => SignalBuilder(builder: (context, value) => const SizedBox());
          ''',
          rootPackage: 'apps_examples',
          otherFiles: {
            'acme_state|lib/acme_state.dart': '''
              import 'package:flutter/widgets.dart';
              class SignalBuilder extends StatelessWidget {
                const SignalBuilder({super.key, required this.builder});
                final Widget Function(BuildContext context, int value) builder;
                @override
                Widget build(BuildContext context) => builder(context, 0);
              }
            ''',
          },
        ),
      );
      expect(
        result.issues.single.message,
        startsWith(
          "'SignalBuilder' (package:acme_state) builds from app state. Read "
          'that state in the host widget and pass the values to this surface '
          'as constructor inputs.',
        ),
      );
    });

    test(
        'a builder widget that hands over only a callback is not app '
        'state', () async {
      final result = ExpressionTranslator(
        catalog: kEmptyCatalog,
        helpers: HelperRegistry(),
      ).translate(
        await parseExpressionFromSourceForTest(
          '''
          import 'package:flutter/widgets.dart';
          import 'package:acme_motion/acme_motion.dart';
          Object x() => OpenContainer(
            closedBuilder: (context, open) => const SizedBox(),
            openBuilder: (context, close) => const SizedBox(),
          );
          ''',
          rootPackage: 'apps_examples',
          otherFiles: {
            'acme_motion|lib/acme_motion.dart': '''
              import 'package:flutter/widgets.dart';
              class OpenContainer extends StatelessWidget {
                const OpenContainer({
                  super.key,
                  required this.closedBuilder,
                  required this.openBuilder,
                });
                final Widget Function(BuildContext, VoidCallback) closedBuilder;
                final Widget Function(BuildContext, VoidCallback) openBuilder;
                @override
                Widget build(BuildContext context) =>
                    closedBuilder(context, () {});
              }
            ''',
          },
        ),
      );
      expect(
        result.issues.single.message,
        isNot(contains('builds from app state')),
      );
    });

    const tokens = '''
      import 'package:flutter/widgets.dart';
      class Palette extends InheritedWidget {
        const Palette({super.key, required super.child, required this.ink});
        final Color ink;
        static Palette of(BuildContext context) =>
            context.dependOnInheritedWidgetOfExactType<Palette>()!;
        @override
        bool updateShouldNotify(Palette old) => ink != old.ink;
      }
      abstract final class Styles {
        static final TextStyle title = _sized(28);
        static TextStyle _sized(double size) => TextStyle(fontSize: size);
      }
    ''';

    Future<List<String>> messagesFor(String body) async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/widgets.dart';
        import 'package:apps_examples/tokens.dart';
        class Probe extends StatelessWidget {
          const Probe({super.key});
          @override
          Widget build(BuildContext context) => const SizedBox();
          Object x(BuildContext context) => $body;
        }
        ''',
        rootPackage: 'apps_examples',
        enclosingClassName: 'Probe',
        otherFiles: {'lib/tokens.dart': tokens},
      );
      final result = ExpressionTranslator(
        catalog: kEmptyCatalog,
        helpers: HelperRegistry(),
      ).translate(expr);
      return [for (final issue in result.issues) issue.message];
    }

    test('an inherited lookup reads from the running app', () async {
      expect(
        await messagesFor('Palette.of(context).ink'),
        [_contextLookupMessage],
      );
    });

    test('a static final value exists only in the running app', () async {
      expect(
        await messagesFor('Styles.title'),
        [_staticFinalMessage],
      );
    });
  });
}
