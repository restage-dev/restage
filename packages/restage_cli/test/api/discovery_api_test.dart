import 'package:restage_cli/src/api/discovery_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:test/test.dart';

class FakeRestageApi implements RestageApi {
  FakeRestageApi({required this.response});

  final dynamic response;
  String? lastEndpoint;
  String? lastMethod;
  Map<String, dynamic>? lastArgs;

  @override
  Future<dynamic> call(
    String endpointName,
    String methodName,
    Map<String, dynamic> args,
  ) async {
    lastEndpoint = endpointName;
    lastMethod = methodName;
    lastArgs = args;
    return response;
  }

  @override
  void close() {}
}

void main() {
  group('DiscoveryApi', () {
    test('listOrganizations posts organization/listMine', () async {
      final fake = FakeRestageApi(
        response: <dynamic>[
          {
            'organizationId': 7,
            'slug': 'default',
            'name': 'Default',
            'role': 'owner',
          },
        ],
      );

      final organizations = await DiscoveryApi(fake).listOrganizations();

      expect(fake.lastEndpoint, 'organization');
      expect(fake.lastMethod, 'listMine');
      expect(fake.lastArgs, isEmpty);
      expect(organizations.single.organizationId, 7);
      expect(organizations.single.slug, 'default');
    });

    test(
      'listWorkspaceExperiences maps the existing organization projection',
      () async {
        final fake = FakeRestageApi(
          response: <dynamic>[
            {
              'organizationId': 7,
              'provenance': 'sample',
              'sampleGeneration': 3,
              'seedVersion': 'northwind-v1',
              'hostedAccessState': 'sandbox',
              'productionAllowed': false,
              'canRequestProduction': false,
              'canResetSample': true,
              'canDeleteSample': true,
              'pairedOrganizationId': 8,
            },
          ],
        );

        final workspaces = await DiscoveryApi(fake).listWorkspaceExperiences();

        expect(fake.lastEndpoint, 'organization');
        expect(fake.lastMethod, 'listWorkspaceExperiences');
        expect(fake.lastArgs, isEmpty);
        expect(workspaces.single.organizationId, 7);
        expect(workspaces.single.provenance, 'sample');
        expect(workspaces.single.hostedAccessState, 'sandbox');
        expect(workspaces.single.productionAllowed, isFalse);
      },
    );

    test('listProjects posts project/listProjects with the org id', () async {
      final fake = FakeRestageApi(
        response: <dynamic>[
          {'slug': 'default', 'name': 'Default'},
        ],
      );

      final projects = await DiscoveryApi(fake).listProjects(7);

      expect(fake.lastEndpoint, 'project');
      expect(fake.lastMethod, 'listProjects');
      expect(fake.lastArgs!['organizationId'], 7);
      expect(projects.single.slug, 'default');
    });

    test('listApps threads org id + project slug', () async {
      final fake = FakeRestageApi(
        response: <dynamic>[
          {'slug': 'default', 'name': 'Default'},
        ],
      );

      final apps = await DiscoveryApi(
        fake,
      ).listApps(organizationId: 7, projectSlug: 'default');

      expect(fake.lastEndpoint, 'app');
      expect(fake.lastMethod, 'listApps');
      expect(fake.lastArgs!['organizationId'], 7);
      expect(fake.lastArgs!['projectSlug'], 'default');
      expect(apps.single.name, 'Default');
    });

    test('listEnvironments threads org id + project slug', () async {
      final fake = FakeRestageApi(
        response: <dynamic>[
          {'slug': 'staging'},
        ],
      );

      final environments = await DiscoveryApi(
        fake,
      ).listEnvironments(organizationId: 7, projectSlug: 'default');

      expect(fake.lastEndpoint, 'environment');
      expect(fake.lastMethod, 'listEnvironments');
      expect(fake.lastArgs!['organizationId'], 7);
      expect(fake.lastArgs!['projectSlug'], 'default');
      expect(fake.lastArgs!.containsKey('appSlug'), isFalse);
      expect(environments.single.slug, 'staging');
    });
  });
}
