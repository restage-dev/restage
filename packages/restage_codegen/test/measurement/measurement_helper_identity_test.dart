import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:restage_codegen/src/measurement/measurement_event_occurrence.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test('helper identities name the declaring class or extension', () async {
    final identities = await resolveSources(
      {
        'a|lib/helpers.dart': '''
int topLevel() => 0;

class Helpers {
  static int row() => 0;
}

extension First on int {
  static int row() => 0;
}

extension Second on int {
  static int row() => 0;
}
''',
      },
      (resolver) async {
        final library = await resolver.libraryFor(
          AssetId.parse('a|lib/helpers.dart'),
        );
        return [
          library.topLevelFunctions.single,
          library.getClass('Helpers')!.methods.single,
          for (final extension in library.extensions) extension.methods.single,
        ].map<String>((ExecutableElement helper) {
          return measurementHelperIdentity(helper);
        }).toList();
      },
    );

    expect(identities, [
      'package:a/helpers.dart#topLevel.topLevel',
      'package:a/helpers.dart#Helpers.row',
      'package:a/helpers.dart#First.row',
      'package:a/helpers.dart#Second.row',
    ]);
  });
}
