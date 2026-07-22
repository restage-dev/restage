import 'dart:io';

import 'package:args/args.dart';
import 'package:restage_cli/src/api/discovery_api.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/discovery/context_discovery.dart';
import 'package:restage_cli/src/io/interactive.dart';

/// Runtime-plane values accepted by command-line selectors.
const runtimePlaneWireNames = <String>['sandbox', 'live'];

/// Add the optional runtime-plane selector shared by target-aware commands.
void addRuntimePlaneOption(ArgParser parser) {
  parser.addOption(
    'plane',
    allowed: runtimePlaneWireNames,
    help: 'Runtime plane: sandbox or live.',
  );
}

/// Parse an optional runtime-plane command-line value.
RuntimePlane? runtimePlaneFromArgs(ArgResults? argResults) {
  final value = argResults?['plane'] as String?;
  return value == null ? null : RuntimePlane.fromWireName(value);
}

/// Fully resolved organization and environment target for an operation.
class ResolvedEnvironmentTargetContext {
  /// Construct a resolved target context.
  const ResolvedEnvironmentTargetContext({
    required this.organizationId,
    required this.appId,
    required this.target,
  });

  /// Authorized organization id.
  final int organizationId;

  /// Active numeric App authority verified during discovery.
  final int appId;

  /// Exact target selected for the operation.
  final EnvironmentTargetSummary target;
}

/// Resolves one active App slug to its stable numeric id.
///
/// Target-aware callers fail closed when an older server omits the additive id
/// or when the slug is ambiguous; neither condition may fall back to slug-only
/// target discovery.
Future<int?> resolveActiveAppId({
  required DiscoveryApi discovery,
  required StringSink stderr,
  required int organizationId,
  required String projectSlug,
  required String appSlug,
}) async {
  final apps = await discovery.listApps(
    organizationId: organizationId,
    projectSlug: projectSlug,
  );
  final matchingApps = [
    for (final app in apps)
      if (app.slug == appSlug) app,
  ];
  if (matchingApps.length != 1 || matchingApps.single.appId == null) {
    stderr.writeln("No active app found for '$projectSlug/$appSlug'.");
    return null;
  }
  return matchingApps.single.appId!;
}

/// Resolve one exact target before a target-scoped operation starts.
///
/// A single matching target preserves the behavior of configurations that
/// predate runtime-plane selection. When the same slug exists on both planes,
/// callers must pass `--plane` or choose interactively.
Future<ResolvedEnvironmentTargetContext?> resolveEnvironmentTargetContext({
  required RestageApi api,
  required Interactive interactive,
  required StringSink stderr,
  required String projectSlug,
  required String appSlug,
  required String environmentSlug,
  String? preferredOrganizationSlug,
  RuntimePlane? runtimePlane,
}) async {
  try {
    final discovery = DiscoveryApi(api);
    final organization = await resolveActiveOrganization(
      api: discovery,
      interactive: interactive,
      stderr: stderr,
      preferredSlug: preferredOrganizationSlug,
    );
    if (organization == null) return null;

    final appId = await resolveActiveAppId(
      discovery: discovery,
      stderr: stderr,
      organizationId: organization.organizationId,
      projectSlug: projectSlug,
      appSlug: appSlug,
    );
    if (appId == null) return null;

    final targets = await discovery.listEnvironmentTargets(
      organizationId: organization.organizationId,
      projectSlug: projectSlug,
      appSlug: appSlug,
      appId: appId,
      runtimePlane: runtimePlane,
    );
    final matches = [
      for (final target in targets)
        if (target.environmentSlug == environmentSlug) target,
    ];
    if (matches.isEmpty) {
      final planeSuffix = runtimePlane == null
          ? ''
          : ' on the ${runtimePlane.wireName} plane';
      stderr.writeln(
        "No target found for environment '$environmentSlug'$planeSuffix.",
      );
      return null;
    }

    final EnvironmentTargetSummary target;
    if (matches.length == 1) {
      target = matches.single;
    } else if (runtimePlane != null) {
      stderr.writeln(
        "Multiple ${runtimePlane.wireName} targets found for environment "
        "'$environmentSlug'.",
      );
      return null;
    } else if (!interactive.isInteractive) {
      stderr.writeln(
        "Environment '$environmentSlug' exists on multiple runtime planes. "
        'Pass --plane <sandbox|live>.',
      );
      return null;
    } else {
      target = await interactive.select<EnvironmentTargetSummary>(
        "Which '$environmentSlug' target?",
        [
          for (final match in matches)
            (
              label:
                  '${match.runtimePlane.wireName} '
                  '(target ${match.environmentTargetId})',
              value: match,
            ),
        ],
      );
    }

    return ResolvedEnvironmentTargetContext(
      organizationId: organization.organizationId,
      appId: appId,
      target: target,
    );
  } on RestageApiException catch (e) {
    final outcome = renderGenericTypedError(e);
    stderr.writeln(
      outcome?.message ?? 'Could not discover environment targets: ${e.body}',
    );
    return null;
  } on SocketException catch (e) {
    stderr.writeln('Could not contact the backend: $e');
    return null;
  }
}
