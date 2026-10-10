import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/surface_api.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/commands/surface_identity.dart';
import 'package:restage_cli/src/commands/target_resolution.dart';
import 'package:restage_cli/src/receipts/receipt_location.dart';
import 'package:restage_cli/src/receipts/release_receipt.dart';
import 'package:restage_cli/src/receipts/release_recorder.dart';
import 'package:restage_shared/restage_shared.dart' show SurfaceSourceKind;
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show DeliveryMeasurementMutationProceedV1;

/// The audit reason recorded when the operator does not supply one.
const String kDefaultPublishReason = 'Published from the CLI';

/// Where a surface family operation runs.
typedef FamilyTarget = ({
  String project,
  String app,
  String environment,
  int? environmentTargetId,
  RuntimePlane? runtimePlane,
  int? organizationId,
});

/// The family operation target [resolved] names under [project] and [app].
FamilyTarget familyTargetOf(ResolvedEnvironmentTargetContext resolved) => (
  project: resolved.projectSlug,
  app: resolved.appSlug,
  environment: resolved.target.environmentSlug,
  environmentTargetId: resolved.target.environmentTargetId,
  runtimePlane: resolved.target.runtimePlane,
  organizationId: resolved.organizationId,
);

/// The history of the family the server resolves for [identity] at [at].
@experimental
Future<SurfaceContractFamilyHistoryResult> familyHistory({
  required SurfaceApi api,
  required SurfaceLifecycleIdentity identity,
  required FamilyTarget at,
}) => api.surfaceContractHistory(
  project: at.project,
  app: at.app,
  surfaceType: identity.surface,
  surfaceSlug: identity.slug,
  environment: at.environment,
  sourceKind: identity.sourceKind,
  contractVersion: identity.contractVersion,
  environmentTargetId: at.environmentTargetId,
  runtimePlane: at.runtimePlane,
  organizationId: at.organizationId,
);

/// One publication [publishSurface] made.
typedef SurfacePublication = ({
  SurfaceLifecycleIdentity family,
  int revision,
  bool latest,
  SurfaceFamilyMutationResult result,
});

/// Publish [revision], or the newest pushed one, of the family the server
/// resolves for [identity] at [at], then record it when [record] names a
/// recorder and the exact target the receipt carries.
///
/// [onPublished] runs before the receipt is written. Returns the publication
/// and, with a [recorder], whether its receipt landed.
@experimental
Future<({SurfacePublication publication, bool? recorded})> publishSurface({
  required SurfaceApi api,
  required SurfaceLifecycleIdentity identity,
  required FamilyTarget at,
  required String reason,
  int? revision,
  ({ReleaseRecorder recorder, ResolvedEnvironmentTargetContext target})? record,
  StringSink? stdout,
  StringSink? stderr,
  void Function(SurfacePublication publication)? onPublished,
  DeliveryMeasurementMutationProceedV1? measurementProceed,
}) async {
  final result = await api.activate(
    project: at.project,
    app: at.app,
    surfaceType: identity.surface,
    surfaceSlug: identity.slug,
    environment: at.environment,
    publishedRevision: revision,
    reason: reason,
    environmentTargetId: at.environmentTargetId,
    runtimePlane: at.runtimePlane,
    organizationId: at.organizationId,
    contractVersion: identity.contractVersion,
    sourceKind: identity.sourceKind,
    measurementProceed: measurementProceed,
  );
  final sourceKind = result.sourceKind;
  final family = sourceKind == null
      ? identity
      : identity.resolvedAs(
          sourceKind: SurfaceSourceKind.fromWireName(sourceKind),
          contractVersion: result.contractVersion,
        );
  final chosen = result.publishedRevision ?? revision!;
  final publication = (
    family: family,
    revision: chosen,
    latest: revision == null,
    result: result,
  );
  onPublished?.call(publication);
  if (record == null) return (publication: publication, recorded: null);
  final (:recorder, :target) = record;
  final recorded = await recordSurfacePublishReceipt(
    recorder: recorder,
    organizationSlug: target.organizationSlug,
    organizationId: target.organizationId,
    project: target.projectSlug,
    app: target.appSlug,
    environment: target.target.environmentSlug,
    environmentTargetId: target.target.environmentTargetId,
    runtimePlane: target.target.runtimePlane,
    identity: family,
    result: result,
    revision: chosen,
    stdout: stdout!,
    stderr: stderr!,
  );
  return (publication: publication, recorded: recorded);
}

/// How to show a published [kind] of surface in an app. [mountName] is the
/// generated widget the published version names, when it names one.
@experimental
String mountGuide(SurfaceSourceKind? kind, String slug, {String? mountName}) {
  const configure =
      "In the app, call Restage.configure(apiKey: 'rs_pk_...', baseUrl: ...) "
      'once with the key of this environment';
  const docs = 'https://docs.page/restage-dev/restage/delivery/hosted-delivery';
  return switch (kind) {
    SurfaceSourceKind.paywall =>
      '$configure, then mount the generated <Name>Surface() of the paywall '
          "class, or RestagePaywall(id: '$slug'). See $docs.",
    _ when mountName != null =>
      "In your app, call Restage.configure(apiKey: 'rs_pk_...', baseUrl: "
          "...) once with this environment's key, then add $mountName(...) "
          'where it should appear. New versions reach app builds made from '
          'the same surface code. Guide: $docs',
    _ =>
      '$configure, then mount the generated <Name>Surface() of the class '
          'that declares it. A screen or flow has no mount by id: it runs '
          'only in app builds that compile its generated mount, and a '
          'published version must match the contract that build carries. '
          'See $docs.',
  };
}

/// The line an app writes to show the surface [status] describes, or null
/// when its live version names no generated widget.
@experimental
String? mountLine(SurfaceStatusResult status) {
  if (status.sourceKind == SurfaceSourceKind.paywall.wireName) {
    return "RestagePaywall(id: '${status.surfaceSlug}')";
  }
  final name = status.versions
      .where((version) => version.isActive)
      .firstOrNull
      ?.mountName;
  return name == null ? null : '$name(...)';
}

/// Record a publication as a release receipt, linking it to the source of
/// [revision], and commit it.
///
/// Returns false when the server published and the receipt did not land.
@experimental
Future<bool> recordSurfacePublishReceipt({
  required ReleaseRecorder recorder,
  required String organizationSlug,
  required int organizationId,
  required String project,
  required String app,
  required String environment,
  required int environmentTargetId,
  required RuntimePlane runtimePlane,
  required SurfaceLifecycleIdentity identity,
  required SurfaceFamilyMutationResult result,
  required int revision,
  required StringSink stdout,
  required StringSink stderr,
}) async {
  final recordedAt = DateTime.now();
  final target = ReceiptTarget(
    organization: organizationSlug,
    organizationId: organizationId,
    project: project,
    app: app,
    environment: environment,
    environmentTargetId: environmentTargetId,
    runtimePlane: runtimePlane.wireName,
  );
  final surfaceType = result.surfaceType;
  final surfaceId = result.surfaceSlug;
  final source = await recorder.sourceOfPushedRevision(
    organization: organizationSlug,
    project: project,
    app: app,
    surfaceType: surfaceType,
    surfaceId: surfaceId,
    environment: environment,
    revision: revision,
  );
  if (source.state == ReceiptSourceState.unknown) {
    stdout.writeln(
      'Nothing here records where r$revision was built from, so the receipt '
      'says its source is unknown.',
    );
  }

  final written = await recorder.write(
    receipt: ReleaseReceipt(
      operation: ReceiptOperation.surfacePublish,
      recordedAt: recordedAt,
      target: target,
      surface: ReceiptSurface(
        type: surfaceType,
        id: surfaceId,
        sourceKind: result.sourceKind ?? identity.sourceKind!.wireName,
        contractVersion: result.contractVersion ?? identity.contractVersion,
      ),
      revision: ReceiptRevision(
        stored: revision,
        activeBefore: result.activeRevisionBefore,
        activeAfter: result.activeRevisionAfter,
        identityFrozen: result.frozen,
      ),
      source: source,
    ),
    relativePath: surfacePublishReceiptPath(
      organization: organizationSlug,
      project: project,
      app: app,
      surfaceType: surfaceType,
      surfaceId: surfaceId,
      environment: environment,
      revision: revision,
      at: recordedAt,
    ),
    stdout: stdout,
    stderr: stderr,
  );
  final committed = await recorder.commit(
    message: 'restage: publish $surfaceId r$revision to $environment',
    stdout: stdout,
    stderr: stderr,
  );
  return written && committed;
}
