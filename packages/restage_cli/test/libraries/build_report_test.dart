import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/commands/build_report_command.dart';
import 'package:restage_cli/src/libraries/build_report.dart';
import 'package:test/test.dart';

Map<String, Object?> _site(
  String kind,
  String name,
  String widget,
  String location, {
  String? reason,
  String? token,
  int? widgets,
}) => {
  'surface': 'lib/paywall.dart#Paywall',
  'mount': 'PaywallSurface',
  'name': name,
  'widget': widget,
  'location': location,
  'kind': kind,
  'reason': ?reason,
  'token': ?token,
  'widgets': ?widgets,
};

final _first = [
  _site('design', 'PaywallSurface', 'Paywall', 'lib/paywall.dart', widgets: 9),
  _site(
    'island',
    'app.islands:Paywall_ListView_0',
    'ListView',
    'lib/paywall.dart:12:7',
    reason: 'Restage can\'t translate `_scroll`.',
    token: 'w0001',
    widgets: 3,
  ),
  _site('value', '_h01', 'offer.title', 'lib/paywall.dart:9:5'),
  _site('action', '_h02', '() => buy()', 'lib/paywall.dart:20:12'),
  _site(
    'mount',
    'BlocListener',
    'BlocListener',
    'lib/paywall.dart:6:12',
    reason: 'notDelivered',
  ),
];

void main() {
  test(
    'the build report lists each part and what changed since the baseline',
    () async {
      final root = Directory.systemTemp.createTempSync('build_report_');
      addTearDown(() => root.deleteSync(recursive: true));
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: app\n');
      final handoff = File(
        p.join(
          root.path,
          '.dart_tool/build/generated/app/lib/src/surface_publication/'
          'surface_publication.compiler.json',
        ),
      )..createSync(recursive: true);
      void build(List<Map<String, Object?>> sites) =>
          handoff.writeAsStringSync(jsonEncode({'splitSites': sites}));
      Future<(int, List<String>, String)> run(List<String> flags) async {
        final out = StringBuffer();
        final err = StringBuffer();
        final runner = CommandRunner<int>('restage', '')
          ..addCommand(BuildReportCommand(stdout: out, stderr: err));
        final code = await runner.run(['report', '-C', root.path, ...flags]);
        return (code!, const LineSplitter().convert('$out'), '$err'.trim());
      }

      const mountLine =
          '`PaywallSurface` (lib/paywall.dart): designs can change 9 of its '
          '12 widgets (75%).';
      const partLines = [
        '  `ListView` (lib/paywall.dart:12:7) renders from the app. Restage '
            "can't translate `_scroll`.",
        '  App code computes `offer.title` (lib/paywall.dart:9:5).',
        '  App code runs `() => buy()` (lib/paywall.dart:20:12).',
        '  App code keeps `BlocListener` (lib/paywall.dart:6:12) around '
            'every design.',
      ];
      const noBaseline =
          'There is no restage_build_report.json to compare with. Try running '
          '`restage build report --accept` to record this build.';

      // Each step: the build, the flags, the exit code, the last lines and
      // stderr.
      final steps = <(List<Map<String, Object?>>?, List<String>, int, List<String>, String)>[
        (_first, const [], 0, [mountLine, ...partLines, noBaseline], ''),
        (null, const ['--check'], 1, [noBaseline], noBaseline),
        (
          null,
          const ['--accept'],
          0,
          ['Recorded this build in restage_build_report.json.'],
          '',
        ),
        (
          null,
          const ['--check'],
          0,
          [
            'The widgets that render from the app and the wrappers kept for '
                'every design match restage_build_report.json.',
          ],
          '',
        ),
        (
          [
            // The island moved and changed, a second one appeared, and the
            // wrapper is no longer kept.
            for (final site in _first)
              if (site['kind'] == 'island')
                {...site, 'location': 'lib/paywall.dart:14:7', 'token': 'w0009'}
              else if (site['kind'] != 'mount')
                site,
            _site(
              'island',
              'app.islands:Paywall_Fade_0',
              'Fade',
              'lib/paywall.dart:30:9',
              token: 'w0002',
            ),
          ],
          const ['--check'],
          1,
          [
            'Changes since restage_build_report.json:',
            '  The app code of `ListView` (lib/paywall.dart:14:7) in '
                '`PaywallSurface` changed. Live versions that show it fall back '
                'to the screen compiled into the app until you republish them.',
            '  `Fade` (lib/paywall.dart:30:9) in `PaywallSurface` now renders '
                'from the app.',
            '  App code no longer keeps `BlocListener` in `PaywallSurface` for '
                'every design.',
          ],
          'This build differs from restage_build_report.json. Try reviewing '
              'the changes above, then running `restage build report --accept`.',
        ),
      ];
      for (final (sites, flags, code, tail, err) in steps) {
        if (sites != null) build(sites);
        final (exit, lines, stderr) = await run(flags);
        expect(exit, code, reason: '$flags');
        expect(
          lines.sublist(lines.length - tail.length),
          tail,
          reason: '$flags',
        );
        expect(stderr, err, reason: '$flags');
      }

      // JSON carries the shares, the parts and the changes.
      final (_, lines, _) = await run(const ['--json']);
      final json = jsonDecode(lines.join('\n')) as Map<String, Object?>;
      final mount = (json['mounts']! as List).single as Map<String, Object?>;
      expect(
        [mount['mount'], mount['delivered'], mount['app']],
        ['PaywallSurface', 9, 4],
      );
      expect(
        [for (final part in mount['parts']! as List) (part as Map)['kind']],
        ['island', 'value', 'action', 'island'],
      );
      expect(
        [
          for (final change in json['changes']! as List)
            (change as Map)['kind'],
        ],
        ['islandChanged', 'islandAdded', 'keptRemoved'],
      );
    },
  );

  test('the build report suggests a widget class where one pays off', () {
    BuildReportPart island(String mount, String location, String interface) =>
        BuildReportPart(
          kind: 'island',
          mount: mount,
          name: 'app.islands:$mount',
          widget: 'Tinted',
          location: location,
          interface: interface,
          promotion: {'class': '/// $mount\nclass {{name}} {}'},
        );
    expect(
      BuildReport([
        island('ASurface', 'lib/a.dart:3:5', ''),
        island('BSurface', 'lib/b.dart:4:5', ''),
      ]).promotionSuggestions,
      [
        'The same app code renders `Tinted` in `ASurface`, `BSurface`. Try '
            '`restage widget promote lib/a.dart:3:5` to move it into one '
            'widget class that designs can use.',
      ],
    );
    expect(
      BuildReport([
        island(
          'ASurface',
          'lib/a.dart:3:5',
          'property a: integer\nproperty b: integer\nproperty c: string',
        ),
      ]).promotionSuggestions,
      [
        '`Tinted` (lib/a.dart:3:5) takes 3 values from the design. Try '
            '`restage widget promote lib/a.dart:3:5` to name them in the '
            'editor.',
      ],
    );
  });
}
