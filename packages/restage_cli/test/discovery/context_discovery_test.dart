import 'package:restage_cli/src/api/discovery_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/discovery/context_discovery.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:test/test.dart';

class _FakeRestageApi implements RestageApi {
  _FakeRestageApi({required this.response});

  final dynamic response;

  @override
  Future<dynamic> call(
    String endpointName,
    String methodName,
    Map<String, dynamic> args,
  ) async {
    return response;
  }

  @override
  void close() {}
}

void main() {
  group('resolveActiveOrganization', () {
    test('returns the sole organization without prompting', () async {
      final organization = await resolveActiveOrganization(
        api: DiscoveryApi(
          _FakeRestageApi(
            response: <dynamic>[
              {'organizationId': 7, 'slug': 'default', 'name': 'Default'},
            ],
          ),
        ),
        interactive: const NonInteractive(),
        stderr: StringBuffer(),
      );

      expect(organization, isNotNull);
      expect(organization!.organizationId, 7);
      expect(organization.slug, 'default');
    });

    test(
      'returns the preferred slug when several organizations exist',
      () async {
        final organization = await resolveActiveOrganization(
          api: DiscoveryApi(
            _FakeRestageApi(
              response: <dynamic>[
                {'organizationId': 7, 'slug': 'default', 'name': 'Default'},
                {'organizationId': 8, 'slug': 'team', 'name': 'Team'},
              ],
            ),
          ),
          interactive: const NonInteractive(),
          stderr: StringBuffer(),
          preferredSlug: 'team',
        );

        expect(organization, isNotNull);
        expect(organization!.organizationId, 8);
        expect(organization.slug, 'team');
      },
    );

    test('rejects an explicit unknown preferred slug', () async {
      final stderr = StringBuffer();

      final organization = await resolveActiveOrganization(
        api: DiscoveryApi(
          _FakeRestageApi(
            response: <dynamic>[
              {'organizationId': 7, 'slug': 'default', 'name': 'Default'},
              {'organizationId': 8, 'slug': 'team', 'name': 'Team'},
            ],
          ),
        ),
        interactive: const NonInteractive(),
        stderr: stderr,
        preferredSlug: 'missing',
      );

      expect(organization, isNull);
      expect(
        stderr.toString(),
        contains('No organization found for --organization <slug>: missing.'),
      );
    });

    test('does not prompt after an explicit unknown preferred slug', () async {
      final stderr = StringBuffer();

      final organization = await resolveActiveOrganization(
        api: DiscoveryApi(
          _FakeRestageApi(
            response: <dynamic>[
              {'organizationId': 7, 'slug': 'default', 'name': 'Default'},
              {'organizationId': 8, 'slug': 'team', 'name': 'Team'},
            ],
          ),
        ),
        interactive: _FailingInteractive(),
        stderr: stderr,
        preferredSlug: 'missing',
      );

      expect(organization, isNull);
      expect(stderr.toString(), contains('missing'));
    });

    test('fails closed in non-interactive mode when ambiguous', () async {
      final stderr = StringBuffer();

      final organization = await resolveActiveOrganization(
        api: DiscoveryApi(
          _FakeRestageApi(
            response: <dynamic>[
              {'organizationId': 7, 'slug': 'default', 'name': 'Default'},
              {'organizationId': 8, 'slug': 'team', 'name': 'Team'},
            ],
          ),
        ),
        interactive: const NonInteractive(),
        stderr: stderr,
      );

      expect(organization, isNull);
      expect(stderr.toString(), contains('--organization'));
    });
  });
}

class _FailingInteractive implements Interactive {
  @override
  bool get isInteractive => true;

  @override
  Future<bool> confirm(String question, {bool defaultYes = false}) async =>
      fail('confirm should not be called');

  @override
  Future<String> prompt(String question, {String? defaultValue}) async =>
      fail('prompt should not be called');

  @override
  Future<T> select<T>(
    String question,
    List<({String label, T value})> options, {
    T? defaultValue,
  }) async => fail('select should not be called');

  @override
  Future<String> secret(String question) async =>
      fail('secret should not be called');

  @override
  Spinner spinner(String message) => fail('spinner should not be called');
}
