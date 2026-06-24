import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Wording discipline for the cluster of diagnostics that fire when a
/// custom widget — or a construct inside one — does not transpile.
///
/// Two categories, distinguished by phrasing (no `[deferred]` /
/// `[structural]` prefix marker — IssueCode is the routing key for
/// tooling; the message is for humans, and the verbs carry the category
/// unambiguously):
///
///   - **Deferred** — *"…this transpiler increment does not yet …"*. A
///     future codegen unlock could move the construct into the inlinable
///     set; the customer can also rewrite to a recognised shape today.
///   - **Structural** — *"…the declarative paywall format cannot
///     express…"* / *"…cannot be transpiled…"*. The construct is
///     fundamentally outside RFW's declarative envelope; no future
///     codegen will bring it in.
///
/// These tests are the chapter-close regression rail — they make the
/// category boundary load-bearing so wording drift between increments
/// surfaces immediately. The behaviour-level tests for each diagnostic
/// live in `custom_widget_recognition_test.dart`,
/// `custom_widget_e2e_test.dart`, and `widget_classifier_test.dart`;
/// this file only guards the category-verb invariants. Public-bound:
/// every message asserted here
/// is wire-frozen the moment a customer's build surfaces it.
const String _key = 'package:restage_codegen/_expr_probe.dart#AcmeWidget';

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
            'customer reads it as a future-codegen-unlockable shape, not as '
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
            'the customer reads it as an RFW capability boundary, not as a '
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
      expect(issue.message, contains('not supported by this transpiler'));
      expect(issue.message, isNot(contains('cannot express')));
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
}
