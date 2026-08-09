import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/user_catalog_builder.dart';
import 'package:restage_codegen/src/user_factory_builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('RFW callback contract production builders', () {
    for (final payload in const [
      'List<List<String>>',
      'List<String>?',
    ]) {
      test(
        '$payload fails both builders before catalog/factory divergence',
        () async {
          final source = '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A callback-contract probe.
@RestageWidget(
  name: 'CallbackProbe',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.input,
)
class CallbackProbe {
  const CallbackProbe({this.onChanged});

  /// Reports the changed value.
  final void Function($payload)? onChanged;
}
''';
          final sourceId = AssetId(
            'apps_examples',
            'lib/widgets/callback_probe.dart',
          );
          final cases = <({Builder builder, String output})>[
            (
              builder: const UserCatalogBuilder(BuilderOptions.empty),
              output: 'lib/user_catalog.g.dart',
            ),
            (
              builder: const UserFactoryBuilder(BuilderOptions.empty),
              output: 'lib/user_factories.g.dart',
            ),
          ];

          for (final builderCase in cases) {
            final readerWriter = await readerWriterWithFilesystemSources(
              rootPackage: 'apps_examples',
              includeFlutter: false,
            );
            readerWriter.testing.writeString(sourceId, source);
            final logs = <String>[];

            final result = await testBuilder(
              builderCase.builder,
              {sourceId.toString(): source},
              rootPackage: 'apps_examples',
              readerWriter: readerWriter,
              onLog: (record) => logs.add(record.message),
            );

            expect(result.succeeded, isFalse, reason: builderCase.output);
            expect(
              logs.join('\n'),
              allOf(
                contains('[invalidEventConfiguration]'),
                contains(
                  'lib/widgets/callback_probe.dart#'
                  'CallbackProbe.onChanged',
                ),
                contains(payload),
              ),
              reason: builderCase.output,
            );
            expect(
              readerWriter.testing.exists(
                AssetId('apps_examples', builderCase.output),
              ),
              isFalse,
              reason: builderCase.output,
            );
          }
        },
      );
    }
  });
}
