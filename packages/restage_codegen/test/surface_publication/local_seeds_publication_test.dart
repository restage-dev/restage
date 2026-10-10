import 'dart:convert';

import 'package:build/build.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../helpers.dart';

const _screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/reminders.restage.g.dart';

@Screen(id: 'reminders', surface: Surface.general)
final class Reminders extends StatefulWidget {
  const Reminders({super.key});

  @override
  State<Reminders> createState() => _RemindersState();
}

final class _RemindersState extends State<Reminders> {
  bool reminders = true;

  @override
  Widget build(BuildContext context) => Switch(
        value: reminders,
        onChanged: (on) => setState(() => reminders = on),
      );
}
''';

void main() {
  test('a screen with local values publishes its seeds beside its blob',
      () async {
    final sources = {'apps_examples|lib/features/reminders.dart': _screen};
    final readerWriter =
        await readerWriterWithFilesystemSources(rootPackage: 'apps_examples');
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));

    final handoff = RestageSurfacePublicationBundle.fromJson(
      jsonDecode(
        readerWriter.testing.readString(
          AssetId(
              'apps_examples', kRestageSurfacePublicationCompilerBundlePath),
        ),
      ),
    );
    expect(handoff.valid, isTrue, reason: handoff.errors.join('\n'));
    final manifest = handoff.manifest!;
    final entry = manifest.publications.single;
    final blob = entry.artifacts.singleWhere(
      (artifact) => artifact.role == SurfacePublicationArtifactRole.screenBlob,
    );
    final seeds = entry.artifacts.singleWhere(
      (artifact) => artifact.role == SurfacePublicationArtifactRole.localSeeds,
    );
    expect(seeds.id, 'reminders');
    expect(
      seeds.path,
      '${blob.path.substring(0, blob.path.indexOf('.'))}.local.json',
    );

    final files = {...handoff.artifacts, ...handoff.borrowedArtifacts};
    final closure = manifest.validateArtifactClosure(files).single;
    expect(closure.localSeeds, {
      'OnboardingScreen': {'reminders': true},
    });
    expect(
      entry.publication.capabilities!.builtInFloor,
      kSurfaceFeatureClientFloor,
    );
  });

  test('screens with identical blobs keep their own seeds', () async {
    String screen(String id, String type, bool initial) => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/$id.restage.g.dart';

@Screen(id: '$id', surface: Surface.general)
final class $type extends StatefulWidget {
  const $type({super.key});

  @override
  State<$type> createState() => _${type}State();
}

final class _${type}State extends State<$type> {
  bool reminders = $initial;

  @override
  Widget build(BuildContext context) => Switch(
        value: reminders,
        onChanged: (on) => setState(() => reminders = on),
      );
}
''';
    final sources = {
      'apps_examples|lib/features/on_first.dart':
          screen('on_first', 'OnFirst', true),
      'apps_examples|lib/features/off_first.dart':
          screen('off_first', 'OffFirst', false),
    };
    final readerWriter =
        await readerWriterWithFilesystemSources(rootPackage: 'apps_examples');
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));

    final handoff = RestageSurfacePublicationBundle.fromJson(
      jsonDecode(
        readerWriter.testing.readString(
          AssetId(
              'apps_examples', kRestageSurfacePublicationCompilerBundlePath),
        ),
      ),
    );
    final manifest = handoff.manifest!;
    final files = {...handoff.artifacts, ...handoff.borrowedArtifacts};
    final closures = manifest.validateArtifactClosure(files);
    final seedsBySlug = {
      for (final (index, entry) in manifest.publications.indexed)
        entry.publication.slug: closures[index].localSeeds,
    };
    expect(seedsBySlug['on_first'], {
      'OnboardingScreen': {'reminders': true},
    });
    expect(seedsBySlug['off_first'], {
      'OnboardingScreen': {'reminders': false},
    });
  });

  test('a paywall pushed in a navigation flow keeps its seeds', () async {
    const home = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'reminder_plan.dart';

part 'restage.generated/offer_home.restage.g.dart';

@Paywall()
class OfferHome extends StatelessWidget {
  const OfferHome({super.key});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          ElevatedButton(
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(builder: (_) => const ReminderPlan()),
            ),
            child: const Text('Choose'),
          ),
          TextButton(
            onPressed: paywallEvent('skip'),
            child: const Text('Not now'),
          ),
        ],
      );
}
''';
    const plan = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/reminder_plan.restage.g.dart';

@Paywall()
class ReminderPlan extends StatefulWidget {
  const ReminderPlan({super.key});

  @override
  State<ReminderPlan> createState() => _ReminderPlanState();
}

class _ReminderPlanState extends State<ReminderPlan> {
  bool reminders = true;

  @override
  Widget build(BuildContext context) => Switch(
        value: reminders,
        onChanged: (on) => setState(() => reminders = on),
      );
}
''';
    final readerWriter =
        await readerWriterWithFilesystemSources(rootPackage: 'apps_examples');
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      {
        'apps_examples|lib/paywalls/offer_home.dart': home,
        'apps_examples|lib/paywalls/reminder_plan.dart': plan,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));

    final handoff = RestageSurfacePublicationBundle.fromJson(
      jsonDecode(
        readerWriter.testing.readString(
          AssetId(
              'apps_examples', kRestageSurfacePublicationCompilerBundlePath),
        ),
      ),
    );
    expect(handoff.valid, isTrue, reason: handoff.errors.join('\n'));
    final manifest = handoff.manifest!;
    final files = {...handoff.artifacts, ...handoff.borrowedArtifacts};
    final closures = manifest.validateArtifactClosure(files);
    final flow = [
      for (final (index, entry) in manifest.publications.indexed)
        if (entry.publication.payloadKind == SurfacePayloadKind.flow)
          closures[index],
    ].single;
    expect(flow.localSeeds.values, [
      {'reminders': true},
    ]);
  });
}
