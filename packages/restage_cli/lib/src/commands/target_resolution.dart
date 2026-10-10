import 'package:args/args.dart';
import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/discovery_api.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/api/typed_error_models.dart';
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

/// The plane argument a follow-up needs, or none when [implicit].
List<FollowUpArg> planeArgs(RuntimePlane plane, {required bool implicit}) => [
  if (!implicit) FollowUpArg('runtimePlane', plane.wireName, flag: 'plane'),
];

/// Resolve selectors to one exact target on the server.
///
/// Refusals surface as [RestageApiException] carrying the typed refusal.
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
  final selection = await DiscoveryApi(api).resolveTarget(
    projectSlug: projectSlug,
    appSlug: appSlug,
    environmentSlug: environmentSlug,
    runtimePlane: runtimePlane,
    environmentTargetId: environmentTargetId,
    organizationId: organizationId,
    organizationSlug: organizationSlug,
  );
  return ResolvedEnvironmentTargetContext(
    projectSlug: selection.projectSlug,
    appSlug: selection.appSlug,
    organizationId: selection.organizationId,
    organizationSlug: selection.organizationSlug,
    appId: selection.appId,
    target: selection.target!,
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
  RuntimePlane? runtimePlane,
  RuntimePlane? configuredPlane,
}) async {
  var plane = runtimePlane;
  var organization = organizationSlug;
  int? targetId;
  var chosePlane = false;
  while (true) {
    try {
      final resolved = await resolveTargetSelection(
        api: api,
        projectSlug: projectSlug,
        appSlug: appSlug,
        environmentSlug: environmentSlug,
        runtimePlane: plane,
        environmentTargetId: targetId,
        organizationId: organizationId,
        organizationSlug: organization,
      );
      final needsPlane =
          chosePlane ||
          (runtimePlane != null && runtimePlane != configuredPlane);
      return ResolvedEnvironmentTargetContext(
        projectSlug: resolved.projectSlug,
        appSlug: resolved.appSlug,
        organizationId: resolved.organizationId,
        organizationSlug: resolved.organizationSlug,
        appId: resolved.appId,
        target: resolved.target,
        planeIsImplicit: !needsPlane,
      );
    } on RestageApiException catch (e) {
      final refused = decodeGenericTypedException(e.body);
      if (!interactive.isInteractive || refused is! TargetSelectionRefused) {
        rethrow;
      }
      if (refused.reason == TargetSelectionRefusal.environmentOnBothPlanes &&
          refused.candidates.isNotEmpty &&
          !chosePlane) {
        final choice = await interactive.select<EnvironmentTargetSummary>(
          "Which '$environmentSlug' target?",
          [
            for (final candidate in refused.candidates)
              (
                label:
                    '${candidate.runtimePlane.wireName} '
                    '(target ${candidate.environmentTargetId})',
                value: candidate,
              ),
          ],
        );
        plane = choice.runtimePlane;
        targetId = choice.environmentTargetId;
        chosePlane = true;
        continue;
      }
      if (refused.reason == TargetSelectionRefusal.multipleOrganizations &&
          refused.organizationSlugs.isNotEmpty &&
          organization == null) {
        organization = await interactive.select<String>('Which organization?', [
          for (final slug in refused.organizationSlugs)
            (label: slug, value: slug),
        ]);
        continue;
      }
      rethrow;
    }
  }
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
