import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:restage_cli/src/api/experiment_activation_api.dart';
import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/commands/experiment_activation_command.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as measurement;
import 'package:test/test.dart';

void main() {
  test('an injected authority still requires the low-level opt-in', () async {
    var calls = 0;
    final stdout = StringBuffer();
    final stderr = StringBuffer();
    final cli = RestageCli(
      stdout: stdout,
      stderr: stderr,
      experimentActivationApi: ExperimentActivationApi(
        transport: (bytes) async {
          calls += 1;
          return bytes;
        },
      ),
      hasTerminal: () => false,
      environment: const {'RESTAGE_EXPERIMENTAL': 'false'},
    );

    expect(await cli.run(const ['--help']), 0);
    expect(stdout.toString(), contains('experiment'));
    expect(stdout.toString(), isNot(contains('experiment-activation')));
    expect(
      await cli.run(const [
        'experiment-activation',
        '--request=unused.json',
        '--response=unused-result.json',
      ]),
      1,
    );
    expect(stderr.toString(), contains('RESTAGE_EXPERIMENTAL=1'));
    expect(calls, 0);
  });

  test(
    'rejects an empty command file before invoking its authority transport',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'activation-cli-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final request = File('${directory.path}/command.json');
      final response = File('${directory.path}/result.json');
      await request.writeAsBytes(const []);
      var calls = 0;
      final stderr = StringBuffer();
      final runner = CommandRunner<int>('restage', 'test')
        ..addCommand(
          ExperimentActivationCommand(
            api: ExperimentActivationApi(
              transport: (bytes) async {
                calls += 1;
                return bytes;
              },
            ),
            stdout: StringBuffer(),
            stderr: stderr,
            environment: const {'RESTAGE_EXPERIMENTAL': '1'},
          ),
        );

      final exitCode = await runner.run([
        'experiment-activation',
        '--request',
        request.path,
        '--response',
        response.path,
      ]);

      expect(exitCode, 1);
      expect(calls, isZero);
      expect(stderr.toString(), contains('1..'));
    },
  );

  test('a live activation needs --yes when non-interactive', () async {
    final directory = await Directory.systemTemp.createTemp('activation-cli-');
    addTearDown(() => directory.delete(recursive: true));
    final request = File('${directory.path}/command.json');
    await request.writeAsBytes(
      measurement.CanonicalJsonCodec.encode({
        'target': measurement.TargetCoordinate(
          organizationId: measurement.OrganizationId(7),
          appId: measurement.ApplicationId(11),
          environmentTargetId: measurement.EnvironmentTargetId(44),
          namedEnvironmentId: measurement.NamedEnvironmentId(440),
          runtimePlane: measurement.RuntimePlane.live,
        ).toJson(),
      }),
    );
    var calls = 0;
    final stderr = StringBuffer();
    CommandRunner<int> runner() => CommandRunner<int>('restage', 'test')
      ..argParser.addFlag('yes', negatable: false)
      ..addCommand(
        ExperimentActivationCommand(
          api: ExperimentActivationApi(
            transport: (bytes) async {
              calls += 1;
              return bytes;
            },
          ),
          stdout: StringBuffer(),
          stderr: stderr,
          environment: const {'RESTAGE_EXPERIMENTAL': '1'},
        ),
      );
    final args = [
      'experiment-activation',
      '--request',
      request.path,
      '--response',
      '${directory.path}/result.json',
    ];

    expect(await runner().run(args), 1);
    expect(calls, isZero);
    expect(stderr.toString(), contains('changes what the live plane serves'));

    await runner().run(['--yes', ...args]);
    expect(calls, 1);
  });

  test(
    'registers the activation command only when an authority is injected',
    () async {
      final stdout = StringBuffer();
      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: StringBuffer(),
        experimentActivationApi: ExperimentActivationApi(
          transport: (bytes) async => bytes,
        ),
        hasTerminal: () => false,
      ).run(const ['experiment-activation', '--help']);

      expect(exitCode, 0);
      expect(
        stdout.toString(),
        contains('Apply one exact canonical experiment'),
      );
    },
  );

  test(
    'does not register the activation command without an authority',
    () async {
      final stdout = StringBuffer();
      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: StringBuffer(),
        hasTerminal: () => false,
      ).run(const ['--help']);

      expect(exitCode, 0);
      expect(stdout.toString(), isNot(contains('experiment-activation')));
    },
  );
}
