import 'dart:io';

import 'package:args/args.dart';
import 'package:restage_cli/src/api/discovery_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/config/config_target_check.dart';
import 'package:restage_cli/src/config/restage_config.dart';

/// Resolved organization id for commands scoped by project/app slugs.
class ConfiguredOrganizationContext {
  /// Construct a resolved organization context.
  const ConfiguredOrganizationContext(this.organizationId);

  /// Backend organization id, or null when no organization was configured.
  final int? organizationId;
}

/// Register the hidden `--organization-id` selector a tool that already
/// knows the organization id passes.
void addOrganizationIdOption(ArgParser parser) => parser.addOption(
  'organization-id',
  hide: true,
  callback: (value) {
    if (value != null && (int.tryParse(value) ?? 0) < 1) {
      throw ArgParserException('--organization-id must be a positive integer.');
    }
  },
);

/// The organization id `--organization-id` names, if any.
int? organizationIdOption(ArgResults? argResults) {
  if (argResults == null || !argResults.options.contains('organization-id')) {
    return null;
  }
  return int.tryParse(argResults['organization-id'] as String? ?? '');
}

/// An explicit organization selector takes precedence over configured scope.
String? resolveOrganizationSlug(ArgResults? argResults, RestageConfig? config) {
  if (argResults?.options.contains('organization') ?? false) {
    return argResults!['organization'] as String?;
  }
  return organizationIdOption(argResults) == null ? config?.organization : null;
}

void _writeOrganizationDiscoveryError(
  StringSink stderr,
  RestageApiException error,
) => stderr.writeln(renderApiError(error).message);

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
  String? preferredSlug,
  int? organizationId,
}) async {
  if (organizationId != null && !(preferredSlug?.isNotEmpty ?? false)) {
    return ConfiguredOrganizationContext(organizationId);
  }
  final organizationSlug = preferredSlug?.isNotEmpty ?? false
      ? preferredSlug
      : config?.organization;
  if (organizationSlug == null || organizationSlug.isEmpty) {
    return const ConfiguredOrganizationContext(null);
  }

  try {
    final organizations = await DiscoveryApi(api).listOrganizations();
    for (final organization in organizations) {
      if (organization.slug == organizationSlug &&
          (organizationId == null ||
              organization.organizationId == organizationId)) {
        return ConfiguredOrganizationContext(organization.organizationId);
      }
    }
    stderr.writeln('No organization found for `$organizationSlug`.');
    return null;
  } on RestageApiException catch (e) {
    _writeOrganizationDiscoveryError(stderr, e);
    return null;
  } on SocketException catch (e) {
    stderr.writeln(backendUnreachableMessage(api.endpoint, e));
    return null;
  }
}

/// Resolve the exact organization id required by target-aware operations.
///
/// A configured organization is authoritative. Without one, a sole membership
/// is safe to select automatically; multiple memberships fail closed and ask
/// the caller to persist an explicit organization in `restage_config.yaml`.
Future<int?> resolveRequiredOrganizationId({
  required RestageApi api,
  required RestageConfig? config,
  required StringSink stderr,
  String? preferredSlug,
}) async {
  final configured = await resolveConfiguredOrganization(
    api: api,
    config: config,
    stderr: stderr,
    preferredSlug: preferredSlug,
  );
  if (configured == null) return null;
  if (configured.organizationId case final organizationId?) {
    return organizationId;
  }

  try {
    final organizations = await DiscoveryApi(api).listOrganizations();
    if (organizations.isEmpty) {
      stderr.writeln(noOrganizationSentence);
      return null;
    }
    if (organizations.length != 1) {
      stderr.writeln(ambiguousOrganizationSentence(organizations));
      return null;
    }
    return organizations.single.organizationId;
  } on RestageApiException catch (e) {
    _writeOrganizationDiscoveryError(stderr, e);
    return null;
  } on SocketException catch (e) {
    stderr.writeln(backendUnreachableMessage(api.endpoint, e));
    return null;
  }
}
