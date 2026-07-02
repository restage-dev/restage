import 'dart:io';

import 'package:restage_cli/src/api/discovery_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/config/restage_config.dart';

/// Resolved organization id for commands scoped by project/app slugs.
class ConfiguredOrganizationContext {
  /// Construct a resolved organization context.
  const ConfiguredOrganizationContext(this.organizationId);

  /// Backend organization id, or null when no organization was configured.
  final int? organizationId;
}

/// Resolve `restage_config.yaml`'s organization slug to the backend id.
///
/// Project/app commands can omit this when there is no configured organization;
/// the backend then resolves within the caller's memberships and fails closed on
/// ambiguous project slugs. When a config names an organization, resolve it
/// through the authenticated discovery RPC and thread the id into the scoped
/// operation so day-2 zero-flag commands work for multi-organization accounts.
Future<ConfiguredOrganizationContext?> resolveConfiguredOrganization({
  required RestageApi api,
  required RestageConfig? config,
  required StringSink stderr,
}) async {
  final organizationSlug = config?.organization;
  if (organizationSlug == null || organizationSlug.isEmpty) {
    return const ConfiguredOrganizationContext(null);
  }

  try {
    final organizations = await DiscoveryApi(api).listOrganizations();
    for (final organization in organizations) {
      if (organization.slug == organizationSlug) {
        return ConfiguredOrganizationContext(organization.organizationId);
      }
    }
    stderr.writeln(
      'No organization found for restage_config.yaml organization: '
      '$organizationSlug.',
    );
    return null;
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
