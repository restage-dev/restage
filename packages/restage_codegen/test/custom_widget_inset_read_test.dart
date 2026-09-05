// An inset read inside a custom widget. The widget's own build context is
// decided by whatever composes it, so the inset published at the surface's
// mount point is not the value there, and the read refuses.

import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const String _package = 'apps_examples';

const String _customWidget = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@RestageWidget(
  name: 'InsetSpacer',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'inset spacer',
)
class InsetSpacer extends StatelessWidget {
  const InsetSpacer({super.key});

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: MediaQuery.paddingOf(context).top);
}
''';

const String _screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'package:apps_examples/widgets/inset_spacer.dart';

@Paywall()
class CustomInset extends StatelessWidget {
  const CustomInset({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(children: [InsetSpacer()]);
  }
}
''';

const String _screenRead = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Paywall()
class ScreenInset extends StatelessWidget {
  const ScreenInset({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(height: MediaQuery.paddingOf(context).top),
    );
  }
}
''';

Future<TestReaderWriter> _seeded(Map<String, String> sources) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: _package,
    includeFlutter: true,
  );
  for (final entry in sources.entries) {
    readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
  }
  return readerWriter;
}

Future<String> _refusalLog(Map<String, String> sources) async {
  final logs = <String>[];
  await testBuilder(
    restageCodegenBuilder(BuilderOptions.empty),
    sources,
    rootPackage: _package,
    readerWriter: await _seeded(sources),
    outputs: const {},
    onLog: (record) => logs.add(record.message),
  );
  return logs.join('\n');
}

void main() {
  test('a read inside a custom widget refuses', () async {
    final log = await _refusalLog({
      '$_package|lib/widgets/inset_spacer.dart': _customWidget,
      '$_package|lib/paywalls/custom_inset.dart': _screen,
    });

    expect(log, contains('read inside a custom widget'));
  });

  test('a screen read under a SafeArea keeps the published inset', () async {
    final sources = {'$_package|lib/paywalls/screen_inset.dart': _screenRead};
    final result = await testBuilders(
      [restageCodegenBuilder(BuilderOptions.empty)],
      sources,
      rootPackage: _package,
      readerWriter: await _seeded(sources),
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    expect(
      result.readerWriter.testing
          .readString(AssetId(_package, 'assets/paywalls/screen_inset.rfwtxt')),
      contains('data.device.safeAreaTop'),
    );
  });
}
