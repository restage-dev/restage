import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/restage_source_roster.dart';
import 'package:restage_codegen/src/restage_source_roster_builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('Restage source roster ownership', () {
    test('accepts one implicit and multiple explicit declarations', () {
      final roster = assembleRestageSourceRoster([
        _declaration(
          libraryPath: 'lib/account_screens.dart',
          declarationName: 'AccountChooser',
          explicitId: null,
          outputPath: 'assets/restage/account_screens.rfw',
        ),
        _declaration(
          libraryPath: 'lib/account_screens.dart',
          declarationName: 'CompactProfile',
          explicitId: 'compact_profile',
          outputPath: 'assets/restage/compact_profile.rfw',
        ),
        _declaration(
          libraryPath: 'lib/account_screens.dart',
          declarationName: 'CompactConfirmation',
          explicitId: 'compact_confirmation',
          outputPath: 'assets/restage/compact_confirmation.rfw',
        ),
      ]);

      expect(roster.isValid, isTrue);
      expect(
        roster.declarations.map((source) => source.effectiveId),
        containsAll(<String>[
          'account_screens',
          'compact_profile',
          'compact_confirmation',
        ]),
      );
      expect(
        roster.declarations
            .singleWhere(
              (source) =>
                  source.declarationIdentity.endsWith('#AccountChooser'),
            )
            .hasImplicitId,
        isTrue,
      );
    });

    test('rejects a second implicit declaration in one library with spans', () {
      final roster = assembleRestageSourceRoster([
        _declaration(
          libraryPath: 'lib/account_screens.dart',
          declarationName: 'First',
          explicitId: null,
          outputPath: 'assets/restage/first.rfw',
          line: 4,
        ),
        _declaration(
          libraryPath: 'lib/account_screens.dart',
          declarationName: 'Second',
          explicitId: null,
          outputPath: 'assets/restage/second.rfw',
          line: 12,
        ),
      ]);

      expect(roster.isValid, isFalse);
      final message = roster.issues.map((issue) => issue.toString()).join('\n');
      expect(message, contains('lib/account_screens.dart@4:1'));
      expect(message, contains('lib/account_screens.dart@12:1'));
      expect(
        roster.issues,
        contains(
          predicate<Issue>(
            (issue) => issue.code == IssueCode.invalidScreenSourceCount,
          ),
        ),
      );
    });

    test('rejects duplicate explicit identities and names both source spans',
        () {
      final roster = assembleRestageSourceRoster([
        _declaration(
          libraryPath: 'lib/first.dart',
          declarationName: 'First',
          explicitId: 'same',
          outputPath: 'assets/restage/first.rfw',
          line: 3,
        ),
        _declaration(
          libraryPath: 'lib/second.dart',
          declarationName: 'Second',
          explicitId: 'same',
          outputPath: 'assets/restage/second.rfw',
          line: 8,
        ),
      ]);

      expect(roster.isValid, isFalse);
      final duplicate = roster.issues.singleWhere(
        (issue) => issue.code == IssueCode.duplicateId,
      );
      expect(duplicate.message, contains('duplicate explicit IDs'));
      expect(duplicate.message, contains('lib/first.dart@3:1'));
      expect(duplicate.message, contains('lib/second.dart@8:1'));
    });

    test('checks every declared identity namespace without a kind:id key', () {
      final roster = assembleRestageSourceRoster([
        _declaration(
          libraryPath: 'lib/first.dart',
          declarationName: 'First',
          explicitId: 'same',
          outputPath: 'assets/restage/first.rfw',
          identityClaims: const [
            RestageIdentityClaim(namespace: 'neutral/source', key: 'same'),
            RestageIdentityClaim(namespace: 'artifact-output', key: 'first'),
          ],
        ),
        _declaration(
          libraryPath: 'lib/second.dart',
          declarationName: 'Second',
          explicitId: 'other',
          outputPath: 'assets/restage/second.rfw',
          identityClaims: const [
            RestageIdentityClaim(namespace: 'neutral/source', key: 'other'),
            RestageIdentityClaim(namespace: 'artifact-output', key: 'first'),
          ],
          line: 8,
        ),
      ]);

      final duplicate = roster.issues.singleWhere(
        (issue) => issue.code == IssueCode.duplicateId,
      );
      expect(duplicate.message, contains('artifact-output:first'));
      expect(duplicate.message, contains('lib/first.dart@1:1'));
      expect(duplicate.message, contains('lib/second.dart@8:1'));
    });

    test('rejects output ownership collisions with both source spans', () {
      final roster = assembleRestageSourceRoster([
        _declaration(
          libraryPath: 'lib/first.dart',
          declarationName: 'First',
          explicitId: 'first',
          outputPath: 'assets/restage/shared.rfw',
          line: 3,
        ),
        _declaration(
          libraryPath: 'lib/second.dart',
          declarationName: 'Second',
          explicitId: 'second',
          outputPath: 'assets/restage/shared.rfw',
          line: 8,
        ),
      ]);

      expect(roster.isValid, isFalse);
      final collision = roster.issues.singleWhere(
        (issue) => issue.code == IssueCode.generatedSymbolCollision,
      );
      expect(collision.message, contains('assets/restage/shared.rfw'));
      expect(collision.message, contains('lib/first.dart@3:1'));
      expect(collision.message, contains('lib/second.dart@8:1'));
    });

    test('one library sharing its generated part is not a collision', () {
      // A screen and a flow in one library contribute different roles to the
      // one part they share. That is a single physical output with one owner
      // and one writing builder, so it must not read as two claimants.
      const part = 'lib/features/restage.generated/welcome.restage.g.dart';
      final roster = assembleRestageSourceRoster([
        _sharedPartDeclaration(
          declarationName: 'WelcomeScreen',
          explicitId: 'welcome',
          kind: RestageRosterSourceKind.screen,
          role: 'screen-descriptor',
          partPath: part,
        ),
        _sharedPartDeclaration(
          declarationName: 'welcomeFlow',
          explicitId: 'welcome-flow',
          kind: RestageRosterSourceKind.flow,
          role: 'flow-descriptor',
          partPath: part,
        ),
      ]);

      expect(roster.issues, isEmpty);
      expect(roster.isValid, isTrue);
    });

    test('a second builder claiming one path is still a collision', () {
      // The relaxation above must not blunt the guard: same path, same
      // library-owned key, but a different writing builder is exactly the
      // two-owner case the check exists to catch.
      const part = 'lib/features/restage.generated/welcome.restage.g.dart';
      final roster = assembleRestageSourceRoster([
        _sharedPartDeclaration(
          declarationName: 'WelcomeScreen',
          explicitId: 'welcome',
          kind: RestageRosterSourceKind.screen,
          role: 'screen-descriptor',
          partPath: part,
        ),
        _sharedPartDeclaration(
          declarationName: 'welcomeFlow',
          explicitId: 'welcome-flow',
          kind: RestageRosterSourceKind.flow,
          role: 'flow-descriptor',
          partPath: part,
          builder: 'restage_codegen:some_other_builder',
        ),
      ]);

      expect(roster.isValid, isFalse);
      final collision = roster.issues.singleWhere(
        (issue) => issue.code == IssueCode.generatedSymbolCollision,
      );
      expect(collision.message, contains(part));
    });

    test('keeps const declarations valid and freezes runtime output lists', () {
      const declaration = RestageSourceDeclaration(
        kind: RestageRosterSourceKind.screen,
        libraryIdentity: 'package:fixture/const.dart',
        libraryPath: 'lib/const.dart',
        declarationIdentity: 'package:fixture/const.dart#ConstScreen',
        sourcePath: 'lib/const.dart',
        explicitId: null,
        span: RestageSourceSpan(
          path: 'lib/const.dart',
          startLine: 1,
          startColumn: 1,
          endLine: 1,
          endColumn: 12,
        ),
        identityClaims: [
          RestageIdentityClaim(namespace: 'test/source', key: 'const'),
        ],
        outputs: [
          RestageOutputClaim(
            path: 'assets/restage/const.rfw',
            role: 'binary',
            builder: 'restage_codegen:test',
          ),
        ],
      );
      expect(declaration.outputs, hasLength(1));

      final mutableOutputs = <RestageOutputClaim>[];
      final frozen = RestageSourceDeclaration.frozen(
        kind: RestageRosterSourceKind.screen,
        libraryIdentity: 'package:fixture/frozen.dart',
        libraryPath: 'lib/frozen.dart',
        declarationIdentity: 'package:fixture/frozen.dart#FrozenScreen',
        sourcePath: 'lib/frozen.dart',
        explicitId: 'frozen',
        span: const RestageSourceSpan(
          path: 'lib/frozen.dart',
          startLine: 1,
          startColumn: 1,
          endLine: 1,
          endColumn: 13,
        ),
        identityClaims: const [
          RestageIdentityClaim(namespace: 'test/source', key: 'frozen'),
        ],
        outputs: mutableOutputs,
      );
      mutableOutputs.add(
        const RestageOutputClaim(
          path: 'assets/restage/mutated.rfw',
          role: 'binary',
          builder: 'restage_codegen:test',
        ),
      );
      expect(frozen.outputs, isEmpty);
      expect(
        () => frozen.outputs.add(
          const RestageOutputClaim(
            path: 'assets/restage/late.rfw',
            role: 'binary',
            builder: 'restage_codegen:test',
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('computes stale output families for remove, move, and reclassify', () {
      final previous = assembleRestageSourceRoster([
        _declaration(
          libraryPath: 'lib/onboarding/removed.dart',
          declarationName: 'Removed',
          explicitId: 'removed',
          outputPaths: const [
            'assets/onboarding/screens/removed.rfwtxt',
            'assets/onboarding/screens/removed.rfw',
            'assets/onboarding/screens/removed.capability.json',
          ],
        ),
        _declaration(
          libraryPath: 'lib/onboarding/old_name.dart',
          declarationName: 'Moved',
          explicitId: 'stable',
          identityNamespace: 'publication/onboarding',
          outputPaths: const [
            'assets/onboarding/screens/old_name.rfwtxt',
            'assets/onboarding/screens/old_name.rfw',
          ],
        ),
        _declaration(
          libraryPath: 'lib/onboarding/reclassified.dart',
          declarationName: 'OldKind',
          explicitId: 'reclassified',
          outputPaths: const ['assets/shared/reclassified.rfw'],
          builder: 'restage_codegen:screen',
        ),
        _declaration(
          libraryPath: 'lib/onboarding/kept.dart',
          declarationName: 'Kept',
          explicitId: 'kept',
          outputPaths: const ['assets/onboarding/screens/kept.rfw'],
        ),
      ]);
      final current = assembleRestageSourceRoster([
        _declaration(
          libraryPath: 'lib/onboarding/new_name.dart',
          declarationName: 'Moved',
          explicitId: 'stable',
          identityNamespace: 'publication/onboarding',
          outputPaths: const [
            'assets/onboarding/screens/new_name.rfwtxt',
            'assets/onboarding/screens/new_name.rfw',
          ],
        ),
        _declaration(
          libraryPath: 'lib/onboarding/reclassified.dart',
          declarationName: 'NewKind',
          explicitId: 'reclassified',
          outputPaths: const ['assets/shared/reclassified.rfw'],
          builder: 'restage_codegen:paywall',
          identityNamespace: 'publication/paywall',
        ),
        _declaration(
          libraryPath: 'lib/onboarding/kept.dart',
          declarationName: 'Kept',
          explicitId: 'kept',
          outputPaths: const ['assets/onboarding/screens/kept.rfw'],
        ),
      ]);

      final stale = computeRestageStaleOutputs(previous, current);
      expect(
        stale.map((claim) => claim.path),
        orderedEquals(<String>[
          'assets/onboarding/screens/old_name.rfw',
          'assets/onboarding/screens/old_name.rfwtxt',
          'assets/onboarding/screens/removed.capability.json',
          'assets/onboarding/screens/removed.rfw',
          'assets/onboarding/screens/removed.rfwtxt',
          'assets/shared/reclassified.rfw',
        ]),
      );
      expect(
        stale
            .where((claim) => claim.path.contains('old_name'))
            .map((claim) => claim.reason),
        everyElement(RestageStaleOutputReason.moved),
      );
      expect(
        stale
            .where((claim) => claim.path.contains('removed'))
            .map((claim) => claim.reason),
        everyElement(RestageStaleOutputReason.removed),
      );
      expect(
        stale
            .singleWhere((claim) => claim.path.contains('reclassified'))
            .reason,
        RestageStaleOutputReason.replaced,
      );

      final oldMoved = previous.declarations.singleWhere(
        (source) => source.explicitId == 'stable',
      );
      final newMoved = current.declarations.singleWhere(
        (source) => source.explicitId == 'stable',
      );
      expect(newMoved.effectiveId, oldMoved.effectiveId);
      expect(
        newMoved.identityClaims.single.qualifiedKey,
        oldMoved.identityClaims.single.qualifiedKey,
      );
      expect(
        current.outputs.map((output) => output.path),
        isNot(contains('assets/onboarding/screens/old_name.rfw')),
      );
    });
  });

  group('RestageSourceRosterBuilder', () {
    test('discovers the package and emits deterministic source/output files',
        () async {
      final sources = <String, String>{
        'lib/onboarding/screens/welcome.dart': _screenSource(
          id: 'welcome',
          className: 'WelcomeScreen',
        ),
        'lib/message/flows/receipt.dart': _flowSource('receipt'),
        'lib/paywalls/pro.dart': _paywallSource('pro'),
      };
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );

      final result = await _runBuilder(sources, readerWriter);
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));

      final sourceIndex = jsonDecode(
        readerWriter.testing.readString(
          AssetId('apps_examples', 'assets/restage/source-index.json'),
        ),
      ) as Map<String, Object?>;
      final indexedSources = sourceIndex['sources']! as List<Object?>;
      expect(indexedSources, hasLength(3));
      expect(
        indexedSources.map(
          (source) => (source! as Map<String, Object?>)['id'],
        ),
        containsAll(<Object?>['welcome', 'receipt', 'pro']),
      );

      final outputRoster = jsonDecode(
        readerWriter.testing.readString(
          AssetId('apps_examples', 'assets/restage/output-roster.json'),
        ),
      ) as Map<String, Object?>;
      final outputs = outputRoster['outputs']! as List<Object?>;
      final outputPaths = [
        for (final output in outputs)
          (output! as Map<String, Object?>)['path']! as String,
      ];
      expect(
        outputPaths,
        containsAll(<String>[
          'lib/onboarding/screens/restage.generated/welcome.restage.g.dart',
          'assets/onboarding/screens/welcome.rfw',
          'assets/message/flows/receipt.flow.json',
          'assets/paywalls/pro.rfw',
          'assets/paywalls/pro.flow.json',
        ]),
      );
      expect(
        outputPaths,
        orderedEquals([...outputPaths]..sort()),
      );
    });

    test(
      'admits canonical libraries beneath generated while excluding generated '
      'and story Dart files',
      () async {
        final readerWriter = await readerWriterWithFilesystemSources(
          rootPackage: 'apps_examples',
        );
        final retained = _canonicalExplicitScreenSource(
          id: 'retained',
          className: 'RetainedScreen',
          partStem: 'retained',
          surface: 'general',
        );
        final ignored = _canonicalExplicitScreenSource(
          id: 'ignored',
          className: 'IgnoredScreen',
          partStem: 'ignored',
          surface: 'general',
        );

        final result = await _runBuilder(
          {
            'lib/generated/retained.dart': retained,
            'lib/generated/ignored.g.dart': ignored,
            'lib/generated/ignored.stories.dart': ignored,
          },
          readerWriter,
        );

        expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
        final sourceIndex =
            jsonDecode(_rosterText(readerWriter)) as Map<String, Object?>;
        final sources = sourceIndex['sources']! as List<Object?>;
        expect(
          sources.map((source) => (source! as Map<String, Object?>)['id']),
          orderedEquals(['retained']),
        );
      },
    );

    test('writes an invalid fixed bundle before failing ownership admission',
        () async {
      final sources = <String, String>{
        'lib/onboarding/screens/first.dart': _screenSource(
          id: 'same',
          className: 'FirstScreen',
        ),
        'lib/onboarding/screens/second.dart': _screenSource(
          id: 'same',
          className: 'SecondScreen',
        ),
      };
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );

      final result = await _runBuilder(sources, readerWriter);

      expect(result.succeeded, isFalse);
      final sourceIndex =
          jsonDecode(_rosterText(readerWriter)) as Map<String, Object?>;
      expect(sourceIndex['valid'], isFalse);
      expect(sourceIndex['issues'], isNotEmpty);
      final outputRoster = jsonDecode(
        readerWriter.testing.readString(
          AssetId('apps_examples', 'assets/restage/output-roster.json'),
        ),
      ) as Map<String, Object?>;
      expect(outputRoster['valid'], isFalse);
      expect(outputRoster['issues'], isNotEmpty);
    });

    test('defers cross-surface publication collision to the later frontend',
        () async {
      final sources = <String, String>{
        'lib/onboarding/screens/duplicate.dart': _screenSource(
          id: 'duplicate',
          className: 'OnboardingDuplicate',
        ),
        'lib/message/screens/duplicate.dart': _screenSource(
          id: 'duplicate',
          className: 'MessageDuplicate',
        ),
      };
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );

      final result = await _runBuilder(sources, readerWriter);

      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final sourceIndex = jsonDecode(_rosterText(readerWriter));
      final indexedSources =
          (sourceIndex as Map<String, Object?>)['sources']! as List<Object?>;
      expect(indexedSources, hasLength(2));
      for (final source in indexedSources) {
        final sourceMap = source! as Map<String, Object?>;
        final claims = sourceMap['identityClaims']! as List<Object?>;
        expect(
          claims.single,
          isA<Map<String, Object?>>().having(
            (claim) => claim['namespace'],
            'namespace',
            startsWith('legacy-source/screen/'),
          ),
        );
      }
    });

    test('executes add, edit, remove, and rename source invalidation',
        () async {
      final initial = <String, String>{
        'lib/onboarding/screens/alpha.dart': _screenSource(
          id: 'alpha',
          className: 'AlphaScreen',
        ),
        'lib/message/screens/beta.dart': _screenSource(
          id: 'beta',
          className: 'BetaScreen',
        ),
      };
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );

      var result = await _runBuilder(initial, readerWriter);
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      expect(_rosterText(readerWriter), contains('alpha'));
      expect(_rosterText(readerWriter), contains('beta'));

      final added = {
        ...initial,
        'lib/survey/screens/gamma.dart': _screenSource(
          id: 'gamma',
          className: 'GammaScreen',
        ),
      };
      result = await _runBuilder(added, readerWriter);
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      expect(_rosterText(readerWriter), contains('gamma'));

      final edited = {
        ...added,
        'lib/onboarding/screens/alpha.dart': _screenSource(
          id: 'alpha',
          className: 'EditedAlphaScreen',
        ),
      };
      result = await _runBuilder(edited, readerWriter);
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      expect(_rosterText(readerWriter), contains('#EditedAlphaScreen'));
      expect(_rosterText(readerWriter), isNot(contains('#AlphaScreen"')));

      readerWriter.testing.delete(
        AssetId('apps_examples', 'lib/message/screens/beta.dart'),
      );
      final removed = Map<String, String>.from(edited)
        ..remove('lib/message/screens/beta.dart');
      result = await _runBuilder(removed, readerWriter);
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      expect(_rosterText(readerWriter), isNot(contains('beta')));
      expect(
        _rosterText(readerWriter),
        isNot(contains('assets/message/screens/beta.rfw')),
      );

      readerWriter.testing.delete(
        AssetId('apps_examples', 'lib/onboarding/screens/alpha.dart'),
      );
      final renamed = Map<String, String>.from(removed)
        ..remove('lib/onboarding/screens/alpha.dart')
        ..['lib/onboarding/screens/renamed.dart'] = _screenSource(
          id: 'renamed',
          className: 'EditedAlphaScreen',
        );
      result = await _runBuilder(renamed, readerWriter);
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      expect(_rosterText(readerWriter), contains('renamed'));
      expect(_rosterText(readerWriter), isNot(contains('alpha')));
      expect(
        _rosterText(readerWriter),
        isNot(contains('assets/onboarding/screens/alpha.rfw')),
      );
    });

    test('admits colocated canonical screens with one library-owned part',
        () async {
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final result = await _runBuilder(
        {
          'lib/feature.dart': _canonicalColocatedScreensSource(),
        },
        readerWriter,
      );

      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final sourceIndex =
          jsonDecode(_rosterText(readerWriter)) as Map<String, Object?>;
      final sources = sourceIndex['sources']! as List<Object?>;
      expect(sources, hasLength(2));
      expect(
        sources.map(
          (source) => (source! as Map<String, Object?>)['authoring'],
        ),
        everyElement('canonical'),
      );
      expect(
        sources.map((source) => (source! as Map<String, Object?>)['id']),
        containsAll(<Object?>['first', 'second']),
      );

      final outputRoster = jsonDecode(
        readerWriter.testing.readString(
          AssetId('apps_examples', 'assets/restage/output-roster.json'),
        ),
      ) as Map<String, Object?>;
      final outputPaths = [
        for (final output in outputRoster['outputs']! as List<Object?>)
          (output! as Map<String, Object?>)['path']! as String,
      ];
      expect(
        outputPaths.where(
          (path) => path == 'lib/restage.generated/feature.restage.g.dart',
        ),
        hasLength(1),
      );
      expect(
        outputPaths,
        containsAll(<String>[
          'assets/general/screens/first.rfw',
          'assets/general/screens/second.rfw',
          'lib/generated/restage.publication.json',
          'lib/generated/restage.outputs.json',
        ]),
      );
    });

    test('shares one library part across explicit screen and paywall sources',
        () async {
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final result = await _runBuilder(
        {'lib/offers.dart': _canonicalColocatedScreenAndPaywallSource()},
        readerWriter,
      );

      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final outputRoster = jsonDecode(
        readerWriter.testing.readString(
          AssetId('apps_examples', 'assets/restage/output-roster.json'),
        ),
      ) as Map<String, Object?>;
      final outputPaths = [
        for (final output in outputRoster['outputs']! as List<Object?>)
          (output! as Map<String, Object?>)['path']! as String,
      ];
      expect(
        outputPaths.where(
          (path) => path == 'lib/restage.generated/offers.restage.g.dart',
        ),
        hasLength(1),
      );
      expect(
        outputPaths,
        containsAll(<String>[
          'assets/general/screens/announcement.rfw',
          'assets/paywalls/premium.rfw',
          'assets/paywalls/screens/paywall_premium.rfw',
        ]),
      );
    });

    test('uses explicit canonical IDs as authoritative across file moves',
        () async {
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final result = await _runBuilder(
        {
          'lib/renamed_feature.dart': _canonicalExplicitScreenSource(),
        },
        readerWriter,
      );

      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final sourceIndex =
          jsonDecode(_rosterText(readerWriter)) as Map<String, Object?>;
      final source = (sourceIndex['sources']! as List<Object?>).single!
          as Map<String, Object?>;
      expect(source['id'], 'stable-feature');
      expect(source['idMode'], 'explicit');
      expect(source['surface'], 'message');
      expect(source['authoring'], 'canonical');
      expect(
        _rosterText(readerWriter),
        isNot(contains('filenameMismatch')),
      );
      final outputRoster = jsonDecode(
        readerWriter.testing.readString(
          AssetId('apps_examples', 'assets/restage/output-roster.json'),
        ),
      ) as Map<String, Object?>;
      final outputPaths = {
        for (final output in outputRoster['outputs']! as List<Object?>)
          (output! as Map<String, Object?>)['path']! as String,
      };
      expect(
        outputPaths,
        containsAll(<String>{
          'assets/message/screens/stable-feature.rfwtxt',
          'assets/message/screens/stable-feature.rfw',
          'assets/message/screens/stable-feature.capability.json',
        }),
      );
      expect(
        outputPaths.where((path) => path.startsWith('assets/message/screens/')),
        everyElement(isNot(contains('renamed_feature'))),
      );
    });

    test('admits canonical top-level flow definitions through the frontend',
        () async {
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final result = await _runBuilder(
        {
          'lib/feature.dart': _canonicalFlowSource(),
        },
        readerWriter,
      );

      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final sourceIndex =
          jsonDecode(_rosterText(readerWriter)) as Map<String, Object?>;
      final sources = sourceIndex['sources']! as List<Object?>;
      expect(
        sources.map((value) => (value! as Map<String, Object?>)['kind']),
        contains('flowGraph'),
        reason: _rosterText(readerWriter),
      );
      final source = sources.singleWhere(
        (value) => (value! as Map<String, Object?>)['kind'] == 'flowGraph',
      )! as Map<String, Object?>;
      expect(source['id'], 'feature');
      expect(source['idMode'], 'implicit');
      expect(source['surface'], 'general');
      expect(source['deliveryMode'], 'typed');
      final neutralScreen = sources.singleWhere(
        (value) => (value! as Map<String, Object?>)['kind'] == 'screen',
      )! as Map<String, Object?>;
      expect(neutralScreen.containsKey('surface'), isFalse);
      expect(
        neutralScreen['outputs'],
        hasLength(4),
      );
      expect(
        (neutralScreen['outputs']! as List<Object?>).map(
          (output) => (output! as Map<String, Object?>)['path'],
        ),
        containsAll(<String>[
          'assets/general/screens/feature-screen.rfwtxt',
          'assets/general/screens/feature-screen.rfw',
          'assets/general/screens/feature-screen.capability.json',
        ]),
      );
      expect(
        (neutralScreen['identityClaims']! as List<Object?>).map(
          (claim) => (claim! as Map<String, Object?>)['namespace'],
        ),
        isNot(contains('canonical-publication/neutral')),
      );
      expect(
        (jsonDecode(
          readerWriter.testing.readString(
            AssetId('apps_examples', 'assets/restage/output-roster.json'),
          ),
        ) as Map<String, Object?>)['outputs'],
        contains(
          predicate<Object?>((value) {
            final output = value! as Map<String, Object?>;
            return output['path'] == 'assets/general/flows/feature.flow.json';
          }),
        ),
      );
    });

    test('admits the canonical advanced @FlowGraph class target', () async {
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final result = await _runBuilder(
        {
          'lib/advanced.dart': _canonicalAdvancedFlowSource(),
        },
        readerWriter,
      );

      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final sourceIndex =
          jsonDecode(_rosterText(readerWriter)) as Map<String, Object?>;
      final source = (sourceIndex['sources']! as List<Object?>).single!
          as Map<String, Object?>;
      expect(source['kind'], 'flowGraph');
      expect(source['id'], 'advanced');
      expect(source['idMode'], 'implicit');
      expect(source['surface'], 'general');
      expect(source['authoring'], 'canonical');
    });

    test('admits @Paywall as a composable canonical paywall source', () async {
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final result = await _runBuilder(
        {
          'lib/offer.dart': _canonicalPaywallSource(),
        },
        readerWriter,
      );

      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final sourceIndex =
          jsonDecode(_rosterText(readerWriter)) as Map<String, Object?>;
      final source = (sourceIndex['sources']! as List<Object?>).single!
          as Map<String, Object?>;
      expect(source['kind'], 'paywall');
      expect(source['surface'], 'paywall');
      expect(source['id'], 'offer');
      expect(source['authoring'], 'canonical');
      expect(
        _rosterText(readerWriter),
        contains('assets/paywalls/offer.flow.json'),
      );
      expect(
        _rosterText(readerWriter),
        contains('assets/paywalls/screens/paywall_offer.rfw'),
      );
    });

    test('rejects duplicate canonical publication identities', () async {
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final result = await _runBuilder(
        {
          'lib/first.dart': _canonicalExplicitScreenSource(
            id: 'same',
            className: 'FirstScreen',
            partStem: 'first',
            surface: 'general',
          ),
          'lib/second.dart': _canonicalExplicitScreenSource(
            id: 'same',
            className: 'SecondScreen',
            partStem: 'second',
            surface: 'general',
          ),
        },
        readerWriter,
      );

      expect(result.succeeded, isFalse);
      expect(
        result.errors.join('\n'),
        contains('canonical-publication/general'),
      );
    });
  });
}

/// A declaration claiming one library's shared generated part.
RestageSourceDeclaration _sharedPartDeclaration({
  required String declarationName,
  required String explicitId,
  required RestageRosterSourceKind kind,
  required String role,
  required String partPath,
  String builder = 'restage_codegen:generated_dart',
}) {
  const libraryPath = 'lib/features/welcome.dart';
  const libraryIdentity = 'package:fixture/lib/features/welcome.dart';
  return RestageSourceDeclaration.frozen(
    kind: kind,
    libraryIdentity: libraryIdentity,
    libraryPath: libraryPath,
    declarationIdentity: '$libraryIdentity#$declarationName',
    sourcePath: libraryPath,
    explicitId: explicitId,
    span: const RestageSourceSpan(
      path: libraryPath,
      startLine: 1,
      startColumn: 1,
      endLine: 1,
      endColumn: 2,
    ),
    identityClaims: [
      RestageIdentityClaim(
        namespace: 'test/${kind.wireName}',
        key: explicitId,
      ),
    ],
    outputs: [
      RestageOutputClaim(
        path: partPath,
        role: role,
        builder: builder,
        ownershipKey: 'canonical-library:$libraryIdentity',
      ),
    ],
  );
}

RestageSourceDeclaration _declaration({
  required String libraryPath,
  required String declarationName,
  required String? explicitId,
  String? outputPath,
  List<String>? outputPaths,
  RestageRosterSourceKind kind = RestageRosterSourceKind.screen,
  String identityNamespace = 'test/source',
  List<RestageIdentityClaim>? identityClaims,
  String builder = 'restage_codegen:test',
  int line = 1,
}) {
  final library = libraryPath.substring(
    0,
    libraryPath.length - '.dart'.length,
  );
  final paths = outputPaths ?? [outputPath!];
  return RestageSourceDeclaration.frozen(
    kind: kind,
    libraryIdentity: 'package:fixture/$library',
    libraryPath: libraryPath,
    declarationIdentity: 'package:fixture/$library#$declarationName',
    sourcePath: libraryPath,
    explicitId: explicitId,
    span: RestageSourceSpan(
      path: libraryPath,
      startLine: line,
      startColumn: 1,
      endLine: line,
      endColumn: declarationName.length + 1,
    ),
    identityClaims: identityClaims ??
        [
          RestageIdentityClaim(
            namespace: identityNamespace,
            key: explicitId ?? library.split('/').last,
          ),
        ],
    outputs: [
      for (final path in paths)
        RestageOutputClaim(
          path: path,
          role: path.endsWith('.rfw') ? 'binary' : 'sidecar',
          builder: builder,
        ),
    ],
  );
}

Future<TestBuilderResult> _runBuilder(
  Map<String, String> sources,
  TestReaderWriter readerWriter,
) {
  return testBuilder(
    const RestageSourceRosterBuilder(BuilderOptions.empty),
    {
      for (final entry in sources.entries)
        'apps_examples|${entry.key}': entry.value,
    },
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
}

String _rosterText(TestReaderWriter readerWriter) => readerWriter.testing
    .readString(AssetId('apps_examples', 'assets/restage/source-index.json'));

String _screenSource({required String id, required String className}) => '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/$id.restage.g.dart';

@ScreenSource(id: '$id')
class $className extends StatelessWidget {
  const $className({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

String _flowSource(String id) => '''
import 'package:restage/restage.dart';

part 'restage.generated/$id.restage.g.dart';

@FlowSource(id: '$id')
class ${id}Flow {}
''';

String _paywallSource(String id) => '''
import 'package:restage/restage.dart';

@PaywallSource(id: '$id')
class ${id}Paywall {}
''';

String _canonicalColocatedScreensSource() => '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/feature.restage.g.dart';

@Screen(id: 'first', surface: Surface.general)
final class FirstScreen extends StatelessWidget {
  const FirstScreen({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Screen(id: 'second', surface: Surface.general)
final class SecondScreen extends StatelessWidget {
  const SecondScreen({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

String _canonicalExplicitScreenSource({
  String id = 'stable-feature',
  String className = 'RenamedFeatureScreen',
  String partStem = 'renamed_feature',
  String surface = 'message',
}) =>
    '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/$partStem.restage.g.dart';

@Screen(id: '$id', surface: Surface.$surface)
final class $className extends StatelessWidget {
  const $className({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

String _canonicalColocatedScreenAndPaywallSource() => '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/offers.restage.g.dart';

@Screen(id: 'announcement', surface: Surface.general)
final class AnnouncementScreen extends StatelessWidget {
  const AnnouncementScreen({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Paywall(id: 'premium')
final class PremiumPaywall extends StatelessWidget {
  const PremiumPaywall({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

String _canonicalFlowSource() => '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/feature.restage.g.dart';

@Screen(id: 'feature-screen')
final class FeatureScreen extends StatelessWidget {
  const FeatureScreen({super.key});

  static const next = SurfaceEvent<void>('next');

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@FlowGraph(surface: Surface.general)
const featureFlow = FlowDefinition(
  start: FeatureScreen,
  transitions: [
    Transition.complete(FeatureScreen.next),
  ],
);
''';

String _canonicalPaywallSource() => '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/offer.restage.g.dart';

@Paywall()
final class OfferPaywall extends StatelessWidget {
  const OfferPaywall({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

String _canonicalAdvancedFlowSource() => '''
import 'package:restage/restage.dart';

part 'restage.generated/advanced.restage.g.dart';

@FlowGraph(surface: Surface.general)
final class AdvancedFlow extends RestageFlow {
  const AdvancedFlow();

  @override
  FlowDef buildFlow() => flow(
        initial: const OnboardingScreenRef(
          id: 'advanced',
          artifactPath: 'advanced.rfw',
          version: 1,
          minClient: 1,
        ),
        states: const [],
      );
}
''';
