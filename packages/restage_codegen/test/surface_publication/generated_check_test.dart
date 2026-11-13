import 'dart:convert';

import 'package:build/build.dart';
import 'package:logging/logging.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/generated_check_builder.dart';
import 'package:restage_codegen/src/surface_publication/output_builder.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../helpers.dart';

const _library = '''
import 'package:flutter/widgets.dart';

part 'restage.generated/screen.restage.g.dart';

class Screen extends StatelessWidget {
  const Screen({super.key});
  @override
  Widget build(BuildContext context) => const Text('x');
}
''';

const _brokenPart =
    "part of '../screen.dart';\n\n"
    'final (Text,) pair = (const Text("a") as Widget,);\n';

final String _validBundle = RestageSurfacePublicationBundle.valid(
  manifest: SurfacePublicationManifest(publications: const []),
  artifacts: const {},
).encodeCanonicalJson();

const _stamp = 'apps_examples|.restage/build/metadata/restage.build.json';

// Runs [builders] in one build, as build_runner does, and returns what it
// logged at SEVERE and the build result it recorded.
Future<({bool succeeded, List<String> severe, Map<String, Object?>? stamp})>
_run(List<Builder> builders, Map<String, Object> sources) async {
  final severe = <String>[];
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  final result = await testBuilders(
    builders,
    sources,
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
    onLog: (record) {
      // Without the `<builder> on <input>:` line build_runner prefixes.
      if (record.level >= Level.SEVERE) {
        severe.add(record.message.substring(record.message.indexOf('\n') + 1));
      }
    },
  );
  final stamp = AssetId.parse(_stamp);
  return (
    succeeded: result.succeeded,
    severe: severe,
    stamp: readerWriter.testing.exists(stamp)
        ? jsonDecode(readerWriter.testing.readString(stamp))
              as Map<String, Object?>
        : null,
  );
}

void main() {
  test('the check records a part that does not compile', () async {
    final logs = <String>[];
    final result = await testBuilder(
      const RestageGeneratedCheckBuilder(),
      {
        'apps_examples|lib/screen.dart': _library,
        'apps_examples|lib/restage.generated/screen.restage.g.dart':
            _brokenPart,
      },
      rootPackage: 'apps_examples',
      readerWriter: await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      ),
      onLog: (record) {
        if (record.level >= Level.SEVERE) logs.add(record.message);
      },
      outputs: {
        'apps_examples|$kRestageGeneratedCheckPath': decodedMatches(
          allOf(
            contains(
              "The code generated for lib/screen.dart doesn't compile: "
              'lib/restage.generated/screen.restage.g.dart:3:',
            ),
            contains(
              'Try marking the widget it comes from `@RenderInApp()`, and '
              'report it at https://github.com/restage-dev/restage/issues.',
            ),
          ),
        ),
      },
    );
    // Recorded for the outputs builder, which fails the build.
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    expect(logs, isEmpty);
  });

  test(
    'an authored library that does not compile is named, not its part',
    () async {
      await testBuilder(
        const RestageGeneratedCheckBuilder(),
        {
          'apps_examples|lib/screen.dart': _library.replaceFirst(
            "const Text('x')",
            'const Text(1)',
          ),
          'apps_examples|lib/restage.generated/screen.restage.g.dart':
              _brokenPart,
        },
        rootPackage: 'apps_examples',
        readerWriter: await readerWriterWithFilesystemSources(
          rootPackage: 'apps_examples',
        ),
        outputs: {
          'apps_examples|$kRestageGeneratedCheckPath': decodedMatches(
            allOf(
              contains("lib/screen.dart doesn't compile: lib/screen.dart:"),
              contains('Try fixing it, then run the build again.'),
              isNot(contains('report it')),
            ),
          ),
        },
      );
    },
  );

  test('a part with no library to check is an error, not a pass', () async {
    await testBuilder(
      const RestageGeneratedCheckBuilder(),
      {
        'apps_examples|lib/restage.generated/gone.restage.g.dart':
            "part of '../gone.dart';\n\nconst label = 'x';\n",
      },
      rootPackage: 'apps_examples',
      readerWriter: await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      ),
      outputs: {
        'apps_examples|$kRestageGeneratedCheckPath': decodedMatches(
          contains(
            'lib/restage.generated/gone.restage.g.dart belongs to no library '
            "this build can read, so Restage couldn't check that it compiles.",
          ),
        ),
      },
    );
  });

  test('a generated library that does not compile is recorded', () async {
    await testBuilder(
      const RestageGeneratedCheckBuilder(),
      {
        'apps_examples|lib/user_factories.g.dart':
            "import 'package:flutter/widgets.dart';\n\n"
            'const Widget widget = Text(1);\n',
      },
      rootPackage: 'apps_examples',
      readerWriter: await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      ),
      outputs: {
        'apps_examples|$kRestageGeneratedCheckPath': decodedMatches(
          contains(
            "The code generated in lib/user_factories.g.dart doesn't compile: "
            'lib/user_factories.g.dart:3:',
          ),
        ),
      },
    );
  });

  test('a generated part that compiles passes', () async {
    final result = await testBuilder(
      const RestageGeneratedCheckBuilder(),
      {
        'apps_examples|lib/screen.dart': _library,
        'apps_examples|lib/restage.generated/screen.restage.g.dart':
            "part of '../screen.dart';\n\nconst label = 'x';\n",
      },
      rootPackage: 'apps_examples',
      readerWriter: await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      ),
      outputs: {
        'apps_examples|$kRestageGeneratedCheckPath':
            '{"schemaVersion":1,"errors":[]}',
      },
    );
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
  });

  test(
    'one build: a part that does not compile fails it and is recorded',
    () async {
      final out = await _run(
        [
          const RestageGeneratedCheckBuilder(),
          RestageOutputsBuilder(BuilderOptions.empty),
        ],
        {
          'apps_examples|lib/screen.dart': _library,
          'apps_examples|lib/restage.generated/screen.restage.g.dart':
              _brokenPart,
          'apps_examples|$kRestageSurfacePublicationCompilerBundlePath':
              _validBundle,
        },
      );
      expect(out.succeeded, isFalse);
      expect(out.severe, hasLength(1));
      expect(
        out.severe.single,
        startsWith(
          "The code generated for lib/screen.dart doesn't compile: "
          'lib/restage.generated/screen.restage.g.dart:3:',
        ),
      );
      expect(out.stamp, {
        'schemaVersion': 1,
        'result': 'failed',
        'errors': out.severe,
      });
    },
  );

  test('one build: parts nothing checked fail it', () async {
    final out = await _run(
      [RestageOutputsBuilder(BuilderOptions.empty)],
      {
        'apps_examples|lib/screen.dart': _library,
        'apps_examples|lib/restage.generated/screen.restage.g.dart':
            "part of '../screen.dart';\n\nconst label = 'x';\n",
        'apps_examples|$kRestageSurfacePublicationCompilerBundlePath':
            _validBundle,
      },
    );
    expect(out.succeeded, isFalse);
    expect(out.stamp?['result'], 'failed');
    expect(
      out.severe.single,
      "Restage couldn't check that the code it generated compiles, because "
      "`restage_codegen:generated_check` didn't run. Try enabling that "
      'builder in build.yaml.',
    );
  });

  test('one build: a check that stops fails it and says it stopped', () async {
    final out = await _run(
      [
        const RestageGeneratedCheckBuilder(),
        RestageOutputsBuilder(BuilderOptions.empty),
      ],
      {
        'apps_examples|lib/screen.dart': _library,
        // Not UTF-8, so reading the part throws inside the check.
        'apps_examples|lib/restage.generated/screen.restage.g.dart': const [
          0xc3,
          0x28,
        ],
        'apps_examples|$kRestageSurfacePublicationCompilerBundlePath':
            _validBundle,
      },
    );
    expect(out.succeeded, isFalse);
    expect(out.stamp?['result'], 'failed');
    expect(
      out.severe.single,
      allOf(
        startsWith(
          "Restage's check that the code it generated compiles stopped with "
          'an error: ',
        ),
        endsWith(
          'This is a Restage bug. Try running `dart run build_runner build` '
          'again. If it stops again, report it at '
          'https://github.com/restage-dev/restage/issues.',
        ),
        isNot(contains("didn't run")),
      ),
    );
  });

  test('one build: a compiler refusal fails it, named in the record', () async {
    final out = await _run(
      [RestageOutputsBuilder(BuilderOptions.empty)],
      {
        'apps_examples|$kRestageSurfacePublicationCompilerBundlePath':
            RestageSurfacePublicationBundle.invalid(const [
              '[duplicateId] lib/a.dart@1:1: two paywalls share an id.',
            ]).encodeCanonicalJson(),
      },
    );
    expect(out.succeeded, isFalse);
    expect(out.severe, [
      '[duplicateId] lib/a.dart@1:1: two paywalls share an id.',
    ]);
    expect(out.stamp, {
      'schemaVersion': 1,
      'result': 'failed',
      'errors': ['[duplicateId] lib/a.dart@1:1: two paywalls share an id.'],
    });
  });

  test(
    'one build: no readable compiler result fails it and is recorded',
    () async {
      final out = await _run(
        [RestageOutputsBuilder(BuilderOptions.empty)],
        {
          'apps_examples|lib/screen.dart': _library,
        },
      );
      const message =
          "Restage has no result from compiling the package's surfaces. Try "
          'running `dart run build_runner clean`, then '
          '`dart run build_runner build`.';
      expect(out.succeeded, isFalse);
      expect(out.severe, [message]);
      expect(out.stamp, {
        'schemaVersion': 1,
        'result': 'failed',
        'errors': [message],
      });
    },
  );

  test('one build: a package with no parts and no check succeeds', () async {
    final out = await _run(
      [RestageOutputsBuilder(BuilderOptions.empty)],
      {
        'apps_examples|$kRestageSurfacePublicationCompilerBundlePath':
            _validBundle,
      },
    );
    expect(out.succeeded, isTrue, reason: out.severe.join('\n'));
    expect(out.stamp?['result'], 'succeeded');
  });
}
