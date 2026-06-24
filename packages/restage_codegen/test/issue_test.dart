import 'dart:convert';

import 'package:restage_codegen/src/issue.dart';
import 'package:test/test.dart';

void main() {
  group('IssueCode.isInformational', () {
    // The informational codes record a recognised-but-deferred design
    // decision on the audit trail; they must not fail a build. Everything
    // else is a real codegen error the author must resolve.
    const informational = <IssueCode>{
      IssueCode.denylistedPropertyType,
      IssueCode.denylistedWidget,
      IssueCode.denylistedProperty,
      IssueCode.rfwIncompatibleAnnotated,
      IssueCode.abstractTypeAwaitingUnion,
      IssueCode.structuredCycle,
      IssueCode.structuredDepthExceeded,
      IssueCode.unrepresentableCtorDefault,
      IssueCode.stablePropertyDeferred,
      IssueCode.customWidgetInliningDeferred,
      IssueCode.customWidgetUnsupportedReducible,
      // The announced-rewrite build notice — a non-failing annotation.
      IssueCode.idiomAutoSubstituted,
      IssueCode.navigationStandaloneArtifactSkipped,
    };

    test('classifies exactly the informational set as informational', () {
      final actual = IssueCode.values.where((c) => c.isInformational).toSet();
      expect(actual, equals(informational));
    });

    test('every informational code returns true', () {
      for (final code in informational) {
        expect(
          code.isInformational,
          isTrue,
          reason: '${code.name} should be informational',
        );
      }
    });

    test('a sample of fatal codes returns false', () {
      const fatal = <IssueCode>[
        IssueCode.propertyValueTypeMismatch,
        IssueCode.conflictingDefaultStrategy,
        IssueCode.customWidgetImperative,
        IssueCode.customWidgetUnclassified,
        IssueCode.unknownWidget,
        IssueCode.malformedRawDsl,
        IssueCode.stateShapeUnsupported,
        IssueCode.navigationFormUnsupported,
      ];
      for (final code in fatal) {
        expect(
          code.isInformational,
          isFalse,
          reason: '${code.name} should be fatal',
        );
      }
    });

    test('the informational set is a strict subset of all codes', () {
      expect(informational.length, lessThan(IssueCode.values.length));
      expect(
        IssueCode.values.where((c) => c.isInformational).length,
        equals(informational.length),
      );
    });
  });

  group('IssueCode.isBuildNotice', () {
    // A build notice is emitted ALONGSIDE a complete, correct translation —
    // the paywall builder logs it but does not fail. This is distinct from
    // isInformational (the catalog-build disposition): an informational code
    // such as customWidgetInliningDeferred marks an UNRENDERED widget, which is
    // fatal in a paywall, so it must NOT be a build notice.
    test('only successful-artifact annotations are build notices', () {
      final notices = IssueCode.values.where((c) => c.isBuildNotice).toSet();
      expect(
        notices,
        equals(<IssueCode>{
          IssueCode.idiomAutoSubstituted,
          IssueCode.navigationStandaloneArtifactSkipped,
        }),
      );
    });

    test('an unrendered-widget deferral is NOT a build notice', () {
      // The silent-drop guard: a deferred custom widget did not emit, so it
      // must keep blocking the paywall build even though it is informational.
      expect(IssueCode.customWidgetInliningDeferred.isInformational, isTrue);
      expect(IssueCode.customWidgetInliningDeferred.isBuildNotice, isFalse);
    });

    test('fatal codes are not build notices', () {
      for (final code in [
        IssueCode.unknownWidget,
        IssueCode.propertyValueTypeMismatch,
        IssueCode.unrecognizedMethodCall,
        IssueCode.stateShapeUnsupported,
      ]) {
        expect(code.isBuildNotice, isFalse, reason: code.name);
      }
    });
  });

  group('Issue capability-gap support links', () {
    const repoUrl = 'https://github.com/restage/restage';

    Issue issueWith({
      required IssueCode code,
      String? capabilityGapSubject,
      String message = 'Unsupported method invocation: '
          r'NumberFormat.currency(symbol: "$").format(price).',
    }) {
      return Issue(
        code: code,
        capabilityGapSubject: capabilityGapSubject,
        message: message,
        location: 'lib/paywalls/secret_paywall.dart#SecretPaywall@12:7',
      );
    }

    Uri supportUriFrom(String rendered) {
      const marker = '\nRequest support for this Restage gap: ';
      expect(rendered, contains(marker));
      return Uri.parse(rendered.split(marker).last.trim());
    }

    test('ships dark when no public issue repository URL is configured', () {
      final issue = issueWith(code: IssueCode.unrecognizedMethodCall);

      expect(issue.toLogString(), issue.toString());
      expect(issue.toLogString(), isNot(contains('/issues/new')));
    });

    test('appends a pre-filled GitHub issue URL for capability gaps', () {
      final issue = issueWith(
        code: IssueCode.unrecognizedMethodCall,
        capabilityGapSubject: 'NumberFormat.currency.format',
      );
      final rendered = issue.toLogString(issueRepositoryUrl: repoUrl);
      final uri = supportUriFrom(rendered);
      final body = uri.queryParameters['body']!;
      final jsonBlock = RegExp(
        r'```json\n([\s\S]*?)\n```',
      ).firstMatch(body)!.group(1)!;
      final payload = jsonDecode(jsonBlock) as Map<String, Object?>;

      expect(rendered, startsWith(issue.toString()));
      expect(uri.scheme, 'https');
      expect(uri.host, 'github.com');
      expect(uri.path, '/restage/restage/issues/new');
      expect(
        uri.queryParameters['title'],
        '[restage_codegen] Capability gap: unrecognizedMethodCall',
      );
      expect(
        uri.queryParameters['labels'],
        'codegen-gap,codegen-gap-unrecognizedMethodCall,'
        'codegen-gap-subject-numberformat-currency-format',
      );
      expect(
        payload,
        equals(<String, Object?>{
          'schema': 'restage.codegen.capability_gap.v1',
          'code': 'unrecognizedMethodCall',
          'subject': 'NumberFormat.currency.format',
          'sdkVersion': '0.1.0',
        }),
      );
      expect(
        body,
        allOf(
          contains('Issue code: `unrecognizedMethodCall`'),
          contains('Gap subject: `NumberFormat.currency.format`'),
          contains('SDK version: `0.1.0`'),
          contains(r'NumberFormat.currency(symbol: "$").format(price)'),
          isNot(contains('secret_paywall.dart')),
        ),
      );
    });

    test('does not append issue URLs for author-fixable user errors', () {
      final issue = issueWith(
        code: IssueCode.propertyValueTypeMismatch,
        message: 'Property value has the wrong type.',
      );

      expect(
        issue.toLogString(issueRepositoryUrl: repoUrl),
        issue.toString(),
      );
    });

    test('omits subject label and JSON field when no subject is available', () {
      final issue = issueWith(code: IssueCode.unrecognizedMethodCall);
      final uri = supportUriFrom(
        issue.toLogString(issueRepositoryUrl: repoUrl),
      );
      final body = uri.queryParameters['body']!;

      expect(
        uri.queryParameters['labels'],
        'codegen-gap,codegen-gap-unrecognizedMethodCall',
      );
      expect(body, contains('"code": "unrecognizedMethodCall"'));
      expect(body, isNot(contains('"subject"')));
      expect(body, isNot(contains('Gap subject:')));
    });
  });
}
