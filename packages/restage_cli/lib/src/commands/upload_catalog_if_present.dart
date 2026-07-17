import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_cli/src/api/catalog_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';

/// Upload the generated widget catalog when the project has one.
///
/// A missing catalog means there are no registered custom widgets to push and
/// is intentionally silent. Upload failures are warnings because the caller's
/// primary publish operation has already succeeded.
Future<void> uploadCatalogIfPresent({
  required RestageApi api,
  required String project,
  required String app,
  int? organizationId,
  required Directory projectRoot,
  required StringSink stderr,
}) async {
  final catalogFile = File(
    p.join(projectRoot.path, 'lib', 'src', 'widget_catalog', 'catalog.json'),
  );
  if (!catalogFile.existsSync()) return;

  try {
    await CatalogApi(api).push(
      project: project,
      app: app,
      catalogJson: await catalogFile.readAsString(),
      organizationId: organizationId,
    );
  } on RestageApiException catch (e) {
    final catalog = decodeCatalogTypedException(e.body);
    final message = catalog != null
        ? renderCatalogException(catalog)
        : renderGenericTypedError(e)?.message ?? e.toString();
    stderr.writeln('Warning: widget catalog upload failed: $message');
  } on Object catch (e) {
    stderr.writeln('Warning: could not upload the widget catalog: $e');
  }
}
