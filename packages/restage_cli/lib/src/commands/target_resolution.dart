import 'dart:io';

import 'package:args/args.dart';
import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/discovery_api.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/scope_snapshot_api.dart';
import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/config/restage_config.dart';
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

/// The plane `--plane` names, else the one restage_config.yaml sets.
RuntimePlane? resolveRuntimePlane(
  ArgResults? argResults,
  RestageConfig? config,
) {
  final value = argResults?['plane'] as String?;
  return value == null ? config?.plane : RuntimePlane.fromWireName(value);
}

/// Fully resolved organization and environment target for an operation.
class ResolvedEnvironmentTargetContext {
  /// Construct a resolved target context.
  const ResolvedEnvironmentTargetContext({
    required this.projectSlug,
    required this.appSlug,
    required this.organizationId,
    required this.organizationSlug,
    required this.appId,
    required this.target,
    this.planeIsImplicit = true,
  });

  /// Project slug.
  final String projectSlug;

  /// App slug.
  final String appSlug;

  /// Authorized organization id.
  final int organizationId;

  /// Slug of the organization [organizationId] names.
  final String organizationSlug;

  /// Active numeric App authority verified during discovery.
  final int appId;

  /// Exact target selected for the operation.
  final EnvironmentTargetSummary target;

  /// Whether a follow-up command reaches [target] without `--plane`.
  final bool planeIsImplicit;
}

/// Save IDs only when the resolved target confirms the configured selectors.
Future<void> persistConfirmedTargetIds({
  required File? configSource,
  required RestageConfig? config,
  required ResolvedEnvironmentTargetContext target,
}) async {
  if (configSource == null ||
      config == null ||
      config.project != target.projectSlug ||
      config.app != target.appSlug ||
      config.defaultEnvironment != target.target.environmentSlug ||
      (config.organization != null &&
          config.organization != target.organizationSlug) ||
      (config.plane != null && config.plane != target.target.runtimePlane)) {
    return;
  }
  final confirmed = config.withResolvedIds(
    organizationId: target.organizationId,
    appId: target.appId,
    environmentTargetId: target.target.environmentTargetId,
    namedEnvironmentId: target.target.namedEnvironmentId,
  );
  if (confirmed.toYaml() != config.toYaml()) {
    await writeRestageConfig(configSource, confirmed);
  }
}

/// The plane argument a follow-up needs, or none when [implicit].
List<FollowUpArg> planeArgs(RuntimePlane plane, {required bool implicit}) => [
  if (!implicit) FollowUpArg('runtimePlane', plane.wireName, flag: 'plane'),
];

/// Resolve selectors against one current, admitted scope snapshot.
@experimental
Future<ResolvedEnvironmentTargetContext> resolveTargetSelection({
  required RestageApi api,
  required String projectSlug,
  required String appSlug,
  required String environmentSlug,
  RuntimePlane? runtimePlane,
  int? environmentTargetId,
  int? organizationId,
  String? organizationSlug,
}) async {
  final snapshot = await readProgrammaticScope(
    api,
    organizationId: organizationId,
  );
  if (organizationId == null &&
      organizationSlug == null &&
      snapshot.organizations.length != 1) {
    throw const TargetSelectionException(
      'You belong to multiple organizations. Select one organization.',
    );
  }
  return _selectionInSnapshot(
    snapshot,
    projectSlug: projectSlug,
    appSlug: appSlug,
    environmentSlug: environmentSlug,
    runtimePlane: runtimePlane,
    environmentTargetId: environmentTargetId,
    organizationSlug: organizationSlug,
  );
}

ResolvedEnvironmentTargetContext _selectionInSnapshot(
  ProgrammaticScopeSnapshot snapshot, {
  required String projectSlug,
  required String appSlug,
  required String environmentSlug,
  RuntimePlane? runtimePlane,
  int? environmentTargetId,
  String? organizationSlug,
}) {
  final organization = snapshot.organizations
      .where((candidate) => candidate.organizationId == snapshot.organizationId)
      .firstOrNull;
  if (organization == null ||
      (organizationSlug != null && organization.slug != organizationSlug)) {
    throw const TargetSelectionException(
      'No organization matches those selectors.',
    );
  }
  if (!snapshot.projects.any((project) => project.slug == projectSlug)) {
    throw const TargetSelectionException('No project matches those selectors.');
  }
  final apps = snapshot
      .apps(projectSlug)
      .where((candidate) => candidate.slug == appSlug)
      .toList();
  if (apps.length != 1 || apps.single.appId == null) {
    throw const TargetSelectionException('No app matches those selectors.');
  }
  final candidates = snapshot
      .targets(
        projectSlug: projectSlug,
        appSlug: appSlug,
        runtimePlane: runtimePlane,
      )
      .where(
        (target) =>
            target.environmentSlug == environmentSlug &&
            (environmentTargetId == null ||
                target.environmentTargetId == environmentTargetId),
      )
      .toList();
  if (candidates.isEmpty) {
    throw const TargetSelectionException(
      'No environment target matches those selectors.',
    );
  }
  if (candidates.length != 1) {
    throw TargetSelectionException(
      "Environment '$environmentSlug' exists on both runtime planes. Pass "
      '${currentSelectorSyntax.plane}.',
    );
  }
  return ResolvedEnvironmentTargetContext(
    projectSlug: projectSlug,
    appSlug: appSlug,
    organizationId: organization.organizationId,
    organizationSlug: organization.slug,
    appId: apps.single.appId!,
    target: candidates.single,
  );
}

/// Resolve selectors to one exact target, asking which target or
/// organization the server found ambiguous when [interactive] can prompt.
///
/// [configuredPlane] is the config's plane, which decides whether follow-up
/// hints need `--plane`.
Future<ResolvedEnvironmentTargetContext> resolveTargetInteractively({
  required RestageApi api,
  required Interactive interactive,
  required String projectSlug,
  required String appSlug,
  required String environmentSlug,
  String? organizationSlug,
  int? organizationId,
  int? environmentTargetId,
  RuntimePlane? runtimePlane,
  RuntimePlane? configuredPlane,
}) async {
  var snapshot = await readProgrammaticScope(
    api,
    organizationId: organizationId,
  );
  if (organizationId == null &&
      organizationSlug == null &&
      snapshot.organizations.length > 1) {
    if (!interactive.isInteractive) {
      throw const TargetSelectionException(
        'You belong to multiple organizations. Select one organization.',
      );
    }
    final chosen = await interactive
        .select<OrganizationSummary>('Which organization?', [
          for (final organization in snapshot.organizations)
            (label: organization.slug, value: organization),
        ]);
    if (chosen.organizationId != snapshot.organizationId) {
      snapshot = await readProgrammaticScope(
        api,
        organizationId: chosen.organizationId,
      );
    }
  }
  if (organizationId == null && organizationSlug != null) {
    final matches = snapshot.organizations
        .where((organization) => organization.slug == organizationSlug)
        .toList();
    if (matches.length != 1) {
      throw const TargetSelectionException(
        'No organization matches those selectors.',
      );
    }
    if (matches.single.organizationId != snapshot.organizationId) {
      snapshot = await readProgrammaticScope(
        api,
        organizationId: matches.single.organizationId,
      );
    }
  }
  final choices = snapshot
      .targets(
        projectSlug: projectSlug,
        appSlug: appSlug,
        runtimePlane: runtimePlane,
      )
      .where(
        (target) =>
            target.environmentSlug == environmentSlug &&
            (environmentTargetId == null ||
                target.environmentTargetId == environmentTargetId),
      )
      .toList();
  final selected = choices.length > 1 && interactive.isInteractive
      ? await interactive.select<EnvironmentTargetSummary>(
          "Which '$environmentSlug' target?",
          [
            for (final candidate in choices)
              (
                label:
                    '${candidate.runtimePlane.wireName} '
                    '(target ${candidate.environmentTargetId})',
                value: candidate,
              ),
          ],
        )
      : null;
  final resolved = _selectionInSnapshot(
    snapshot,
    projectSlug: projectSlug,
    appSlug: appSlug,
    environmentSlug: environmentSlug,
    runtimePlane: selected?.runtimePlane ?? runtimePlane,
    environmentTargetId: selected?.environmentTargetId ?? environmentTargetId,
    organizationSlug: organizationSlug,
  );
  return ResolvedEnvironmentTargetContext(
    projectSlug: resolved.projectSlug,
    appSlug: resolved.appSlug,
    organizationId: resolved.organizationId,
    organizationSlug: resolved.organizationSlug,
    appId: resolved.appId,
    target: resolved.target,
    planeIsImplicit:
        selected == null &&
        (runtimePlane == null || runtimePlane == configuredPlane),
  );
}

/// The project slug [preferredSlug] names, else the one to pick. Null after
/// writing why to [stderr].
Future<String?> resolveProjectSlug({
  required DiscoveryApi discovery,
  required Interactive interactive,
  required StringSink stderr,
  required int organizationId,
  String? preferredSlug,
}) async {
  if (preferredSlug != null && preferredSlug.isNotEmpty) return preferredSlug;
  final project = await pickOne<ProjectSummary>(
    interactive: interactive,
    stderr: stderr,
    prompt: 'Which project?',
    options: [
      for (final project in await discovery.listProjects(organizationId))
        (label: '${project.name} (${project.slug})', value: project),
    ],
    missingFlag: '--project <slug>',
  );
  return project?.slug;
}

/// The app [preferredSlug] names under [projectSlug], else the one to pick.
/// Null after writing why to [stderr].
Future<AppSummary?> resolveApp({
  required DiscoveryApi discovery,
  required Interactive interactive,
  required StringSink stderr,
  required int organizationId,
  required String projectSlug,
  String? preferredSlug,
}) async {
  final apps = await discovery.listApps(
    organizationId: organizationId,
    projectSlug: projectSlug,
  );
  if (preferredSlug != null && preferredSlug.isNotEmpty) {
    for (final app in apps) {
      if (app.slug == preferredSlug) return app;
    }
    stderr.writeln('No option found for --app <slug>: $preferredSlug.');
    return null;
  }
  return pickOne<AppSummary>(
    interactive: interactive,
    stderr: stderr,
    prompt: 'Which app?',
    options: [
      for (final app in apps) (label: '${app.name} (${app.slug})', value: app),
    ],
    missingFlag: '--app <slug>',
  );
}
