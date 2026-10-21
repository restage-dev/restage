import 'dart:convert';
import 'dart:io';

import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

int _nodes(Object? root) {
  var count = 0;
  final stack = <Object?>[root];
  while (stack.isNotEmpty) {
    final value = stack.removeLast();
    count++;
    if (value is Map) stack.addAll(value.values);
    if (value is List) stack.addAll(value);
  }
  return count;
}

void main() {
  test(
    'the built-in catalogs leave room for an app catalog in the manifest',
    () {
      var nodes = 0;
      var bytes = 0;
      for (final package in [
        'restage_core',
        'restage_material',
        'restage_cupertino',
      ]) {
        final catalog = jsonDecode(
          File(
            '../$package/lib/src/widget_catalog/catalog.json',
          ).readAsStringSync(),
        );
        nodes += _nodes(catalog);
        // The manifest carries the catalog compact.
        bytes += utf8.encode(jsonEncode(catalog)).length;
      }
      // An app's merged catalog adds its own widgets on top of the built-ins.
      expect(nodes * 2, lessThan(renderBundleMaxCapabilityManifestNodes));
      expect(bytes * 2, lessThan(renderBundleMaxCapabilityManifestBytes));
    },
  );
}
