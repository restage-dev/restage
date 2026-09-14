import 'dart:convert';

import 'package:build/build.dart';
import 'package:logging/logging.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// A paywall's compiled blob is the only place some catalog entries appear, so
/// the app-wide vocabulary has to be read from it and not from the Dart.
void main() {
  test('the app vocabulary names a catalog entry only the paywall blob names',
      () async {
    // The interpolation lowers to the rich-text catalog entry, which the Dart
    // never spells — a walk over the app's sources can only ever see `Text`.
    expect(_paywallSource, isNot(contains('TextRich')));

    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
      includeFlutter: true,
    );
    readerWriter.testing.writeString(
      AssetId.parse(_paywallAsset),
      _paywallSource,
    );
    final records = <LogRecord>[];
    final result = await testBuilders(
      [
        restagePackageSurfaceCompilerBuilder(BuilderOptions.empty),
        userFactoryBuilder(BuilderOptions.empty),
      ],
      const {_paywallAsset: _paywallSource},
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
      onLog: records.add,
    );
    final logs = records.map((record) => record.message).join('\n');
    expect(result.succeeded, isTrue, reason: logs);

    final bundle = jsonDecode(
      result.readerWriter.testing.readString(
        AssetId('apps_examples', kRestageSurfacePublicationCompilerBundlePath),
      ),
    ) as Map<String, Object?>;
    expect(
      bundle['surfaceWidgetNames'],
      contains('restage.core:TextRich'),
      reason: logs,
    );
    expect(
      result.readerWriter.testing.readString(
        AssetId('apps_examples', 'lib/user_factories.g.dart'),
      ),
      contains("'TextRich': buildTextRich"),
      reason: logs,
    );
  });
}

const String _paywallAsset = 'apps_examples|lib/paywalls/x_premium.dart';

const String _paywallSource = r'''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Paywall(id: 'x_premium')
class XPremiumPaywall extends StatefulWidget {
  const XPremiumPaywall({super.key});

  @override
  State<XPremiumPaywall> createState() => _XPremiumPaywallState();
}

class _XPremiumPaywallState extends State<XPremiumPaywall> {
  String trialLabel = '7 days free';

  @override
  Widget build(BuildContext context) => Text('$trialLabel remaining');
}
''';
