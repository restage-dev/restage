import 'dart:io';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

Map<dynamic, dynamic> _resolvedPackages() {
  var dir = Directory.current;
  while (true) {
    final lock = File('${dir.path}/pubspec.lock');
    if (lock.existsSync()) {
      final doc = loadYaml(lock.readAsStringSync()) as YamlMap;
      final packages = doc['packages'] as YamlMap;
      if (packages.containsKey('a2ui_flutter')) return packages;
    }
    if (dir.parent.path == dir.path) {
      throw StateError('workspace lock not found');
    }
    dir = dir.parent;
  }
}

void main() {
  test('the workspace resolves the candidate renderer and core versions', () {
    final packages = _resolvedPackages();
    expect((packages['a2ui_flutter'] as YamlMap)['version'], '0.0.1-wip003');
    // The pubspec allows ^0.4.0: any 0.4.x patch.
    expect(
      (packages['a2ui_core'] as YamlMap)['version'] as String,
      matches(RegExp(r'^0\.4\.\d+$')),
    );
    expect(packages.containsKey('genui'), isFalse);
    expect(packages.containsKey('a2ui_agent'), isFalse);
  });
  test('v1 wire and catalog version spellings are distinct', () {
    expect(A2uiProtocolVersion.v1_0.jsonValue, 'v1.0');
    expect(A2uiProtocolVersion.v1_0.semverValue, '1.0');
    expect(
      AgentToRendererMessage.parseAll([
        {
          'version': 'v1.0',
          'createSurface': {'surfaceId': 's'},
        },
      ], protocolVersion: A2uiProtocolVersion.v1_0).messages.single,
      isA<CreateSurfaceMessage>(),
    );
    expect(
      () => AgentToRendererMessage.parseAll([
        {
          'version': 'v0.9',
          'createSurface': {'surfaceId': 's', 'catalogId': 'c'},
        },
      ], protocolVersion: A2uiProtocolVersion.v1_0),
      throwsA(anything),
    );
  });
}
