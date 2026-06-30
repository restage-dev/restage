import 'publish_closeout.dart' as closeout;

void main() {
  _testDiscoversSameCommitPackageTags();
  _testUsesCuratedReleaseNotesManifest();
  _testGeneratesFallbackReleaseNotesFromChangelogs();
  _testOnlyCuratedNotesUpdateExistingReleases();
}

void _testDiscoversSameCommitPackageTags() {
  final tags = closeout.planRelease(
    tagNames: [
      'restage_codegen-v1.0.4',
      'not-a-release',
      'restage_a2ui-v0.1.3',
      'restage_codegen-vbad',
    ],
    pubspecVersions: {
      'restage_codegen': '1.0.4',
      'restage_a2ui': '0.1.3',
    },
    changelogs: const {},
  );

  _expect(tags.headlineTag, 'restage_codegen-v1.0.4');
  _expect(
    tags.packages.map((pkg) => '${pkg.name}:${pkg.version}').join(','),
    'restage_codegen:1.0.4,restage_a2ui:0.1.3',
  );
}

void _testUsesCuratedReleaseNotesManifest() {
  final plan = closeout.planRelease(
    tagNames: [
      'restage_codegen-v1.0.4',
      'restage_a2ui-v0.1.3',
    ],
    pubspecVersions: {
      'restage_codegen': '1.0.4',
      'restage_a2ui': '0.1.3',
    },
    changelogs: const {},
    curatedNotes: const {
      'restage_codegen-v1.0.4': '''
---
title: A2UI standalone schema completeness
packages:
  - restage_a2ui
  - restage_codegen
---
Curated notes body.
''',
    },
  );

  _expect(plan.headlineTag, 'restage_codegen-v1.0.4');
  _expect(plan.title, 'A2UI standalone schema completeness');
  _expect(plan.body.trim(), 'Curated notes body.');
  _expect(
    plan.packages.map((pkg) => pkg.name).join(','),
    'restage_a2ui,restage_codegen',
  );
}

void _testGeneratesFallbackReleaseNotesFromChangelogs() {
  final plan = closeout.planRelease(
    tagNames: ['restage_codegen-v1.0.4'],
    pubspecVersions: {'restage_codegen': '1.0.4'},
    changelogs: const {
      'restage_codegen': '''
# Changelog

## 1.0.4

- Carry full schemas.
- Suppress unused helpers.

## 1.0.3

- Older entry.
''',
    },
  );

  _expect(plan.title, 'restage_codegen 1.0.4');
  _expect(plan.body.contains('| `restage_codegen` | 1.0.4 |'), true);
  _expect(plan.body.contains('- Carry full schemas.'), true);
  _expect(plan.body.contains('- Older entry.'), false);
}

void _testOnlyCuratedNotesUpdateExistingReleases() {
  final generated = closeout.planRelease(
    tagNames: ['restage_codegen-v1.0.4'],
    pubspecVersions: {'restage_codegen': '1.0.4'},
    changelogs: const {},
  );
  final curated = closeout.planRelease(
    tagNames: ['restage_codegen-v1.0.4'],
    pubspecVersions: {'restage_codegen': '1.0.4'},
    changelogs: const {},
    curatedNotes: const {
      'restage_codegen-v1.0.4': '''
---
title: Keep this title
---
Keep this body.
''',
    },
  );

  _expect(generated.updateExistingRelease, false);
  _expect(curated.updateExistingRelease, true);
}

void _expect(Object? actual, Object? expected) {
  if (actual != expected) {
    throw StateError('expected <$expected>, got <$actual>');
  }
}
