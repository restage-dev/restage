import 'dart:convert';

import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('AppBar text styles lower to distinct structured values', () async {
    const source = '''
      import 'package:flutter/material.dart';
      $kStubAnnotationsAndBases

      @PaywallSource(id: 'styled_app_bar')
      class StyledAppBar extends StatelessWidget {
        const StyledAppBar();
        Widget build(BuildContext context) => Scaffold(
          appBar: AppBar(
            title: const Text('Welcome'),
            actions: const [Text('Done')],
            titleTextStyle: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF112233),
              letterSpacing: 1,
            ),
            toolbarTextStyle: const TextStyle(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: Color(0xFF445566),
              height: 1.5,
            ),
          ),
          body: const SizedBox(),
        );
      }
    ''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
      includeFlutter: true,
    );
    final sourceId =
        AssetId('apps_examples', 'lib/paywalls/styled_app_bar.dart');
    readerWriter.testing.writeString(sourceId, source);

    final result = await testBuilder(
      restageCodegenBuilder(BuilderOptions.empty),
      {sourceId.toString(): source},
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      outputs: {
        'apps_examples|assets/paywalls/styled_app_bar.rfwtxt': decodedMatches(
          allOf(
            contains('titleTextStyle: {color: 0xFF112233, fontSize: 24.0, '
                'fontWeight: "w700", letterSpacing: 1.0}'),
            contains('toolbarTextStyle: {color: 0xFF445566, fontSize: 14.0, '
                'fontStyle: "italic", height: 1.5}'),
          ),
        ),
        'apps_examples|assets/paywalls/styled_app_bar.rfw': isNotEmpty,
        'apps_examples|assets/paywalls/styled_app_bar.capability.json':
            decodedMatches(
          predicate<String>(
            (text) {
              final sidecar = jsonDecode(text) as Map<String, dynamic>;
              final manifest = sidecar['manifest'] as Map<String, dynamic>;
              return manifest['builtInFloor'] == 12;
            },
          ),
        ),
        'apps_examples|assets/paywalls/screens/paywall_styled_app_bar.rfw':
            isNotEmpty,
        'apps_examples|assets/paywalls/screens/paywall_styled_app_bar.capability.json':
            anything,
      },
    );
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
  });
}
