import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/commands/surface_identity.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../_helpers/publication_fixtures.dart';
import '../_helpers/test_fixtures.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('surface_identity_');
    await seedRestageConfig(
      tempDir,
      'demo',
      'mobile',
      defaultEnvironment: 'staging',
    );
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test(
    'uses the current manifest for a non-versioned paywall family',
    () async {
      await seedGeneratedPaywall(tempDir, slug: 'pro');

      final identity = await resolveSurfaceLifecycleIdentity(
        argResults: _args(tempDir, rest: ['pro']),
        fixedSurfaceType: null,
        slug: 'pro',
        stderr: StringBuffer(),
      );

      expect(identity, isNotNull);
      expect(identity!.surface, Surface.paywall);
      expect(identity.sourceKind, SurfaceSourceKind.paywall);
      expect(identity.contractVersion, isNull);
      expect(identity.fromManifest, isTrue);
    },
  );

  test('does not let an explicit type override a current manifest', () async {
    await seedGeneratedPaywall(tempDir, slug: 'pro');
    final error = StringBuffer();

    final identity = await resolveSurfaceLifecycleIdentity(
      argResults: _args(tempDir, flags: {'type': 'onboarding'}, rest: ['pro']),
      fixedSurfaceType: null,
      slug: 'pro',
      stderr: error,
    );

    expect(identity, isNull);
    expect(error.toString(), contains('does not match'));
  });

  test(
    'rejects the invalid-build marker instead of using an older manifest',
    () async {
      await seedGeneratedPaywall(tempDir, slug: 'pro');
      final marker = File(p.join(tempDir.path, kSurfacePublicationInvalidPath));
      await marker.create(recursive: true);
      final error = StringBuffer();

      final identity = await resolveSurfaceLifecycleIdentity(
        argResults: _args(tempDir, rest: ['pro']),
        fixedSurfaceType: Surface.paywall,
        slug: 'pro',
        stderr: error,
      );

      expect(identity, isNull);
      expect(
        error.toString(),
        contains('Generated publication output is invalid'),
      );
    },
  );

  test(
    'explicit fallback uses a positive version for a standalone screen',
    () async {
      final identity = await resolveSurfaceLifecycleIdentity(
        argResults: _args(
          tempDir,
          flags: {'type': 'general', 'contract-version': '7'},
          rest: ['notice'],
        ),
        fixedSurfaceType: null,
        slug: 'notice',
        stderr: StringBuffer(),
      );

      expect(identity, isNotNull);
      expect(identity!.sourceKind, SurfaceSourceKind.screen);
      expect(identity.payloadKind, SurfacePayloadKind.blob);
      expect(identity.contractVersion, 7);
      expect(identity.fromManifest, isFalse);
    },
  );

  test(
    'a paywall category with a positive version selects an ordinary screen',
    () async {
      final identity = await resolveSurfaceLifecycleIdentity(
        argResults: _args(
          tempDir,
          flags: {'type': 'paywall', 'contract-version': '7'},
          rest: ['notice'],
        ),
        fixedSurfaceType: null,
        slug: 'notice',
        stderr: StringBuffer(),
      );

      expect(identity, isNotNull);
      expect(identity!.surface, Surface.paywall);
      expect(identity.sourceKind, SurfaceSourceKind.screen);
      expect(identity.payloadKind, SurfacePayloadKind.blob);
      expect(identity.contractVersion, 7);
    },
  );

  test('an explicit specialized paywall selector is non-versioned', () async {
    final identity = await resolveSurfaceLifecycleIdentity(
      argResults: _args(
        tempDir,
        flags: {'type': 'paywall', 'source-kind': 'paywall'},
        rest: ['offer'],
      ),
      fixedSurfaceType: null,
      slug: 'offer',
      stderr: StringBuffer(),
    );

    expect(identity, isNotNull);
    expect(identity!.sourceKind, SurfaceSourceKind.paywall);
    expect(identity.contractVersion, isNull);
  });

  test('source-kind screen requires a positive contract version', () async {
    final error = StringBuffer();

    final identity = await resolveSurfaceLifecycleIdentity(
      argResults: _args(
        tempDir,
        flags: {'type': 'general', 'source-kind': 'screen'},
        rest: ['notice'],
      ),
      fixedSurfaceType: null,
      slug: 'notice',
      stderr: error,
    );

    expect(identity, isNull);
    expect(error.toString(), contains('--source-kind screen'));
    expect(error.toString(), contains('--contract-version'));
  });

  test('specialized paywall rejects a contract version', () async {
    final error = StringBuffer();

    final identity = await resolveSurfaceLifecycleIdentity(
      argResults: _args(
        tempDir,
        flags: {
          'type': 'paywall',
          'source-kind': 'paywall',
          'contract-version': '7',
        },
        rest: ['offer'],
      ),
      fixedSurfaceType: null,
      slug: 'offer',
      stderr: error,
    );

    expect(identity, isNull);
    expect(error.toString(), contains('--source-kind paywall'));
    expect(error.toString(), contains('contract-version'));
  });

  test('does not infer specialized paywall from a category alone', () async {
    final error = StringBuffer();

    final identity = await resolveSurfaceLifecycleIdentity(
      argResults: _args(tempDir, flags: {'type': 'paywall'}, rest: ['offer']),
      fixedSurfaceType: null,
      slug: 'offer',
      stderr: error,
    );

    expect(identity, isNull);
    expect(error.toString(), contains('--source-kind'));
    expect(error.toString(), contains('paywall'));
  });

  test('explicit flow fallback remains non-versioned', () async {
    final identity = await resolveSurfaceLifecycleIdentity(
      argResults: _args(
        tempDir,
        flags: {'type': 'onboarding', 'source-kind': 'flowGraph'},
        rest: ['welcome'],
      ),
      fixedSurfaceType: null,
      slug: 'welcome',
      stderr: StringBuffer(),
    );

    expect(identity, isNotNull);
    expect(identity!.sourceKind, SurfaceSourceKind.flowGraph);
    expect(identity.payloadKind, SurfacePayloadKind.flow);
    expect(identity.contractVersion, isNull);
  });
}

ArgResults _args(
  Directory directory, {
  Map<String, String> flags = const {},
  List<String> rest = const [],
}) {
  final parser = ArgParser()
    ..addOption('type')
    ..addOption('source-kind')
    ..addOption('contract-version')
    ..addOption('directory', abbr: 'C', defaultsTo: '.');
  final args = <String>['--directory', directory.path];
  for (final entry in flags.entries) {
    args
      ..add('--${entry.key}')
      ..add(entry.value);
  }
  args.addAll(rest);
  return parser.parse(args);
}
