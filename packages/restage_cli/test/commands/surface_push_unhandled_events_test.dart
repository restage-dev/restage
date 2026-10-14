import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/commands/surface_push_command.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:test/test.dart';

import '../_helpers/publication_fixtures.dart';
import '../_helpers/test_fixtures.dart';

void main() {
  late Directory app;
  late Directory home;
  late FileCredentialStore store;
  late StringBuffer out;
  late StringBuffer err;

  setUp(() async {
    app = await Directory.systemTemp.createTemp('surface_push_events_');
    home = await Directory.systemTemp.createTemp('surface_push_events_home_');
    store = FileCredentialStore(p.join(home.path, 'credentials'));
    await seedCredential(store);
    out = StringBuffer();
    err = StringBuffer();
    File(p.join(app.path, 'restage_config.yaml')).writeAsStringSync(
      'project: demo\napp: mobile\ndefaultEnvironment: staging\n',
    );
  });

  tearDown(() {
    app.deleteSync(recursive: true);
    home.deleteSync(recursive: true);
  });

  test(
    'push warns about a flow that drops a screen event and pushes',
    () async {
      await seedDroppingFlow(app);
      final methods = <String>[];
      final client = mockHttpClient((request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        methods.add(body['method'] as String);
        return publishSucceeded(
          'notice',
          surfaceType: 'onboarding',
          sourceKind: 'flowGraph',
        );
      });

      final exit =
          await (CommandRunner<int>('restage', '')..addCommand(
                SurfacePushCommand(
                  stdout: out,
                  stderr: err,
                  interactive: const NonInteractive(),
                  credentialStore: store,
                  httpClient: client,
                ),
              ))
              .run(['push', 'notice', '-C', app.path]);

      expect(exit, 0, reason: err.toString());
      expect(methods, contains('publishPublication'));
      expect(
        err.toString(),
        contains(
          'The flow "notice" does not handle every event its screens emit:\n'
          '- the screen "notice" in the state "notice" emits "dropped"\n'
          'Add a transition for each event in that state, or declare it as a '
          'custom event if the app handles it.',
        ),
      );
    },
  );
}
