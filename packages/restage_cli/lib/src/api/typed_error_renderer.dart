import 'package:restage_cli/src/config/config_target_check.dart'
    show noOrganizationSentence;
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/api/surface_routing_api.dart';
import 'package:restage_cli/src/delivery/fit_report.dart'
    show outsideLayoutSentence;
import 'package:restage_cli/src/api/typed_error_models.dart';
import 'package:restage_shared/restage_shared.dart'
    show SurfaceFitFailureCodeV1;

/// The exit code and stderr message for a backend refusal.
class TypedErrorOutcome {
  /// Construct an outcome with the matching exit code + message.
  const TypedErrorOutcome(this.exitCode, this.message);

  /// Exit code the caller should return.
  final int exitCode;

  /// Human-readable message to write to stderr.
  final String message;
}

/// The one rendering of a [RestageApiException], worded for [syntax].
///
/// A typed refusal reads as its sentence (exit 1); an untyped 401/403 as a
/// stale credential (exit 1); anything else as an HTTP failure (exit 2).
TypedErrorOutcome renderApiError(
  RestageApiException e, {
  SelectorSyntax? syntax,
}) {
  syntax ??= currentSelectorSyntax;
  String? typed;
  try {
    typed = typedErrorSentence(e.body, syntax: syntax);
  } on Object {
    typed = null;
  }
  if (typed != null) return TypedErrorOutcome(1, typed);
  if (e.statusCode == 401 || e.statusCode == 403) {
    return TypedErrorOutcome(1, staleCredentialSentence(syntax));
  }
  return TypedErrorOutcome(2, switch (syntax) {
    SelectorSyntax.cli || SelectorSyntax.console =>
      'The Restage backend returned an error (HTTP ${e.statusCode}). Try '
          'again; if it keeps happening, report it.',
    SelectorSyntax.mcp =>
      'The Restage backend returned an error (status ${e.statusCode}).',
  });
}

/// The one sentence for a typed backend refusal in [body], worded for
/// [syntax], or null when the body carries no typed payload. The CLI and the
/// MCP server share it.
String? typedErrorSentence(String body, {SelectorSyntax? syntax}) {
  syntax ??= currentSelectorSyntax;
  final generic = decodeGenericTypedException(body);
  if (generic != null) return _genericSentence(generic, syntax);
  final surface = decodeSurfaceTypedException(body);
  if (surface case SurfaceFamilyRefused(
    :final message,
    :final unhandledEvents,
  ) when unhandledEvents.isNotEmpty) {
    return [
      message,
      for (final gap in unhandledEvents)
        '  Flow "${gap.flow}", state "${gap.state}", screen "${gap.screen}", '
            'event "${gap.event}"',
      switch (syntax) {
        SelectorSyntax.cli || SelectorSyntax.console =>
          'Run again with --accept-unhandled-events to push it anyway.',
        SelectorSyntax.mcp =>
          'Call again with acceptUnhandledEvents: true to push it anyway.',
      },
    ].join('\n');
  }
  if (surface != null) return renderSurfaceException(surface);
  final routing = decodeSurfaceRoutingException(body);
  if (routing case SurfaceRoutingRejected(:final reason)) {
    return 'The delivery service refused the request: $reason.';
  }
  return null;
}

/// Return a user-facing error message for a typed [SurfaceException].
String renderSurfaceException(SurfaceException e) => switch (e) {
  SurfaceNotFound(:final surfaceSlug) => "Surface '$surfaceSlug' not found.",
  SurfacePublishConflict(:final surfaceSlug, :final environmentSlug) =>
    "Concurrent push conflict for '$surfaceSlug' in '$environmentSlug'. "
        'Retry the operation.',
  SurfaceVersionNotFound(:final surfaceSlug, :final toVersion) =>
    "Version v$toVersion not found for '$surfaceSlug'.",
  SurfaceFamilyRefused(:final message) => message,
  SurfaceArchived(:final surfaceSlug) =>
    "'$surfaceSlug' is archived. Restore it first.",
  SurfaceNotArchived(:final surfaceSlug) =>
    "Archive '$surfaceSlug' before deleting it for good.",
  SurfaceVersionLabelRejected(:final message) => message,
  final SurfaceDeleteRefused refused => surfaceDeleteRefusedSentence(refused),
};

/// The refusal of a delete for good: its title, then one line per blocker.
String surfaceDeleteRefusedSentence(SurfaceDeleteRefused refused) => [
  'Surface not deleted',
  for (final blocker in refused.blockers)
    '  ${switch (blocker.kind) {
      SurfaceDeleteBlockerKind.runningExperiment => 'Running experiment ${blocker.experimentName ?? ''}'.trimRight(),
      SurfaceDeleteBlockerKind.deliveryRule => 'Delivery rule in ${blocker.environmentSlug ?? ''}'.trimRight(),
      SurfaceDeleteBlockerKind.recentRequests => ['${blocker.requestCount ?? 0} requests in the last 30 days', if (blocker.lastRequestAt case final last?) '(last at ${_utcMinute(last)})'].join(' '),
    }}',
].join('\n');

String _utcMinute(DateTime at) {
  final utc = at.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${utc.year}-${two(utc.month)}-${two(utc.day)} '
      '${two(utc.hour)}:${two(utc.minute)} UTC';
}

/// The sentence for an organization [name] (a config slug, or an id the
/// request sent) that the account cannot reach.
String organizationUnavailableSentence(String? name, SelectorSyntax syntax) {
  final subject = name == null || name.isEmpty
      ? 'No organization is'
      : 'No organization `$name` is';
  return switch (syntax) {
    SelectorSyntax.mcp =>
      '$subject available to this account. Check `organizationId`, or sign in '
          'again with `restage_login`.',
    _ =>
      '$subject available to this account. Check `org` in your Restage '
          'config, or run `restage login` with an account that belongs to it.',
  };
}

/// The sentence for an app slug with no app under [projectSlug].
String appNotFoundSentence(String appSlug, String projectSlug) =>
    'App `$appSlug` not found under project `$projectSlug`.';

/// The sentence for a credential the server no longer accepts.
String staleCredentialSentence(SelectorSyntax syntax) =>
    'The stored credential is no longer accepted by the server. '
    '${syntax.signIn}';

String _genericSentence(
  GenericTypedException typed,
  SelectorSyntax syntax,
) => switch (typed) {
  OrganizationNotFound(:final organizationId) =>
    organizationUnavailableSentence('$organizationId', syntax),
  ProjectNotFound(:final projectSlug) =>
    'Project `$projectSlug` not found or you do not have access to it.',
  AppNotFound(:final appSlug, :final projectSlug) => appNotFoundSentence(
    appSlug,
    projectSlug,
  ),
  SurfaceSlugRejected(:final slug, :final reason) =>
    'Refusing the id `$slug`. $reason',
  MeasurementReadRejected(:final detail) => 'The read was refused. $detail',
  final AppDeleteRefused refused => appDeleteRefusedSentence(refused),
  AppDeleteNameMismatch(:final appName) => switch (syntax) {
    SelectorSyntax.mcp => "The name doesn't match the app's name, $appName.",
    _ => "--name doesn't match the app's name, $appName.",
  },
  UnauthorizedAccess(:final reason) => unauthorizedSentence(reason, syntax),
  final TargetSelectionRefused refused => targetSelectionSentence(
    refused,
    syntax,
  ),
  final SurfaceFitNeedsConfirmation needs => [
    fitConfirmationSentence(needs),
    switch (syntax) {
      SelectorSyntax.cli || SelectorSyntax.console => 'Use --yes to go ahead.',
      SelectorSyntax.mcp => 'Call again with acceptFit: true to go ahead.',
    },
  ].join('\n'),
};

/// The refusal of an app delete: its title, then one line per hold.
String appDeleteRefusedSentence(AppDeleteRefused refused) => [
  '${refused.appName} is still in use',
  for (final (:kind, :count) in refused.holds)
    '  ${appDeleteHoldLine(kind, count, projectName: refused.projectName)}',
].join('\n');

/// One hold of an app delete, such as "2 surfaces serving".
String appDeleteHoldLine(
  AppDeleteHoldKind kind,
  int count, {
  required String projectName,
}) => switch (kind) {
  AppDeleteHoldKind.servingSurface =>
    count == 1 ? '1 surface serving' : '$count surfaces serving',
  AppDeleteHoldKind.activeApiKey =>
    count == 1 ? '1 active API key' : '$count active API keys',
  AppDeleteHoldKind.runningExperiment =>
    count == 1 ? '1 running experiment' : '$count running experiments',
  AppDeleteHoldKind.deliveryRule =>
    count == 1 ? '1 delivery rule' : '$count delivery rules',
  AppDeleteHoldKind.lastAppInProject => 'The only app in $projectName',
};

/// Names why the server refused a signed-in caller.
String unauthorizedSentence(
  UnauthorizedReason reason, [
  SelectorSyntax? syntax,
]) => switch (reason) {
  UnauthorizedReason.roleMissing =>
    'Your role in this organization does not allow this. Ask an '
        'organization admin.',
  UnauthorizedReason.liveChangesNotAllowed =>
    "This organization's plan does not allow changes to the live plane. "
        'Check Billing in the dashboard.',
  UnauthorizedReason.paidPlanRequired =>
    'This needs a paid plan. Check Billing in the dashboard.',
  UnauthorizedReason.customPlanRequired =>
    'SSO comes with the Custom plan. Talk to us about Custom: '
        'contact@restage.dev',
  UnauthorizedReason.notSignedIn => staleCredentialSentence(
    syntax ?? currentSelectorSyntax,
  ),
  UnauthorizedReason.credentialNotAllowed =>
    'This credential cannot do this. Sign in, or use a secret API key with '
        'the right scope.',
  UnauthorizedReason.sampleWorkspaceReadOnly =>
    'The demo workspace is read-only. Use your own organization to make '
        'changes.',
  UnauthorizedReason.membershipChanged =>
    'Your membership in this organization changed. Try again.',
};

/// Names why the server could not resolve the request's selectors.
String targetSelectionSentence(
  TargetSelectionRefused refused,
  SelectorSyntax syntax,
) {
  final environment = refused.environmentSlug;
  final named = environment == null || environment.isEmpty
      ? 'the environment'
      : "environment '$environment'";
  return switch (refused.reason) {
    TargetSelectionRefusal.environmentNotFound =>
      environment == null || environment.isEmpty
          ? 'No environment target matches the request.'
          : "Environment '$environment' not found.",
    TargetSelectionRefusal.environmentOnBothPlanes =>
      "Environment '${environment ?? ''}' exists on both runtime planes. "
          'Pass ${syntax.plane}.',
    TargetSelectionRefusal.noTargetOnPlane =>
      'No target found for $named on that runtime plane.',
    TargetSelectionRefusal.noOrganization => noOrganizationSentence(),
    TargetSelectionRefusal.multipleOrganizations =>
      'This project is in more than one of your organizations'
          '${refused.organizationSlugs.isEmpty ? '' : ' (${refused.organizationSlugs.join(', ')})'}. '
          'Pass ${syntax.organization}.',
    TargetSelectionRefusal.organizationNotFound =>
      'No organization of yours matches ${syntax.organization}.',
    TargetSelectionRefusal.keyTargetMismatch =>
      'The API key belongs to a different app or environment than the one '
          'named.',
  };
}

/// The share as a whole percent: "0%" for none, "<1%" under a half percent,
/// and never "100%" while some build cannot show the version.
String fitSharePercent(double share) {
  if (share <= 0) return '0%';
  if (share < 0.005) return '<1%';
  final percent = (share * 100).round();
  return '${percent > 99 ? 99 : percent}%';
}

/// The title, body and one row per build that cannot show the version.
String fitConfirmationSentence(SurfaceFitNeedsConfirmation needs) => [
  if (needs.noneFit)
    'No app version in use can show this yet.'
  else
    'Not every app version can show this.',
  if (!needs.noneFit && needs.share != null)
    '${fitSharePercent(needs.share!)} of users are on versions that can.',
  for (final build in needs.builds)
    if (!build.fits) ...[
      '  ${fitBuildRow(build)}',
      for (final reason in build.reasons) '    ${fitReasonSentence(reason)}',
    ],
].join('\n');

/// Why one build can't show the version; [build] names that build, as in
/// "an installed build" where a report can't say which one.
String fitReasonSentence(FitReason reason, {String build = 'this build'}) {
  final theBuild = '${build[0].toUpperCase()}${build.substring(1)}';
  final label = reason.label;
  final named = label == null ? '' : ' `$label`';
  return switch (SurfaceFitFailureCodeV1.values.asNameMap()[reason.code]) {
    SurfaceFitFailureCodeV1.unproducedHostField ||
    SurfaceFitFailureCodeV1.unproducedIsland => outsideLayoutSentence(
      island: reason.code == 'unproducedIsland',
      label: label,
      build: reason.build,
      condition: reason.condition,
      location: reason.location,
    ),
    SurfaceFitFailureCodeV1.hostingMismatch => switch (label) {
      'flow' || 'single' =>
        'This version is ${label == 'flow' ? 'a flow' : 'one screen'}, '
            "and this placement doesn't show "
            "${label == 'flow' ? 'flows' : 'single screens'}. Try publishing "
            'it to a placement that does.',
      final String mode =>
        'This version can be shown only ${switch (mode) {
              'inline' => 'inside a screen of the app',
              'presented' => 'on a route of its own',
              _ => mode,
            }}, and this placement doesn\'t show it that way. Try publishing it '
            'to a placement that does.',
      null =>
        "This placement shows content in a way this version doesn't allow. "
            'Try publishing it to a placement that shows it the same way.',
    },
    SurfaceFitFailureCodeV1.missingHostField
        when _appValueToken.hasMatch(reason.token ?? '') =>
      "This version reads$named, which $build doesn't compute. Try "
          'removing${named.isEmpty ? ' it' : named} from the version, or '
          'releasing an app build that computes it.',
    SurfaceFitFailureCodeV1.missingHostField =>
      "$theBuild doesn't pass$named to this placement. Try removing"
          "${named.isEmpty ? ' it' : named} from the version, or passing it "
          "in the placement's `context` in a new app build.",
    SurfaceFitFailureCodeV1.incompatibleHostField =>
      '$theBuild passes$named to this placement as a different type. Try '
          'reading it as the type $build passes.',
    SurfaceFitFailureCodeV1.unhandledEvent =>
      "This version sends the event$named, which $build doesn't handle "
          'here. Try removing it from the version, or handling it where a new '
          'app build shows this placement.',
    SurfaceFitFailureCodeV1.incompatibleEventShape =>
      "This version sends the event$named with values $build's handler "
          "doesn't take. Try sending the values the handler takes.",
    SurfaceFitFailureCodeV1.missingInstalledVocabulary =>
      "$theBuild doesn't report which widgets it includes. Try releasing an "
          'app build made with a current Restage SDK.',
    SurfaceFitFailureCodeV1.missingWidget =>
      "$theBuild doesn't include the widget$named. Try removing it from the "
          'version, or releasing an app build that includes it.',
    SurfaceFitFailureCodeV1.missingIcon =>
      "$theBuild doesn't include an icon the version uses. Try including the "
          'icon in the app and releasing a build, or use an icon the app '
          'includes.',
    SurfaceFitFailureCodeV1.builtInFloor =>
      "$theBuild's built-in widgets are older than the version needs. Try "
          'releasing an app build made with a newer Restage SDK.',
    SurfaceFitFailureCodeV1.missingLibrary =>
      "$theBuild doesn't include the widget library$named. Try removing its "
          'widgets from the version, or releasing an app build that includes '
          'it.',
    SurfaceFitFailureCodeV1.oldLibrary =>
      '$theBuild has an older version of the widget library$named. Try '
          'releasing an app build with the newer library.',
    SurfaceFitFailureCodeV1.brokenLibrary =>
      'The widget library$named changed in $build in a way the version '
          "can't use. Try republishing the version with $build's library.",
    SurfaceFitFailureCodeV1.deliveryModeMismatch =>
      '$theBuild hosts a different kind of flow here. Try publishing a flow '
          'of the kind this placement hosts.',
    SurfaceFitFailureCodeV1.actionMismatch =>
      "$theBuild doesn't provide the action$named here, or provides it with "
          'different values. Try using the action as $build declares it.',
    SurfaceFitFailureCodeV1.seedMismatch =>
      "$theBuild can start the flow with$named, which the version doesn't "
          'accept. Try accepting${named.isEmpty ? ' it' : named} in the flow.',
    SurfaceFitFailureCodeV1.signalMismatch =>
      'The version fires the signal$named, which $build has no handler '
          'for. Try removing it from the version, or handling it in a new app '
          'build.',
    SurfaceFitFailureCodeV1.resultMismatch =>
      '$theBuild expects a different result from the flow. Try returning '
          'the result the app expects.',
    SurfaceFitFailureCodeV1.outboundMismatch =>
      "$theBuild doesn't accept$named from the version. Try sending only "
          'the values the app accepts.',
    SurfaceFitFailureCodeV1.missingIsland =>
      "$theBuild doesn't include the app code of$named. Try removing it "
          'from the version, or releasing an app build that includes it.',
    SurfaceFitFailureCodeV1.changedIsland =>
      '$theBuild changed the app code of$named. Try republishing the '
          'version to show it on $build.',
    SurfaceFitFailureCodeV1.missingRequirement =>
      "The version didn't record what it needs. Try republishing it.",
    SurfaceFitFailureCodeV1.malformedRequirement =>
      "What the version needs couldn't be read. Try republishing it.",
    null =>
      "$theBuild can't show the version for a reason this `restage` CLI "
          "doesn't know. Try updating the `restage` CLI.",
  };
}

// A value the app's generated widget computes, named at the end of a token.
final _appValueToken = RegExp(r'^missingHostField:(.*\.)?_h[0-9a-f]{10}$');

/// One build as a row: "ios 2.3.0", or "Uploaded build" for an uploaded one.
String fitBuildRow(FitBuild build) {
  if (build.uploaded) return 'Uploaded build';
  final label =
      build.appVersion ??
      (build.appBuildOrdinal == null ? null : 'build ${build.appBuildOrdinal}');
  return [?build.platform, ?label].join(' ');
}
