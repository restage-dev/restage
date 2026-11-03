@TestOn('vm')
@Timeout(Duration(minutes: 4))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

// The canonical encoder compiled to JavaScript and to Wasm, where the host
// encodes UTF-8, writes the same bytes as on the VM.
const _values = <Object?>[
  'plain',
  'a"b\\c\n\t\u0001\u007f',
  'caf\u00E9 \u{1F600} \uE000\uFFFD \u2028',
  {'\u{1F600}': 1, '\uFFFD': 2, 'z': 3, 'B': 4, 'a': 'x'},
  [
    null,
    true,
    -9007199254740991,
    {'k': 'v'},
  ],
];

const _program = '''
import 'dart:convert';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

void main() {
  final values = jsonDecode(VALUES) as List<Object?>;
  for (final value in values) {
    print(base64.encode(CanonicalJsonCodec.encode(value)));
  }
}
''';

const _wasmRunner = '''
import { readFileSync } from 'node:fs';
const [loader, module, host] = process.argv.slice(2);
if (host === 'none') delete globalThis.TextEncoder;
const { compile } = await import(loader);
const app = await (await compile(readFileSync(module))).instantiate({});
app.invokeMain();
''';

void main() {
  final node = _which('node');
  final expected = [
    for (final value in _values)
      base64.encode(CanonicalJsonCodec.encode(value)),
  ];
  late Directory work;
  late String packages;

  setUpAll(() async {
    work = await Directory.systemTemp.createTemp('canonical_host_encoder');
    packages = (await Isolate.packageConfig)!.toFilePath();
    final source = _program.replaceFirst(
      'VALUES',
      "r'''${jsonEncode(_values)}'''",
    );
    await File('${work.path}/main.dart').writeAsString(source);
  });
  tearDownAll(() => work.delete(recursive: true));

  Future<List<String>> run(List<String> command) async {
    final result = await Process.run(command.first, command.skip(1).toList());
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    return const LineSplitter().convert(result.stdout as String);
  }

  Future<void> compile(String target, String output) => run([
        Platform.resolvedExecutable,
        'compile',
        target,
        '--packages=$packages',
        '-o',
        output,
        '${work.path}/main.dart',
      ]);

  // A host without a TextEncoder takes the Dart encoder.
  for (final host in ['TextEncoder', 'none']) {
    test('compiled to JavaScript, host $host', () async {
      final runner = _requireNode(node);
      final program = '${work.path}/main.js';
      if (!File(program).existsSync()) await compile('js', program);
      final preload = '${work.path}/no_text_encoder.cjs';
      await File(preload).writeAsString('delete globalThis.TextEncoder;\n');
      expect(
        await run([
          runner,
          if (host == 'none') ...['-r', preload],
          program,
        ]),
        expected,
      );
    });

    test('compiled to Wasm, host $host', () async {
      final runner = _requireNode(node);
      final module = '${work.path}/main.wasm';
      if (!File(module).existsSync()) await compile('wasm', module);
      await File('${work.path}/run.mjs').writeAsString(_wasmRunner);
      expect(
        await run([
          runner,
          '${work.path}/run.mjs',
          Uri.file('${work.path}/main.mjs').toString(),
          module,
          host,
        ]),
        expected,
      );
    });
  }
}

// Node runs the compiled encoders; a run without it fails, so CI never skips.
String _requireNode(String? node) {
  if (node == null) fail('node is not on PATH; this test needs it to run');
  return node;
}

String? _which(String name) {
  for (final directory in (Platform.environment['PATH'] ?? '').split(':')) {
    final file = File('$directory/$name');
    if (file.existsSync()) return file.path;
  }
  return null;
}
