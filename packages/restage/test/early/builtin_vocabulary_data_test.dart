import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart' show Restage;
import 'package:restage/src/runtime/builtin_icon_table.dart';
import 'package:restage/src/runtime/installed_widget_vocabulary.dart';
import 'package:restage_core/restage_core.dart'
    show InstalledIconTable, RestageIconTable;
import 'package:restage_core/library_registration.dart' as core;
import 'package:restage_core/registry.dart' as core_registry;
import 'package:restage_cupertino/library_registration.dart' as cupertino;
import 'package:restage_cupertino/registry.dart' as cupertino_registry;
import 'package:restage_material/library_registration.dart' as material;
import 'package:restage_material/registry.dart' as material_registry;
import 'package:restage_shared/restage_shared.dart';

const _path =
    '../restage_shared/lib/src/capability/builtin_icon_code_points.g.dart';

Map<String, Set<int>> _flutterCodePoints() {
  final table = builtInIconTable();
  return {
    for (final family in {...table.families.keys, ...table.mirrored.keys})
      family: {
        ...?table.families[family]?.keys,
        ...?table.mirrored[family]?.keys,
      },
  };
}

String _ranges(Set<int> points) {
  final sorted = points.toList()..sort();
  final out = <int>[];
  for (var i = 0; i < sorted.length;) {
    var j = i;
    while (j + 1 < sorted.length && sorted[j + 1] == sorted[j] + 1) {
      j++;
    }
    out
      ..add(sorted[i])
      ..add(j - i + 1);
    i = j + 1;
  }
  return out.join(', ');
}

void main() {
  test('the shared icon code point data matches the Flutter icon tables', () {
    final flutter = _flutterCodePoints();
    if (Platform.environment['UPDATE_ICON_DATA'] == '1') {
      final body = StringBuffer()
        ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
        ..writeln('// Regenerate: UPDATE_ICON_DATA=1 flutter test '
            'test/early/builtin_vocabulary_data_test.dart (in packages/restage).')
        ..writeln()
        ..writeln('/// Code points of the built-in icon families, as '
            '(first, count) runs.')
        ..writeln('const Map<String, List<int>> kBuiltInIconCodePointRuns = {');
      for (final family in flutter.keys.toList()..sort()) {
        body.writeln("  '$family': [${_ranges(flutter[family]!)}],");
      }
      body.writeln('};');
      File(_path).writeAsStringSync(body.toString());
    }
    expect(
      builtInIconCodePoints(),
      flutter,
      reason: 'Regenerate the data with UPDATE_ICON_DATA=1.',
    );
    expect(RestageIconTable.materialIconsFamily, 'MaterialIcons');
  });

  test('each library catalog names exactly the widgets its factories build',
      () {
    Set<String> names(dynamic catalog) => {
          for (final w in catalog.widgets as Iterable<dynamic>) w.name as String
        };
    expect({...names(core_registry.kRegistry), kBuilderContinuationWidgetName},
        core.kCoreLibraryFactories.keys.toSet());
    expect(names(material_registry.kRegistry),
        material.kMaterialLibraryFactories.keys.toSet());
    expect(names(cupertino_registry.kRegistry),
        cupertino.kCupertinoLibraryFactories.keys.toSet());
  });

  test('a whole-catalog app presents the vocabulary the shared data names', () {
    Restage.debugReset();
    addTearDown(Restage.debugReset);
    Restage.configure();
    final vocabulary = currentInstalledCapability().vocabulary!;
    Set<String> qualified(String namespace, dynamic catalog) => {
          for (final w in catalog.widgets as Iterable<dynamic>)
            WidgetVocabulary.qualifiedName(namespace, w.name as String),
        };
    expect(vocabulary.widgetNames, {
      ...qualified('restage.core', core_registry.kRegistry),
      WidgetVocabulary.qualifiedName(
          'restage.core', kBuilderContinuationWidgetName),
      ...qualified('restage.material', material_registry.kRegistry),
      ...qualified('restage.cupertino', cupertino_registry.kRegistry),
    });
    // Configuration alone installs no built-in icons.
    expect(vocabulary.iconCodePoints, isEmpty);
  });

  test('an app that keeps every built-in icon presents the shared icon data',
      () {
    Restage.debugReset();
    addTearDown(Restage.debugReset);
    addTearDown(InstalledIconTable.reset);
    InstalledIconTable.add(builtInIconTable());
    Restage.configure();
    expect(
      currentInstalledCapability().vocabulary!.iconCodePoints,
      builtInIconCodePoints(),
    );
  });
}
