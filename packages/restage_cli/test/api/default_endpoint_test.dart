import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:restage_cli/src/cli.dart';
import 'package:test/test.dart';

void main() {
  test('the compiled default endpoint is Restage Cloud', () {
    expect(defaultRestageEndpoint, 'https://api.restage.dev/');
  });

  test(
    'login with no endpoint signs in against Restage Cloud',
    () async {
      final directory = Directory.systemTemp.createTempSync('restage_cli_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final requested = <Uri>[];
      final cli = RestageCli(
        credentialStore: FileCredentialStore(
          '${directory.path}/credentials.json',
        ),
        httpClient: MockClient((request) async {
          requested.add(request.url);
          return http.Response('', 503);
        }),
        sleep: (_) async {},
        openBrowser: (_) async {},
      );

      await cli.run(['login', '-C', directory.path]);

      expect(requested, isNotEmpty);
      expect(requested.first.origin, 'https://api.restage.dev');
    },
    skip: Platform.environment['RESTAGE_BACKEND_URL']?.isNotEmpty ?? false
        ? 'RESTAGE_BACKEND_URL overrides the default'
        : false,
  );

  group("login uses the backend the project names", () {
    late Directory project;
    late List<Uri> requested;
    late StringBuffer stdout;

    setUp(() {
      project = Directory.systemTemp.createTempSync('restage_project_');
      addTearDown(() => project.deleteSync(recursive: true));
      File('${project.path}/pubspec.yaml').writeAsStringSync('name: app\n');
      requested = [];
      stdout = StringBuffer();
    });

    Future<void> login(
      List<String> args, {
      Map<String, String> environment = const {},
      String? from,
    }) => RestageCli(
      stdout: stdout,
      stderr: StringBuffer(),
      environment: environment,
      credentialStore: FileCredentialStore('${project.path}/credentials.json'),
      httpClient: MockClient((request) async {
        requested.add(request.url);
        return http.Response('', 503);
      }),
      sleep: (_) async {},
      openBrowser: (_) async {},
    ).run(['login', '-C', from ?? project.path, ...args]);

    void writeConfig() => File(
      '${project.path}/restage_config.yaml',
    ).writeAsStringSync('endpoint: https://api-example.restage.dev/\n');
    void writeBuildYaml() =>
        File('${project.path}/build.yaml').writeAsStringSync('''
targets:
  \$default:
    builders:
      restage_codegen:user_factories:
        options:
          base_url: http://localhost:9090
''');

    test('restage_config.yaml endpoint, from a subdirectory too', () async {
      writeConfig();
      writeBuildYaml();
      final lib = Directory('${project.path}/lib')..createSync();

      await login(const [], from: lib.path);

      expect(requested.first.origin, 'https://api-example.restage.dev');
      expect(
        stdout.toString(),
        contains(
          'Signing in to https://api-example.restage.dev, which '
          'restage_config.yaml names.\n',
        ),
      );
    });

    test('build.yaml base_url when the config names no endpoint', () async {
      File('${project.path}/restage_config.yaml').writeAsStringSync('app: a\n');
      writeBuildYaml();

      await login(const []);

      expect(requested.first.origin, 'http://localhost:9090');
      expect(
        stdout.toString(),
        contains(
          'Signing in to http://localhost:9090, which build.yaml '
          'names.\n',
        ),
      );
    });

    test('a project file naming another server is refused for sign-in', () async {
      final stderr = StringBuffer();
      Future<int?> refusedLogin(List<String> args) => RestageCli(
        stdout: stdout,
        stderr: stderr,
        environment: const {},
        credentialStore: FileCredentialStore(
          '${project.path}/credentials.json',
        ),
        httpClient: MockClient((request) async {
          requested.add(request.url);
          return http.Response('', 503);
        }),
        sleep: (_) async {},
        openBrowser: (_) async {},
      ).run(['login', '-C', project.path, ...args]);

      File(
        '${project.path}/restage_config.yaml',
      ).writeAsStringSync('endpoint: https://api.restage-dev.example/\n');
      expect(await refusedLogin(const []), 1);
      expect(requested, isEmpty);
      expect(
        stderr.toString(),
        'restage_config.yaml names https://api.restage-dev.example, which is '
        'not a Restage server, so `restage login` will not send a sign-in '
        'there. Try `restage login --endpoint https://api.restage-dev.example` '
        'if you trust that server.\n',
      );

      stderr.clear();
      File('${project.path}/restage_config.yaml').deleteSync();
      File('${project.path}/build.yaml').writeAsStringSync('''
targets:
  \$default:
    builders:
      restage_codegen:user_factories:
        options:
          base_url: http://api.restage.dev
''');
      expect(await refusedLogin(const []), 1);
      expect(requested, isEmpty);
      expect(
        stderr.toString(),
        startsWith(
          'build.yaml names http://api.restage.dev, which is not a '
          'Restage server',
        ),
      );

      // The person's own choice still goes anywhere.
      await refusedLogin(const ['--endpoint', 'https://own.example.dev']);
      expect(requested.single.origin, 'https://own.example.dev');
    });

    test('RESTAGE_BACKEND_URL and --endpoint win over the project', () async {
      writeConfig();

      await login(
        const [],
        environment: const {'RESTAGE_BACKEND_URL': 'https://env.example.dev'},
      );
      expect(requested.last.origin, 'https://env.example.dev');

      await login(
        const ['--endpoint', 'https://flag.example.dev'],
        environment: const {'RESTAGE_BACKEND_URL': 'https://env.example.dev'},
      );
      expect(requested.last.origin, 'https://flag.example.dev');
      expect(stdout.toString(), isNot(contains('Signing in to')));
    });

    test('a config above the package is the one commands use', () async {
      final parent = Directory.systemTemp.createTempSync('restage_parent_');
      addTearDown(() => parent.deleteSync(recursive: true));
      File(
        '${parent.path}/restage_config.yaml',
      ).writeAsStringSync('endpoint: http://127.0.0.1:9191\n');
      final inner = Directory('${parent.path}/app')..createSync();
      File('${inner.path}/pubspec.yaml').writeAsStringSync('name: app\n');

      await login(const [], from: inner.path);

      expect(requested.first.origin, 'http://127.0.0.1:9191');
      final loaded = await loadRestageConfig(from: inner);
      expect(loaded!.config.endpoint, 'http://127.0.0.1:9191');
    });

    test(
      "build.yaml above the package is not the package's",
      () async {
        final parent = Directory.systemTemp.createTempSync('restage_parent_');
        addTearDown(() => parent.deleteSync(recursive: true));
        File('${parent.path}/build.yaml').writeAsStringSync('''
targets:
  \$default:
    builders:
      restage_codegen:user_factories:
        options:
          base_url: http://127.0.0.1:9191
''');
        final inner = Directory('${parent.path}/app')..createSync();
        File('${inner.path}/pubspec.yaml').writeAsStringSync('name: app\n');

        await login(const [], from: inner.path);

        expect(requested.first.origin, 'https://api.restage.dev');
      },
      skip: defaultRestageEndpoint == 'https://api.restage.dev/'
          ? false
          : 'a build with another default endpoint',
    );
  });

  group('the help footer names the server', () {
    late Directory project;

    setUp(() {
      project = Directory.systemTemp.createTempSync('restage_help_');
      addTearDown(() => project.deleteSync(recursive: true));
      File('${project.path}/pubspec.yaml').writeAsStringSync('name: app\n');
    });

    Future<String> help({Map<String, String> environment = const {}}) async {
      final stdout = StringBuffer();
      await RestageCli(
        stdout: stdout,
        stderr: StringBuffer(),
        environment: environment,
        hasTerminal: () => false,
        credentialStore: FileCredentialStore('${project.path}/credentials'),
      ).run(['-C', project.path, '--help']);
      return stdout.toString();
    }

    test(
      'signed out, where a sign-in would go and why',
      () async {
        expect(
          await help(),
          contains(
            'Not signed in. `restage login` signs in to https://api.restage.dev '
            "unless RESTAGE_BACKEND_URL or the project's restage_config.yaml or "
            'build.yaml names another Restage server.',
          ),
        );
        expect(
          await help(
            environment: const {
              'RESTAGE_BACKEND_URL': 'https://env.example.dev',
            },
          ),
          contains(
            'Not signed in. `restage login` signs in to https://env.example.dev, '
            'which RESTAGE_BACKEND_URL names.',
          ),
        );
        File(
          '${project.path}/restage_config.yaml',
        ).writeAsStringSync('endpoint: https://api-example.restage.dev/\n');
        expect(
          await help(),
          contains(
            'Not signed in. `restage login` signs in to '
            'https://api-example.restage.dev, which restage_config.yaml names.',
          ),
        );
      },
      skip: defaultRestageEndpoint == 'https://api.restage.dev/'
          ? false
          : 'a build with another default endpoint',
    );

    test(
      'signed out, a project file naming another server is refused',
      () async {
        File(
          '${project.path}/restage_config.yaml',
        ).writeAsStringSync('endpoint: https://api.restage-dev.example/\n');
        expect(
          await help(),
          contains(
            'Not signed in. restage_config.yaml names '
            'https://api.restage-dev.example, which is not a Restage server',
          ),
        );
      },
    );

    test('signed in, the server commands use', () async {
      File('${project.path}/credentials').writeAsStringSync(
        jsonEncode({
          'endpoint': 'https://api-example.restage.dev/',
          'kind': 'authKey',
          'authToken': 'kid:secret',
        }),
      );
      expect(
        await help(),
        contains(
          'Commands use https://api-example.restage.dev, the server you '
          'signed in to. Run `restage login --endpoint <url>` to use another.',
        ),
      );
    });
  });

  test('a project file may name only Restage Cloud APIs or this machine', () {
    for (final trusted in [
      'https://api.restage.dev/',
      'https://api-example.restage.dev',
      'http://localhost:8080',
      'http://app.localhost',
      'http://127.0.0.1:9000',
      'http://[::1]:9000',
    ]) {
      expect(
        isTrustedProjectBackend(Uri.parse(trusted)),
        isTrue,
        reason: trusted,
      );
    }
    for (final refused in [
      'http://api.restage.dev',
      'https://restage.dev',
      'https://app.restage.dev',
      'https://api.restage.dev.attacker.example',
      'https://api.restage-dev.example',
      'https://apirestage.dev',
      'https://10.0.0.5',
    ]) {
      expect(
        isTrustedProjectBackend(Uri.parse(refused)),
        isFalse,
        reason: refused,
      );
    }
  });

  test('an unreachable sign-in server names how to use another', () async {
    final directory = Directory.systemTemp.createTempSync('restage_cli_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final stderr = StringBuffer();
    final code = await RestageCli(
      stdout: StringBuffer(),
      stderr: stderr,
      credentialStore: FileCredentialStore(
        '${directory.path}/credentials.json',
      ),
      httpClient: MockClient(
        (request) async => throw http.ClientException('lookup failed'),
      ),
      sleep: (_) async {},
      openBrowser: (_) async {},
    ).run(const ['login', '--endpoint', 'https://api.example.dev/']);

    expect(code, 2);
    expect(
      stderr.toString(),
      startsWith('Could not reach https://api.example.dev: '),
    );
    expect(
      stderr.toString(),
      endsWith(
        'To sign in to another server, run `restage login --endpoint <url>`, '
        'or set RESTAGE_BACKEND_URL.\n',
      ),
    );
  });

  test('help names how to use another server', () async {
    final stdout = StringBuffer();
    await RestageCli(
      stdout: stdout,
      stderr: StringBuffer(),
    ).run(const ['--help']);
    expect(stdout.toString(), contains('restage login --endpoint <url>'));

    final login = StringBuffer();
    await RestageCli(
      stdout: login,
      stderr: StringBuffer(),
    ).run(const ['login', '--help']);
    expect(login.toString(), contains('RESTAGE_BACKEND_URL'));
  });
}
