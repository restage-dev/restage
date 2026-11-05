import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/commands/promote_command.dart';
import 'package:test/test.dart';

const _source = '''
class _PromoState extends State<Promo> {
  final int _tint = 3;
  @override
  Widget build(BuildContext context) => Column(children: [
        Tinted(tint: _tint + 1, child: const Text('slot')),
      ]);
}
''';

const _original = "Tinted(tint: _tint + 1, child: const Text('slot'))";

const _class = '''
@RestageWidget()
class {{name}} extends StatelessWidget {
  const {{name}}({super.key, required this.tint, required this.child});
  final int tint;
  final Widget child;

  @override
  Widget build(BuildContext context) => Tinted(tint: tint + 1, child: child);
}''';

void main() {
  test('promote moves a widget into a class the widget library exports', () async {
    // Each case: what it changes first, the arguments, the exit code and
    // the output line, then what the files hold.
    final cases = <(String, void Function(Directory root)?, List<String>, int, String)>[
      (
        'no place',
        null,
        ['lib/promo.dart:1'],
        1,
        'Nothing at lib/promo.dart:1 renders from the app. Try `restage '
            'build report` to see what does.',
      ),
      (
        'stale source',
        (root) => File(
          p.join(root.path, 'lib/promo.dart'),
        ).writeAsStringSync(_source.replaceFirst('_tint + 1', '_tint + 2')),
        ['lib/promo.dart:5'],
        1,
        'lib/promo.dart changed since the last build. Try running `dart run '
            'build_runner build`, then `restage widget promote` again.',
      ),
      (
        'no library',
        (root) => File(p.join(root.path, 'lib/widgets.dart')).deleteSync(),
        ['lib/promo.dart:5'],
        1,
        'No library in the package has a `@RestageLibrary` annotation to '
            'export the new widget from. Try adding one under lib/, or passing '
            'one with `--library`.',
      ),
      (
        'promoted',
        null,
        ['lib/promo.dart:5:9', '--name', 'PromoTint'],
        0,
        'Moved the widget into the new class `PromoTint` in lib/promo.dart '
            'and exported it from lib/widgets.dart. Run `dart run build_runner '
            'build` to compile it.',
      ),
    ];
    for (final (label, change, arguments, code, line) in cases) {
      final root = _project();
      addTearDown(() => root.deleteSync(recursive: true));
      change?.call(root);
      final out = StringBuffer();
      final err = StringBuffer();
      final runner = CommandRunner<int>('restage', '')
        ..addCommand(WidgetCommand(stdout: out, stderr: err));
      final exit = await runner.run([
        'widget',
        'promote',
        '-C',
        root.path,
        ...arguments,
      ]);
      expect(exit, code, reason: label);
      expect('$out$err'.trim(), line, reason: label);
      if (code != 0) continue;
      final promo = File(
        p.join(root.path, 'lib/promo.dart'),
      ).readAsStringSync();
      expect(
        promo,
        _source.replaceFirst(
              _original,
              "PromoTint(tint: _tint, child: const Text('slot'))",
            ) +
            '\n${_class.replaceAll('{{name}}', 'PromoTint')}\n',
      );
      expect(
        File(p.join(root.path, 'lib/widgets.dart')).readAsStringSync(),
        "import 'package:restage/restage.dart';\n"
        "export 'promo.dart' show PromoTint;\n"
        '@RestageLibrary(capabilityVersion: 1)\n'
        'const restageLibrary = 0;\n',
      );
    }
  });
}

Directory _project() {
  final root = Directory.systemTemp.createTempSync('promote_');
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: app\n');
  File(p.join(root.path, 'lib/promo.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync(_source);
  File(p.join(root.path, 'lib/widgets.dart')).writeAsStringSync(
    "import 'package:restage/restage.dart';\n"
    '@RestageLibrary(capabilityVersion: 1)\n'
    'const restageLibrary = 0;\n',
  );
  File(
      p.join(
        root.path,
        '.dart_tool/build/generated/app/lib/src/surface_publication/'
        'surface_publication.compiler.json',
      ),
    )
    ..createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode({
        'splitSites': [
          {
            'surface': 'lib/promo.dart#Promo',
            'mount': 'PromoSurface',
            'name': 'app.islands:Promo_Tinted_0',
            'widget': 'Tinted',
            'location': 'lib/promo.dart:5:9',
            'kind': 'island',
            'promotion': {
              'file': 'lib/promo.dart',
              'offset': _source.indexOf(_original),
              'original': _original,
              'class': _class,
              'call': "{{name}}(tint: _tint, child: const Text('slot'))",
            },
          },
        ],
      }),
    );
  return root;
}
