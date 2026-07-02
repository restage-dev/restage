import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/discovery_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/commands/organization_resolution.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';

/// Resolved auth + organization context for org-scoped audit reads.
class AuditContext {
  /// Construct an audit context.
  const AuditContext({
    required this.credential,
    required this.apiEndpoint,
    required this.organizationId,
    required this.organizationSlug,
  });

  /// Authenticated credential.
  final Credential credential;

  /// Backend endpoint that may receive [credential].
  final Uri apiEndpoint;

  /// Selected backend organization id.
  final int organizationId;

  /// Selected organization slug.
  final String organizationSlug;
}

/// Add the shared audit context options to [parser].
void addAuditContextOptions(ArgParser parser) {
  parser.addOption(
    'directory',
    abbr: 'C',
    defaultsTo: '.',
    help:
        'Directory to start the restage_config.yaml search from. '
        'Defaults to the current working directory.',
  );
}

/// Resolve credential, endpoint, and selected organization.
Future<AuditContext?> loadAuditContext({
  required ArgResults? argResults,
  required StringSink stderr,
  FileCredentialStore? credentialStore,
  http.Client? httpClient,
}) async {
  final store = credentialStore ?? FileCredentialStore.atDefaultLocation();
  final credential = await store.read();
  if (credential == null) {
    stderr.writeln('Not signed in. Run `restage login`.');
    return null;
  }

  final loaded = await loadRestageConfig(
    from: Directory(argResults?['directory'] as String? ?? '.'),
  );

  final Uri apiEndpoint;
  try {
    apiEndpoint = resolveApiEndpoint(
      config: loaded?.config,
      credential: credential,
    );
  } on EndpointConfigurationException catch (e) {
    stderr.writeln(e.toString());
    return null;
  }

  final RestageApi api;
  try {
    api = RestageApi(
      endpoint: apiEndpoint,
      httpClient: httpClient,
      credential: credential,
    );
  } on InsecureEndpointException catch (e) {
    stderr.writeln(e.toString());
    return null;
  }

  try {
    final organization = await _resolveAuditOrganization(
      api: api,
      config: loaded?.config,
      stderr: stderr,
    );
    if (organization == null) return null;
    return AuditContext(
      credential: credential,
      apiEndpoint: apiEndpoint,
      organizationId: organization.organizationId,
      organizationSlug: organization.slug,
    );
  } finally {
    if (httpClient == null) api.close();
  }
}

Future<_AuditOrganization?> _resolveAuditOrganization({
  required RestageApi api,
  required RestageConfig? config,
  required StringSink stderr,
}) async {
  final configuredSlug = config?.organization?.trim();
  if (configuredSlug != null && configuredSlug.isNotEmpty) {
    final resolved = await resolveConfiguredOrganization(
      api: api,
      config: config,
      stderr: stderr,
    );
    if (resolved?.organizationId == null) return null;
    return _AuditOrganization(
      organizationId: resolved!.organizationId!,
      slug: configuredSlug,
    );
  }

  try {
    final organizations = await DiscoveryApi(api).listOrganizations();
    if (organizations.isEmpty) {
      stderr.writeln('No organizations found for this account.');
      return null;
    }
    if (organizations.length > 1) {
      stderr.writeln(
        'No organization context. Set `organization` in restage_config.yaml.',
      );
      return null;
    }
    final organization = organizations.single;
    return _AuditOrganization(
      organizationId: organization.organizationId,
      slug: organization.slug,
    );
  } on RestageApiException catch (e) {
    final outcome = renderGenericTypedError(e);
    if (outcome != null) {
      stderr.writeln(outcome.message);
    } else {
      stderr.writeln('Could not discover organization context: ${e.body}');
    }
    return null;
  } on SocketException catch (e) {
    stderr.writeln('Could not contact the backend: $e');
    return null;
  }
}

class _AuditOrganization {
  const _AuditOrganization({required this.organizationId, required this.slug});

  final int organizationId;
  final String slug;
}
