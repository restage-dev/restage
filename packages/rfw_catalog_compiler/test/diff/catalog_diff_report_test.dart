import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('computeCatalogDiff', () {
    test('reports a removed widget — classified and ruled', () {
      final report = computeCatalogDiff(
        catalog(widgets: [widgetEntry(wireId: 'w0001')]),
        catalog(),
      );
      expect(report.changes, hasLength(1));
      expect(
        report.changes.single.change,
        EntryRemoved(kind: WireIdKind.widget, affected: ref('w0001')),
      );
      expect(
        report.changes.single.classification,
        CompatClassification.breaking,
      );
      expect(report.compatRules, hasLength(1));
      expect(report.compatRules.single.kind, CompatKind.removal);
    });

    test('versions default to the catalogs generatedAt timestamps', () {
      final report = computeCatalogDiff(
        catalog(
          widgets: [widgetEntry(wireId: 'w0001')],
          generatedAt: '2025-12-01T00:00:00Z',
        ),
        catalog(generatedAt: '2026-02-01T00:00:00Z'),
      );
      expect(report.fromVersion, '2025-12-01T00:00:00Z');
      expect(report.toVersion, '2026-02-01T00:00:00Z');
      expect(report.compatRules.single.fromVersion, '2025-12-01T00:00:00Z');
      expect(report.compatRules.single.toVersion, '2026-02-01T00:00:00Z');
    });

    test('explicit fromVersion / toVersion override the defaults', () {
      final report = computeCatalogDiff(
        catalog(widgets: [widgetEntry(wireId: 'w0001')]),
        catalog(),
        fromVersion: 'release-1',
        toVersion: 'release-2',
      );
      expect(report.fromVersion, 'release-1');
      expect(report.toVersion, 'release-2');
      expect(report.compatRules.single.fromVersion, 'release-1');
      expect(report.compatRules.single.toVersion, 'release-2');
    });

    test('classifies every change but rules only breaking/forwarding ones', () {
      final report = computeCatalogDiff(
        catalog(widgets: [widgetEntry(wireId: 'w0001', name: 'A')]),
        catalog(
          widgets: [
            widgetEntry(wireId: 'w0001', name: 'B'),
            widgetEntry(wireId: 'w0002'),
          ],
        ),
      );
      expect(report.changes, hasLength(2));
      expect(
        report.changes.map((c) => c.classification).toSet(),
        {CompatClassification.free, CompatClassification.additive},
      );
      expect(report.compatRules, isEmpty);
    });
  });
}
