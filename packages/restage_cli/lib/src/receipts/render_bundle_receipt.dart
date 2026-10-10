import 'package:restage_cli/src/receipts/receipt_location.dart';
import 'package:restage_cli/src/receipts/release_receipt.dart';
import 'package:restage_cli/src/receipts/release_recorder.dart';

/// Writes and commits a receipt after a successful bundle push.
/// [head] identifies the target; [environment] names an environment head.
/// [dirty] marks the commit as context for an uncommitted build.
/// Returns false if the receipt is pending or cannot be written.
Future<bool> recordRenderBundlePush({
  required ReleaseRecorder recorder,
  required String organization,
  required int organizationId,
  required String project,
  required String app,
  required String head,
  required int version,
  required String contentHash,
  required String engineSetId,
  required bool dirty,
  required StringSink stdout,
  required StringSink stderr,
  String? environment,
  String? toolchain,
}) async {
  // Checked here so a value the receipt cannot carry is reported rather than
  // written and then unreadable on the next push.
  if (!isReceiptContentHash(contentHash)) {
    stderr.writeln(
      'The bundle content hash "$contentHash" is not a hash, so '
      'the push was not recorded.',
    );
    return false;
  }
  if (!isEngineSetIdentity(engineSetId)) {
    stderr.writeln(
      'The engine set identity "$engineSetId" is not a digest, '
      'so the push was not recorded.',
    );
    return false;
  }
  final receipt = ReleaseReceipt(
    operation: ReceiptOperation.renderBundlePush,
    recordedAt: DateTime.now(),
    target: ReceiptTarget(
      organization: organization,
      organizationId: organizationId,
      project: project,
      app: app,
      environment: environment,
    ),
    bundle: ReceiptBundle(
      head: head,
      version: version,
      contentHash: contentHash,
      engineSetId: engineSetId,
      toolchain: toolchain,
    ),
    source: ReceiptSource(
      state: dirty ? ReceiptSourceState.dirty : ReceiptSourceState.verified,
      commit: recorder.head.commit,
      branch: recorder.head.branch,
    ),
  );
  final written = await recorder.write(
    receipt: receipt,
    relativePath: renderBundleReceiptPath(
      organization: organization,
      project: project,
      app: app,
      head: head,
      version: version,
    ),
    stdout: stdout,
    stderr: stderr,
  );
  final committed = await recorder.commit(
    message: 'restage: push bundle v$version to $head',
    stdout: stdout,
    stderr: stderr,
  );
  return written && committed;
}
