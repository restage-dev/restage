import 'dart:convert';

import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import 'helpers.dart';

String _paywall({required bool localValue}) => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Paywall()
class ReminderPaywall extends StatefulWidget {
  const ReminderPaywall({super.key});

  @override
  State<ReminderPaywall> createState() => _ReminderPaywallState();
}

class _ReminderPaywallState extends State<ReminderPaywall> {
  bool reminders = true;

  @override
  Widget build(BuildContext context) => Switch(
        value: reminders,
        onChanged: ${localValue ? '(on) => setState(() => reminders = on)' : 'null'},
      );
}
''';

Future<TestReaderWriter> _build(String source) async {
  final readerWriter =
      await readerWriterWithFilesystemSources(rootPackage: 'apps_examples');
  final result = await testBuilder(
    restageCodegenBuilder(BuilderOptions.empty),
    {'apps_examples|lib/paywalls/reminder_paywall.dart': source},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
  return readerWriter;
}

void main() {
  test('a paywall with local values writes its seeds beside its blob',
      () async {
    final readerWriter = await _build(_paywall(localValue: true));

    final seeds = readerWriter.testing.readBytes(
      AssetId('apps_examples', 'assets/paywalls/reminder_paywall.local.json'),
    );
    expect(decodeLocalSeedsArtifact(seeds), {
      'Paywall': {'reminders': true},
    });
    final sidecar = CapabilitySidecar.fromJson(
      jsonDecode(
        readerWriter.testing.readString(
          AssetId(
            'apps_examples',
            'assets/paywalls/reminder_paywall.capability.json',
          ),
        ),
      ) as Map<String, dynamic>,
    );
    expect(sidecar.manifest.builtInFloor, kSurfaceFeatureClientFloor);

    final compiled = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      {
        'apps_examples|lib/paywalls/reminder_paywall.dart': _paywall(
          localValue: true,
        )
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(compiled.succeeded, isTrue, reason: compiled.errors.join('\n'));
    final handoff = RestageSurfacePublicationBundle.fromJson(
      jsonDecode(
        readerWriter.testing.readString(
          AssetId(
              'apps_examples', kRestageSurfacePublicationCompilerBundlePath),
        ),
      ),
    );
    expect(handoff.valid, isTrue, reason: handoff.errors.join('\n'));
    final entry = handoff.manifest!.publications.singleWhere(
      (entry) => entry.publication.payloadKind == SurfacePayloadKind.blob,
    );
    final artifact = entry.artifacts.singleWhere(
      (artifact) => artifact.role == SurfacePublicationArtifactRole.localSeeds,
    );
    expect(artifact.path, 'assets/paywalls/reminder_paywall.local.json');
    final files = {...handoff.artifacts, ...handoff.borrowedArtifacts};
    expect(decodeLocalSeedsArtifact(files[artifact.path]!), {
      'Paywall': {'reminders': true},
    });
  });

  test('a paywall without local values writes no seeds', () async {
    final readerWriter = await _build(_paywall(localValue: false));

    expect(
      readerWriter.testing.exists(
        AssetId('apps_examples', 'assets/paywalls/reminder_paywall.local.json'),
      ),
      isFalse,
    );
  });
}
