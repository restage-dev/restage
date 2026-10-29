import 'dart:io';

import 'package:args/args.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/scope_snapshot_api.dart';
import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/api/typed_error_models.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/config/config_target_check.dart'
    show ambiguousOrganizationSentence, noOrganizationSentence;
import 'package:restage_cli/src/config/restage_config.dart';

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

/// The organization id for [preferredSlug], else the config's organization,
/// else [organizationId]; null when none is named.
///
/// Resolves through [readConfiguredScope], so a slug the account cannot reach
/// raises the one [TargetSelectionException] sentence.
Future<int?> resolveOrganizationId({
  required RestageApi api,
  required LoadedConfig? loaded,
  String? preferredSlug,
  int? organizationId,
  StringSink? notices,
}) async {
  final slug = preferredSlug?.isNotEmpty ?? false
      ? preferredSlug
      : loaded?.config.organization;
  if (slug == null || slug.isEmpty) return organizationId;
  if (organizationId != null && !(preferredSlug?.isNotEmpty ?? false)) {
    return organizationId;
  }
  final snapshot = await readConfiguredScope(
    api,
    loaded: loaded,
    organizationSlug: slug,
    notices: notices,
  );
  if (organizationId != null && snapshot.organizationId != organizationId) {
    throw TargetSelectionException(
      organizationUnavailableSentence(slug, currentSelectorSyntax),
    );
  }
  return snapshot.organizationId;
}

/// The loaded project config: its values and the file they came from.
typedef LoadedConfig = ({RestageConfig config, File source});

/// Read the scope for the organization [organizationSlug] names in [loaded].
///
/// Sends the id the config cached. When the server refuses it, resolves the
/// slug once, rewrites the cached id in the config file, and continues; only a
/// slug the account cannot reach raises the error that prints the sentence.
/// A failed rewrite is reported on [notices] and does not stop the command.
Future<ProgrammaticScopeSnapshot> readConfiguredScope(
  RestageApi api, {
  required LoadedConfig? loaded,
  required String? organizationSlug,
  StringSink? notices,
}) async {
  final config = loaded?.config;
  final cached = config != null && config.organization == organizationSlug
      ? config.organizationId
      : null;
  var snapshot = await _readCached(api, cached);
  final refused = snapshot == null;
  snapshot ??= await readProgrammaticScope(api);
  if (organizationSlug == null) return snapshot;
  final match = snapshot.organizations
      .where((organization) => organization.slug == organizationSlug)
      .firstOrNull;
  if (match == null) {
    throw TargetSelectionException(
      organizationUnavailableSentence(organizationSlug, currentSelectorSyntax),
    );
  }
  if (match.organizationId != snapshot.organizationId) {
    snapshot = await readProgrammaticScope(
      api,
      organizationId: match.organizationId,
    );
  }
  if ((refused || (cached != null && cached != match.organizationId)) &&
      loaded != null) {
    try {
      await writeRestageConfig(
        loaded.source,
        loaded.config.withConfirmedOrganizationId(match.organizationId),
      );
    } on FileSystemException {
      notices?.writeln(
        "Couldn't save the organization id to restage_config.yaml. The next "
        'command looks it up again.',
      );
    }
  }
  return snapshot;
}

/// The scope for [cached], or null when the server refuses that id.
Future<ProgrammaticScopeSnapshot?> _readCached(
  RestageApi api,
  int? cached,
) async {
  try {
    return await readProgrammaticScope(api, organizationId: cached);
  } on RestageApiException catch (e) {
    final refused = decodeGenericTypedException(e.body);
    if (cached != null &&
        refused is OrganizationNotFound &&
        refused.organizationId == cached) {
      return null;
    }
    rethrow;
  }
}

/// [resolveOrganizationId], or the caller's only organization when none is
/// named; several or none raise the sentence that says how to choose.
Future<int> resolveRequiredOrganizationId({
  required RestageApi api,
  required LoadedConfig? loaded,
  String? preferredSlug,
  int? organizationId,
  StringSink? notices,
}) async {
  final resolved = await resolveOrganizationId(
    api: api,
    loaded: loaded,
    preferredSlug: preferredSlug,
    organizationId: organizationId,
    notices: notices,
  );
  if (resolved != null) return resolved;
  final organizations = (await readProgrammaticScope(api)).organizations;
  if (organizations.length == 1) return organizations.single.organizationId;
  throw TargetSelectionException(
    organizations.isEmpty
        ? noOrganizationSentence(api.endpoint)
        : ambiguousOrganizationSentence(organizations),
  );
}
