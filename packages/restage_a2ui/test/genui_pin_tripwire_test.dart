import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:yaml/yaml.dart';

/// Walks up from the current directory to the workspace root and reads the
/// resolved `genui` version from `pubspec.lock` (the Melos workspace shares one
/// lock at the root, above the package dir the test runs from). `pubspec.lock`
/// is YAML, so parse it as YAML rather than hand-scanning indentation. Returns
/// null if no lock with a resolved `genui` entry is found.
String? _resolvedGenuiVersion() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    final lock = File('${dir.path}/pubspec.lock');
    if (lock.existsSync()) {
      final doc = loadYaml(lock.readAsStringSync());
      final packages = doc is YamlMap ? doc['packages'] : null;
      if (packages is YamlMap && packages['genui'] is YamlMap) {
        return (packages['genui'] as YamlMap)['version']?.toString();
      }
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break; // reached filesystem root
    dir = parent;
  }
  return null;
}

/// The genui-version-pin loudness tripwire. All A2UI render/tie proofs pin genui
/// 0.9.2; genui's surface/catalog contracts move between minors (its own 0.8 ->
/// 0.9 migration is the precedent). A bump MUST re-baseline these proofs — and
/// that re-baseline must be LOUD, never a silent green against a changed
/// contract. Two complementary tripwires:
///
///  * (a) the RESOLVED genui version equals the pinned 0.9.2 — a cheap early
///    tripwire so a `pub upgrade` past the pin red-flags the proofs before any
///    contract even changes;
///  * (b) genui still enforces the `v0.9` A2UI wire contract — the STRONGER
///    property: the render proofs' golden payloads carry `version: 'v0.9'`, so a
///    genui wire-contract move fails those proofs loud rather than passing
///    against a changed contract.
void main() {
  test('the resolved genui version is the pinned 0.9.2', () {
    final version = _resolvedGenuiVersion();
    expect(
      version,
      isNotNull,
      reason:
          'could not resolve genui from any pubspec.lock above the test '
          'directory',
    );
    expect(
      version,
      '0.9.2',
      reason:
          'the resolved genui version drifted from the pinned 0.9.2 — the '
          'A2UI render/tie proofs pin this contract. Re-baseline them '
          'consciously (re-run the render + fail-closed proofs) before moving '
          'the pin.',
    );
  });

  test('genui still enforces the v0.9 A2UI wire contract', () {
    // The render proofs' golden payloads carry version "v0.9". If genui moves
    // the wire (e.g. to v0.10), this — and those proofs — fail loud.
    expect(
      () => A2uiMessage.fromJson(const {
        'version': 'v0.10',
        'createSurface': {'surfaceId': 's', 'catalogId': 'c'},
      }),
      throwsA(anything),
      reason:
          'genui accepted a non-v0.9 A2UI message — the wire contract moved '
          'and the golden-payload proofs must be re-baselined against the new '
          'contract.',
    );

    // And the pinned contract still accepts v0.9 (guards against a false
    // positive where fromJson throws for an unrelated reason).
    expect(
      A2uiMessage.fromJson(const {
        'version': 'v0.9',
        'createSurface': {'surfaceId': 's', 'catalogId': 'c'},
      }),
      isA<CreateSurface>(),
    );
  });
}
