// A GestureDetector's hit-test behavior reaches the delivered surface, so a
// parent tap over a passive child works as it does in Flutter.

import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const String _package = 'apps_examples';

void main() {
  test('GestureDetector carries its hit-test behavior', () async {
    const source = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Paywall()
class PassiveTap extends StatelessWidget {
  const PassiveTap({super.key});

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: paywallEvent('start'),
        child: const IgnorePointer(child: Text('Start')),
      );
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: _package,
      includeFlutter: true,
    );
    const id = '$_package|lib/paywalls/passive_tap.dart';
    readerWriter.testing.writeString(AssetId.parse(id), source);
    final result = await testBuilders(
      [restageCodegenBuilder(BuilderOptions.empty)],
      {id: source},
      rootPackage: _package,
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    expect(
      result.readerWriter.testing.readString(
        AssetId(_package, 'assets/paywalls/passive_tap.rfwtxt'),
      ),
      contains('behavior: "opaque"'),
    );
    expect(
      result.readerWriter.testing.readString(
        AssetId(_package, 'assets/paywalls/passive_tap.capability.json'),
      ),
      contains('"builtInFloor":16'),
      reason: 'an older client must refuse a surface it would mis-tap',
    );
  });
}
