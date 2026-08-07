import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart'
    show kReservedPreviewConstructorName, kReservedPreviewLibraryName;
import 'package:restage_preview_host/restage_preview_host.dart';

Map<String, Object?> _catalog() => <String, Object?>{
      'schemaVersion': 4,
      'libraries': <String, Object?>{
        'acme.widgets': <String, Object?>{
          'version': '1.2.0',
          'capabilityVersion': 2,
        },
        'beta.widgets': <String, Object?>{
          'version': '3.0.0',
          'capabilityVersion': 7,
        },
        'unversioned.widgets': <String, Object?>{'version': '0.1.0'},
      },
      'widgets': <Object?>[
        <String, Object?>{
          'wireId': 'w0001',
          'name': 'Badge',
          'library': 'acme.widgets',
          'properties': <Object?>[
            <String, Object?>{
              'wireId': 'p0001',
              'name': 'style',
              'type': 'structured',
              'valueShape': <String, Object?>{
                'kind': 'structured',
                'structuredRef': <String, Object?>{
                  'library': 'acme.widgets',
                  'wireId': 's0001',
                },
                'futureShapeField': <String, Object?>{'enabled': true},
              },
            },
          ],
          'futureWidgetField': <String, Object?>{'mode': 'new'},
        },
      ],
      'structuredTypes': <Object?>[
        <String, Object?>{
          'wireId': 's0001',
          'name': 'BadgeStyle',
          'library': 'acme.widgets',
          'fields': <Object?>[
            <String, Object?>{
              'wireId': 'p0002',
              'name': 'tone',
              'type': 'string',
            },
          ],
          'variants': <Object?>[],
        },
      ],
      'unions': <Object?>[
        <String, Object?>{'wireId': 'u0001', 'name': 'BadgeVariant'},
      ],
      'designTokens': <Object?>[
        <String, Object?>{'name': 'badge.accent', 'type': 'color'},
      ],
      'compatRules': <Object?>[
        <String, Object?>{'kind': 'rename', 'from': 'oldTone', 'to': 'tone'},
      ],
      'futureCatalogField': <String, Object?>{
        'nested': <Object?>[
          <String, Object?>{'preserved': true},
        ],
      },
    };

void main() {
  test('wraps complete canonical catalog JSON without lossy projection', () {
    final source = _catalog();
    final manifest = RenderBundleManifest(formatVersion: 1, catalog: source);

    expect(manifest.formatVersion, 1);
    expect(manifest.catalog, source);
    expect(
      manifest.toJson().keys,
      unorderedEquals(<String>['formatVersion', 'catalog']),
    );
    expect(
      RenderBundleManifest.fromJson(manifest.toJson()).toJson(),
      manifest.toJson(),
    );
    expect(
      RenderBundleManifest.fromCatalogJson(jsonEncode(source)).catalog,
      source,
    );

    final libraries = manifest.catalog['libraries']! as Map<String, Object?>;
    expect(
      (libraries['acme.widgets']! as Map<String, Object?>)['capabilityVersion'],
      2,
    );
    expect(
      (libraries['beta.widgets']! as Map<String, Object?>)['capabilityVersion'],
      7,
    );
    expect(
      (libraries['unversioned.widgets']!
          as Map<String, Object?>)['capabilityVersion'],
      isNull,
    );
    final widget = (manifest.catalog['widgets']! as List<Object?>).single
        as Map<String, Object?>;
    final property =
        (widget['properties']! as List<Object?>).single as Map<String, Object?>;
    expect(
      ((property['valueShape']! as Map<String, Object?>)['structuredRef']!
          as Map<String, Object?>)['wireId'],
      's0001',
    );
    expect(widget['futureWidgetField'], <String, Object?>{'mode': 'new'});
    expect(
      manifest.catalog['futureCatalogField'],
      <String, Object?>{
        'nested': <Object?>[
          <String, Object?>{'preserved': true},
        ],
      },
    );
  });

  test('catalog snapshot is deeply immutable and detached from caller input',
      () {
    final source = _catalog();
    final manifest = RenderBundleManifest(formatVersion: 1, catalog: source);
    final libraries = source['libraries']! as Map<String, Object?>;
    (libraries['acme.widgets']! as Map<String, Object?>)['capabilityVersion'] =
        99;

    final snapshotLibraries =
        manifest.catalog['libraries']! as Map<String, Object?>;
    expect(
      (snapshotLibraries['acme.widgets']!
          as Map<String, Object?>)['capabilityVersion'],
      2,
    );
    expect(
      () => (snapshotLibraries['acme.widgets']!
          as Map<String, Object?>)['capabilityVersion'] = 5,
      throwsUnsupportedError,
    );
    final widget = (manifest.catalog['widgets']! as List<Object?>).single
        as Map<String, Object?>;
    expect(
      () => (widget['properties']! as List<Object?>).add('injected'),
      throwsUnsupportedError,
    );
  });

  test('rejects duplicate widget identities instead of merging conflicts', () {
    final catalog = _catalog();
    (catalog['widgets']! as List<Object?>).add(<String, Object?>{
      'wireId': 'w9999',
      'name': 'Badge',
      'library': 'acme.widgets',
      'properties': <Object?>[],
    });

    expect(
      () => RenderBundleManifest(formatVersion: 1, catalog: catalog),
      throwsFormatException,
    );
  });

  test('rejects customer claims to preview-only catalog symbols', () {
    final libraryClaim = _catalog();
    final libraries = libraryClaim['libraries']! as Map<String, Object?>;
    libraries[kReservedPreviewLibraryName] = <String, Object?>{
      'version': '1.0.0',
    };
    expect(
      () => RenderBundleManifest(formatVersion: 1, catalog: libraryClaim),
      throwsFormatException,
    );

    final constructorClaim = _catalog();
    final widget = (constructorClaim['widgets']! as List<Object?>).single
        as Map<String, Object?>;
    widget['name'] = kReservedPreviewConstructorName;
    expect(
      () => RenderBundleManifest(formatVersion: 1, catalog: constructorClaim),
      throwsFormatException,
    );
  });

  test(
      'rejects malformed indexes, non-JSON values, non-finite values, and '
      'credential-shaped keys', () {
    final malformedIndex = _catalog();
    ((malformedIndex['widgets']! as List<Object?>).single
        as Map<String, Object?>)['library'] = 7;
    expect(
      () => RenderBundleManifest(formatVersion: 1, catalog: malformedIndex),
      throwsFormatException,
    );

    for (final invalid in <Object?>[
      Object(),
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      final catalog = _catalog()..['futureCatalogField'] = invalid;
      expect(
        () => RenderBundleManifest(formatVersion: 1, catalog: catalog),
        anyOf(throwsArgumentError, throwsFormatException),
      );
    }

    final credentials = _catalog()
      ..['futureCatalogField'] = <String, Object?>{
        'nested': <String, Object?>{'accessToken': 'must not cross'},
      };
    expect(
      () => RenderBundleManifest(formatVersion: 1, catalog: credentials),
      throwsArgumentError,
    );
  });
}
