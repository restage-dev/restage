import 'package:build/build.dart';
import 'package:restage_codegen/src/project_backend.dart';
import 'package:restage_codegen/src/user_factory_builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('docsOriginForConfig', () {
    test('reads the published docs without an endpoint', () {
      expect(docsOriginForConfig(null), 'https://docs.restage.dev');
      expect(docsOriginForConfig('project: p\n'), 'https://docs.restage.dev');
      expect(docsOriginForConfig(': not yaml ['), 'https://docs.restage.dev');
    });

    test("follows the endpoint's docs", () {
      expect(
        docsOriginForConfig('endpoint: https://api-preview.restage.dev\n'),
        'https://docs-preview.restage.dev',
      );
      expect(
        docsOriginForConfig('endpoint: https://api.example.com\n'),
        'https://docs.restage.dev',
      );
    });
  });

  test("the build's app-size link follows restage_config.yaml", () async {
    const homeSource = '''
      import 'package:flutter/material.dart';

      class Home extends StatelessWidget {
        const Home({super.key});

        @override
        Widget build(BuildContext context) => const Text('home');
      }
    ''';
    const config = 'endpoint: https://api-preview.restage.dev\n';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    readerWriter.testing
      ..writeString(
        AssetId('apps_examples', 'lib/screens/home.dart'),
        homeSource,
      )
      ..writeString(AssetId('apps_examples', 'restage_config.yaml'), config);

    final messages = <String>[];
    await testBuilder(
      const UserFactoryBuilder(BuilderOptions({'catalog': 'derived'})),
      {
        'apps_examples|lib/screens/home.dart': homeSource,
        'apps_examples|restage_config.yaml': config,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      onLog: (record) => messages.add(record.message),
    );

    final summary = messages.singleWhere(
      (message) => message.contains('Restage: a surface'),
    );
    expect(
      summary,
      contains('https://docs-preview.restage.dev/delivery/app-size'),
    );
    expect(summary, isNot(contains('https://docs.restage.dev')));
  });
}
