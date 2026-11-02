import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage_a2ui_example/generated/restage_a2ui_catalog.g.dart';

void main() {
  test(
    'committed example producer document equals the generated v1 catalog',
    () {
      final envelope =
          jsonDecode(
                File(
                  'lib/generated/restage_a2ui_catalog.a2ui.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      final document = envelope['a2uiCatalog']! as Map<String, Object?>;
      expect(document['protocolVersion'], '1.0');
      expect(document['catalogId'], restageA2uiCatalogId);
      expect(document, buildRestageCatalog().toJson());
    },
  );
}
