import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_story_builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test('rejects legacy auxiliary authoring options', () {
    expect(
      () => createWidgetbookStoryBuilder(
        const BuilderOptions(
          {
            'hosts': {
              'package:example/widget.dart#Widget':
                  'package:example/host.dart#host',
            },
            'suppress': ['package:example/widget.dart#Widget'],
          },
        ),
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('no per-widget authoring options'),
            contains('hosts'),
            contains('suppress'),
          ),
        ),
      ),
    );
  });

  test('preserves public callback defaults through production story output',
      () async {
    const output =
        'apps_examples|lib/generated/callback_default_card.stories.dart';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    var generated = '';
    await testBuilder(
      const WidgetbookStoryBuilder({
        'lib/callback_default_card.dart': [
          'lib/generated/callback_default_card.stories.dart',
        ],
      }),
      const {
        'apps_examples|lib/callback_defaults.dart': _publicCallbackDefaults,
        'apps_examples|lib/callback_default_card.dart': _callbackDefaultCard,
        'widgetbook|lib/widgetbook.dart': _widgetbookStub,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      outputs: {
        output: decodedMatches(
          allOf(<Matcher>[
            predicate<String>(
              (source) {
                generated = source;
                return true;
              },
              'captures generated story source',
            ),
            contains(
              "import 'package:apps_examples/callback_defaults.dart' "
              'as restage_native_0;',
            ),
            contains('this.onTap = true'),
            contains('this.onChanged = true'),
            contains('this.onSubmitted = false'),
            contains('this.onDismissed = false'),
            contains(
              'onTap: args.onTap ? restage_native_0.topLevelCallback : () {}',
            ),
            matches(
              RegExp(
                r'onChanged: args\.onChanged\s*\?\s*'
                r'restage_native_0\.PublicCallbacks\.staticCallback\s*:\s*null',
              ),
            ),
            contains('onSubmitted: (_) {}'),
            contains('onDismissed: args.onDismissed ? () {} : null'),
          ]),
        ),
      },
    );

    await resolveSources(
      {
        'apps_examples|lib/callback_defaults.dart': _publicCallbackDefaults,
        'apps_examples|lib/callback_default_card.dart': _callbackDefaultCard,
        output: generated,
        'apps_examples|lib/generated/callback_default_card.stories.g.dart':
            _storyPartStub,
        'widgetbook|lib/widgetbook.dart': _widgetbookStub,
      },
      (resolver) async {
        final library = await resolver.libraryFor(
          AssetId(
            'apps_examples',
            'lib/generated/callback_default_card.stories.dart',
          ),
        );
        final resolved =
            await library.session.getResolvedLibraryByElement(library);
        if (resolved is! ResolvedLibraryResult) {
          throw StateError('Generated callback-default story did not resolve.');
        }
        final errors = [
          for (final unit in resolved.units)
            for (final diagnostic in unit.diagnostics)
              if (diagnostic.severity == Severity.error)
                diagnostic.problemMessage.messageText(includeUrl: false),
        ];
        expect(errors, isEmpty, reason: generated);
      },
      resolverFor: output,
      rootPackage: 'apps_examples',
      readAllSourcesFromFilesystem: true,
    );
  });

  test('rejects a private callback default at its constructor-default path',
      () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final logs = <String>[];
    await testBuilder(
      const WidgetbookStoryBuilder({
        'lib/private_callback_card.dart': [
          'lib/generated/private_callback_card.stories.dart',
        ],
      }),
      const {
        'apps_examples|lib/private_callback_card.dart': _privateCallbackCard,
        'widgetbook|lib/widgetbook.dart': _widgetbookStub,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      onLog: (record) => logs.add('${record.level.name}: ${record.message}'),
    );
    expect(
      logs.join('\n'),
      allOf(
        contains('/constructorDefaults/onTap'),
        contains('_privateCallback'),
      ),
    );
  });
}

const _publicCallbackDefaults = '''
void topLevelCallback() {}

class PublicCallbacks {
  static void staticCallback(String value) {}
}
''';

const _callbackDefaultCard = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

import 'callback_defaults.dart';

@RestageWidget(
  name: 'CallbackDefaultCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.input,
  description: 'Callback constructor-default probe.',
)
class CallbackDefaultCard extends StatelessWidget {
  const CallbackDefaultCard({
    required this.onSubmitted,
    this.onTap = topLevelCallback,
    this.onChanged = PublicCallbacks.staticCallback,
    this.onDismissed,
  });

  /// Invoked for taps.
  final VoidCallback onTap;

  /// Invoked when the value changes.
  final ValueChanged<String>? onChanged;

  /// Invoked when a value is submitted.
  final ValueChanged<String> onSubmitted;

  /// Invoked when the card is dismissed.
  final VoidCallback? onDismissed;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const _privateCallbackCard = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

void _privateCallback() {}

@RestageWidget(
  name: 'PrivateCallbackCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.input,
  description: 'Private callback constructor-default probe.',
)
class PrivateCallbackCard extends StatelessWidget {
  const PrivateCallbackCard({this.onTap = _privateCallback});

  /// Invoked for taps.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const _widgetbookStub = '''
class Meta {
  const Meta(Object constructor, {required Object argsType});
}

class ComponentMeta {
  const ComponentMeta({required this.path});
  final String path;
}

class Arg<T> {
  Arg(this.value, {this.name});
  final T value;
  final String? name;
  String? get description => null;
}

mixin NoFields<T> on Arg<T> {}

class BoolArg extends Arg<bool> {
  BoolArg(super.value, {super.name});
}
''';

const _storyPartStub = '''
part of 'callback_default_card.stories.dart';

typedef _Defaults = CallbackDefaultCardDefaults;
typedef _Story = CallbackDefaultCardStory;
typedef _Args = CallbackDefaultCardArgs;

typedef CallbackDefaultCardBuilder = restage_source.CallbackDefaultCard
    Function(Object? context, CallbackDefaultCardStoryInput args);

final class CallbackDefaultCardDefaults {
  CallbackDefaultCardDefaults({required this.builder});
  final CallbackDefaultCardBuilder builder;
}

final class CallbackDefaultCardStory {
  CallbackDefaultCardStory({required this.args});
  final CallbackDefaultCardArgs args;
}

final class CallbackDefaultCardArgs {
  CallbackDefaultCardArgs({
    required Object description,
    required Object usage,
    required Object onTap,
    required Object onChanged,
    required Object onSubmitted,
    required Object onDismissed,
  });
}
''';
