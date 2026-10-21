import 'package:path/path.dart' as p;
import 'package:restage_cli/src/receipts/release_receipt.dart';
import 'package:restage_shared/restage_shared.dart'
    show receiptPathSegment, receiptsDirectory;

export 'package:restage_shared/restage_shared.dart' show receiptsDirectory;

/// The directory holding every receipt for one app.
///
/// One repository can hold several apps, and several projects can address
/// one directory, so the project and the app come first: revisions are
/// counted per project, and two projects reach the same number.
String appReceiptDirectory({
  required String organization,
  required String project,
  required String app,
}) => p.posix.join(
  receiptsDirectory,
  receiptPathSegment(organization),
  receiptPathSegment(project),
  receiptPathSegment(app),
);

/// The directory holding every receipt for one surface in one environment.
///
/// The category is in the path because an id is unique only within one, and
/// the environment is below the id because revision numbers are counted per
/// environment.
String surfaceReceiptDirectory({
  required String organization,
  required String project,
  required String app,
  required String surfaceType,
  required String surfaceId,
  required String environment,
}) => p.posix.join(
  appReceiptDirectory(organization: organization, project: project, app: app),
  'surface',
  receiptPathSegment(surfaceType),
  receiptPathSegment(surfaceId),
  receiptPathSegment(environment),
);

/// Where the receipt for one pushed revision belongs.
///
/// A push stores a new revision every time, so this path is the operation.
String surfacePushReceiptPath({
  required String organization,
  required String project,
  required String app,
  required String surfaceType,
  required String surfaceId,
  required String environment,
  required int revision,
}) => p.posix.join(
  surfaceReceiptDirectory(
    organization: organization,
    project: project,
    app: app,
    surfaceType: surfaceType,
    surfaceId: surfaceId,
    environment: environment,
  ),
  'push-r$revision.json',
);

/// Where the receipt for one publication belongs.
///
/// One revision can be published more than once, so the instant is part of
/// the name and a listing reads as the publication history.
String surfacePublishReceiptPath({
  required String organization,
  required String project,
  required String app,
  required String surfaceType,
  required String surfaceId,
  required String environment,
  required int revision,
  required DateTime at,
}) => p.posix.join(
  surfaceReceiptDirectory(
    organization: organization,
    project: project,
    app: app,
    surfaceType: surfaceType,
    surfaceId: surfaceId,
    environment: environment,
  ),
  'publish-${_stamp(at)}-r$revision.json',
);

/// Where the receipt for one uploaded render bundle belongs.
String renderBundleReceiptPath({
  required String organization,
  required String project,
  required String app,
  required String head,
  required int version,
}) => p.posix.join(
  appReceiptDirectory(organization: organization, project: project, app: app),
  'bundle',
  receiptPathSegment(head),
  'v$version.json',
);

/// The timestamp as it appears in a receipt file name, to the millisecond.
String _stamp(DateTime at) {
  final utc = at.toUtc();
  final milliseconds = utc.millisecond.toString().padLeft(3, '0');
  final seconds = formatReceiptTimestamp(
    utc,
  ).replaceAll('-', '').replaceAll(':', '');
  return '${seconds.substring(0, seconds.length - 1)}.${milliseconds}Z';
}
