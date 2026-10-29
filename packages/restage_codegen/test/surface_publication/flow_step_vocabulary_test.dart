import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';

const _package = 'apps_examples';

const _caption = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('acme.ui'),
  capabilityVersion: 1,
)
const restageLibrary = 0;

@RestageWidget(
  name: 'Caption',
  library: WidgetLibrary.custom('acme.ui'),
  category: WidgetCategory.decoration,
  description: 'A styled caption.',
)
class Caption extends StatelessWidget {
  const Caption({super.key, required this.label, this.style});

  @RestageProperty(description: 'The text.', required: true)
  final Label label;

  @RestageProperty(description: 'The text style.')
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text(label.text, style: style);
}

class Label {
  const Label({required this.text});
  final String text;
}
''';

const _screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../widgets/caption.dart';

part 'restage.generated/styled_notice.restage.g.dart';

@Screen(id: 'styled_notice', surface: Surface.onboarding)
final class StyledNotice extends StatelessWidget {
  const StyledNotice({super.key});

  @override
  Widget build(BuildContext context) =>
      const Caption(
        label: Label(text: 'Hello'),
        style: TextStyle(fontSize: 18),
      );
}
''';

const _flow = '''
import 'package:restage/restage.dart';

import 'styled_notice.dart';

part 'restage.generated/first_run.restage.g.dart';

@FlowGraph(id: 'first_run', surface: Surface.onboarding)
final class FirstRun extends RestageFlow {
  const FirstRun();

  @override
  FlowDef buildFlow() {
    return flow(
      initial: styledNoticeRef,
      states: [screen(styledNoticeRef)],
    );
  }
}
''';

void main() {
  test(
    'a flow reference installs the app widgets its steps draw',
    () async {
      final sources = {
        '$_package|lib/widgets/caption.dart': _caption,
        '$_package|lib/features/styled_notice.dart': _screen,
        '$_package|lib/features/first_run.dart': _flow,
      };
      final readerWriter =
          await readerWriterWithFilesystemSources(rootPackage: _package);
      final result = await testBuilders(
        [
          restageSourceRosterBuilder(BuilderOptions.forRoot),
          userCatalogJsonBuilder(BuilderOptions.empty),
          restagePackageSurfaceCompilerBuilder(
            BuilderOptions.forRoot,
          ),
          restageGeneratedDartBuilder(BuilderOptions.empty),
          restageOutputsBuilder(BuilderOptions.empty),
          userCatalogBuilder(BuilderOptions.forRoot),
          userFactoryBuilder(BuilderOptions.forRoot),
        ],
        sources,
        rootPackage: _package,
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));

      String part(String path) =>
          readerWriter.testing.readString(AssetId(_package, path));
      final flow =
          part('lib/features/restage.generated/first_run.restage.g.dart');
      final step =
          part('lib/features/restage.generated/styled_notice.restage.g.dart');
      // The flow reference itself names its step's app widgets, so a prefetch
      // installs them before any step builds.
      expect(flow, contains('vocabulary: _firstRunRefVocabulary,'));
      expect(
        flow,
        contains('const _firstRunRefVocabulary = SurfaceVocabulary(\n'
            '  libraries: [...styledNoticeAppWidgets],'),
      );
      expect(step, contains('const styledNoticeAppWidgets ='));
      expect(step, contains("WidgetLibrary.custom('acme.ui')"));
    },
  );
}
