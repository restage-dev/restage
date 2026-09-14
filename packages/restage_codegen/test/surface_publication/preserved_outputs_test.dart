import 'dart:io';

import 'package:build/build.dart';
import 'package:restage_codegen/src/surface_publication/output_placement.dart';
import 'package:restage_codegen/src/surface_publication/preserved_outputs.dart';
import 'package:test/test.dart';

void main() {
  for (final outputRoot in ['.restage/build', '.hidden/build/output']) {
    test('captures bundles from configured hidden root $outputRoot', () {
      final root = Directory.systemTemp.createTempSync('restage-preserved-');
      addTearDown(() => root.deleteSync(recursive: true));
      final plan = RestageOutputPlacementPlan.fromBuilderOptions(
        BuilderOptions({'output_root': outputRoot, 'inspection_report': true}),
      );
      final source = plan.forLibrary('lib/features/screen.dart');
      final paths = [
        source.neutralPartPath,
        source.bundlePath,
        source.inspectionReportPath!,
        plan.outputIndexPath,
        plan.customCatalogPath
      ];
      for (final path in paths) {
        final file = File.fromUri(root.uri.resolve(path));
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(path);
      }
      final ignored = File.fromUri(root.uri.resolve('.git/old.rsbundle'));
      ignored.parent.createSync(recursive: true);
      ignored.writeAsStringSync('unrelated');
      final prior = readPriorGeneratedOutputsFromDirectory(root, plan);
      expect(prior.keys, unorderedEquals(paths));
      for (final path in paths) {
        expect(prior[path], path.codeUnits);
      }
    });
  }
}
