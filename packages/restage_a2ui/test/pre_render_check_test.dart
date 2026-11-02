import 'package:a2ui_core/a2ui_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:restage_a2ui/src/installed_capability.dart';
import 'package:restage_a2ui/src/pre_render_check.dart';
import 'package:restage_a2ui/src/restage_a2ui_sidecar.dart';
import 'package:restage_shared/restage_shared.dart'
    show CapabilityManifest, LibraryRequirement;

CatalogApi _catalogOf(List<String> names, {String id = 'restage:test/v1'}) =>
    CatalogApi(
      id: id,
      protocolVersion: A2uiProtocolVersion.v1_0,
      components: [
        for (final name in names)
          ComponentApi(
            name: name,
            schema: S.object(properties: const {}),
          ),
      ],
    );

Map<String, Object?> _create({
  String? catalog = 'restage:test/v1',
  List<Map<String, Object?>>? components,
}) => {
  'version': 'v1.0',
  'createSurface': {
    'surfaceId': 's',
    'catalogId': ?catalog,
    'components': ?components,
  },
};

Map<String, Object?> _update(List<Map<String, Object?>> components) => {
  'version': 'v1.0',
  'updateComponents': {'surfaceId': 's', 'components': components},
};

// A renderable bundle, so a rejection can only come from the field under test.
final _withRoot = _create(
  components: [
    {'id': 'root', 'component': 'Text'},
  ],
);

List<Map<String, Object?>> _rawPayload(List<String> types) => [
  _create(),
  _update([
    for (final (i, t) in types.indexed)
      {'id': i == 0 ? 'root' : t, 'component': t},
  ]),
];

CatalogApi _layoutCatalog() => CatalogApi(
  id: 'restage:test/v1',
  protocolVersion: A2uiProtocolVersion.v1_0,
  components: [
    ComponentApi(
      name: 'Text',
      schema: S.object(properties: const {}),
    ),
    ComponentApi(
      name: 'Box',
      schema: S.object(properties: {'child': CommonSchemas.componentId}),
    ),
    ComponentApi(
      name: 'Column',
      schema: S.object(properties: {'children': CommonSchemas.childList}),
    ),
  ],
);

/// A Restage sidecar wrapping [types] with the given required [manifest].
Map<String, Object?> _sidecar(
  List<String> types,
  CapabilityManifest manifest,
) => RestageA2uiSidecar(
  capability: manifest,
  perItemSinceVersion: const {},
  a2ui: _rawPayload(types),
).toJson();

void main() {
  group('RestageA2uiPreRenderCheck', () {
    test(
      'renders when every referenced type exists and capability satisfied',
      () {
        final check = RestageA2uiPreRenderCheck(
          catalogs: [
            _catalogOf(['Text', 'Column']),
          ],
          installed: A2uiInstalledCapability(
            catalogContentVersion: 3,
            availableLibraries: const [],
          ),
        );
        final result = check.check(
          _sidecar([
            'Text',
            'Column',
          ], CapabilityManifest(builtInFloor: 2, requiredLibraries: const [])),
        );
        expect(result, isA<A2uiRenderable>());
      },
    );

    test(
      'part (a): rejects a missing component before the renderer would fail',
      () {
        final check = RestageA2uiPreRenderCheck(
          catalogs: [
            _catalogOf(['Text']),
          ],
        );
        final result = check.check(_rawPayload(['Text', 'GhostWidget']));
        expect(result, isA<A2uiRejected>());
        expect((result as A2uiRejected).diagnostic, contains('GhostWidget'));
      },
    );

    test(
      'part (a) is universal: a raw payload renders with no installed side',
      () {
        final check = RestageA2uiPreRenderCheck(
          catalogs: [
            _catalogOf(['Text']),
          ],
        );
        expect(check.check(_rawPayload(['Text'])), isA<A2uiRenderable>());
      },
    );

    test(
      'part (b): rejects when builtInFloor exceeds the installed version',
      () {
        final check = RestageA2uiPreRenderCheck(
          catalogs: [
            _catalogOf(['Text']),
          ],
          installed: A2uiInstalledCapability(
            catalogContentVersion: 1,
            availableLibraries: const [],
          ),
        );
        final result = check.check(
          _sidecar([
            'Text',
          ], CapabilityManifest(builtInFloor: 2, requiredLibraries: const [])),
        );
        expect(result, isA<A2uiRejected>());
        expect((result as A2uiRejected).gap, contains('2'));
      },
    );

    test('part (b): rejects a missing / under-version required library', () {
      final installed = A2uiInstalledCapability(
        catalogContentVersion: 5,
        availableLibraries: const [
          A2uiAvailableLibrary(namespace: 'acme.widgets', version: 2),
        ],
      );
      final check = RestageA2uiPreRenderCheck(
        catalogs: [
          _catalogOf(['Text']),
        ],
        installed: installed,
      );
      // acme.widgets installed at 2, payload needs 3.
      final underVersion = check.check(
        _sidecar(
          ['Text'],
          CapabilityManifest(
            builtInFloor: 1,
            requiredLibraries: const [
              LibraryRequirement(namespace: 'acme.widgets', minVersion: 3),
            ],
          ),
        ),
      );
      expect(underVersion, isA<A2uiRejected>());
      expect((underVersion as A2uiRejected).gap, contains('acme.widgets'));
      // a library not installed at all.
      final missingLib = check.check(
        _sidecar(
          ['Text'],
          CapabilityManifest(
            builtInFloor: 1,
            requiredLibraries: const [
              LibraryRequirement(namespace: 'other.lib', minVersion: 1),
            ],
          ),
        ),
      );
      expect(missingLib, isA<A2uiRejected>());
      expect((missingLib as A2uiRejected).gap, contains('other.lib'));
    });

    test('rejects content older than a declared break; renders an additive '
        'bump', () {
      RestageA2uiPreRenderCheck checkWith(int? compatibleSince) =>
          RestageA2uiPreRenderCheck(
            catalogs: [
              _catalogOf(['Text']),
            ],
            installed: A2uiInstalledCapability(
              catalogContentVersion: 3,
              availableLibraries: [
                A2uiAvailableLibrary(
                  namespace: 'acme.widgets',
                  version: 4,
                  compatibleSince: compatibleSince,
                ),
              ],
            ),
          );
      final payload = _sidecar(
        ['Text'],
        CapabilityManifest(
          builtInFloor: 1,
          requiredLibraries: const [
            LibraryRequirement(namespace: 'acme.widgets', minVersion: 3),
          ],
        ),
      );

      final broken = checkWith(4).check(payload);
      expect(broken, isA<A2uiRejected>());
      expect(
        (broken as A2uiRejected).gap,
        'requires library "acme.widgets" >= v3 '
        '(installed v4, compatible since v4)',
      );
      expect(checkWith(null).check(payload), isA<A2uiRenderable>());
      expect(checkWith(3).check(payload), isA<A2uiRenderable>());
    });

    test(
      'FAIL-CLOSED: a stamped payload with no installed descriptor rejects',
      () {
        // The app registered an unstamped catalog / supplied no descriptor.
        final check = RestageA2uiPreRenderCheck(
          catalogs: [
            _catalogOf(['Text']),
          ],
        );
        final result = check.check(
          _sidecar([
            'Text',
          ], CapabilityManifest(builtInFloor: 1, requiredLibraries: const [])),
        );
        expect(
          result,
          isA<A2uiRejected>(),
          reason:
              'a stamped requirement that cannot be verified must fail closed',
        );
        expect((result as A2uiRejected).diagnostic, contains('verif'));
      },
    );

    test('fail-closed: a malformed sidecar rejects, never throws', () {
      final check = RestageA2uiPreRenderCheck(
        catalogs: [
          _catalogOf(['Text']),
        ],
      );
      final result = check.check(const {
        'restageCapability': 'not-an-object',
        'a2ui': <String, Object?>{},
      });
      expect(result, isA<A2uiRejected>());
    });

    test(
      'fail-closed: a sidecar-shaped map of the wrong static type rejects',
      () {
        // A host may hand-build the cached envelope as Map<Object?, Object?>
        // (legal under the Object? API). A blind cast to Map<String, Object?>
        // would throw a TypeError that escapes a FormatException-only catch — a
        // throw at the render seam. It must fail CLOSED instead.
        final check = RestageA2uiPreRenderCheck(
          catalogs: [
            _catalogOf(['Text']),
          ],
        );
        final wrongTypedEnvelope = <Object?, Object?>{
          'restageCapability': <Object?, Object?>{
            'builtInFloor': 1,
            'requiredLibraries': <Object?>[
              <Object?, Object?>{'namespace': 'acme', 'minVersion': 1},
            ],
          },
          'a2ui': <Object?, Object?>{'version': 'v0.9'},
        };
        final A2uiPreRenderResult result;
        try {
          result = check.check(wrongTypedEnvelope);
        } on Object catch (error) {
          fail('check() must not throw at the render seam, threw: $error');
        }
        expect(result, isA<A2uiRejected>());
      },
    );

    test('existence (part a) is checked before the version gap (part b)', () {
      final check = RestageA2uiPreRenderCheck(
        catalogs: [
          _catalogOf(['Text']),
        ],
        installed: A2uiInstalledCapability(
          catalogContentVersion: 1,
          availableLibraries: const [],
        ),
      );
      // Both a missing component AND a version gap; existence wins.
      final result = check.check(
        _sidecar([
          'Text',
          'Ghost',
        ], CapabilityManifest(builtInFloor: 9, requiredLibraries: const [])),
      );
      expect(result, isA<A2uiRejected>());
      expect((result as A2uiRejected).diagnostic, contains('Ghost'));
    });
    test('rejects unknown component catalog without falling back by name', () {
      final check = RestageA2uiPreRenderCheck(
        catalogs: [
          _catalogOf(['Text']),
        ],
      );
      final result = check.check([
        _create(),
        _update([
          {'id': 'root', 'component': 'Text', 'catalogId': 'unknown'},
        ]),
      ]);
      expect(result, isA<A2uiRejected>());
      expect((result as A2uiRejected).diagnostic, contains('unknown'));
    });

    test('same component name is validated in its selected catalog', () {
      final restrictive = CatalogApi(
        id: 'other',
        protocolVersion: A2uiProtocolVersion.v1_0,
        components: [
          ComponentApi(
            name: 'Text',
            schema: S.object(
              properties: {'props_label': S.string()},
              required: ['props_label'],
            ),
          ),
        ],
      );
      final check = RestageA2uiPreRenderCheck(
        catalogs: [
          _catalogOf(['Text']),
          restrictive,
        ],
      );
      expect(check.check(_rawPayload(['Text'])), isA<A2uiRenderable>());
      expect(
        check.check([
          _create(),
          _update([
            {'id': 'root', 'component': 'Text', 'catalogId': 'other'},
          ]),
        ]),
        isA<A2uiRejected>(),
      );
      expect(
        check.check([
          _create(),
          _update([
            {
              'id': 'root',
              'component': 'Text',
              'catalogId': 'other',
              'props_label': 'selected',
            },
          ]),
        ]),
        isA<A2uiRenderable>(),
      );
    });

    test(
      'no surface default requires an explicit catalog on each component',
      () {
        final check = RestageA2uiPreRenderCheck(
          catalogs: [
            _catalogOf(['Text']),
          ],
        );
        expect(
          check.check([
            _create(catalog: null),
            _update([
              {'id': 'root', 'component': 'Text'},
            ]),
          ]),
          isA<A2uiRejected>(),
        );
        expect(
          check.check([
            _create(catalog: null),
            _update([
              {
                'id': 'root',
                'component': 'Text',
                'catalogId': 'restage:test/v1',
              },
            ]),
          ]),
          isA<A2uiRenderable>(),
        );
      },
    );

    test(
      'rejects complete bundles the renderer could only show as a placeholder',
      () {
        final check = RestageA2uiPreRenderCheck(catalogs: [_layoutCatalog()]);
        const delete = {
          'version': 'v1.0',
          'deleteSurface': {'surfaceId': 's'},
        };
        final unrenderable = <String, Object?>{
          'empty bundle': <Object?>[],
          'surface without components': _create(),
          'missing root': [
            _create(),
            _update([
              {'id': 'notroot', 'component': 'Text'},
            ]),
          ],
          'dangling child': [
            _create(),
            _update([
              {'id': 'root', 'component': 'Box', 'child': 'ghost'},
            ]),
          ],
          'dangling list child': [
            _create(),
            _update([
              {
                'id': 'root',
                'component': 'Column',
                'children': ['a', 'ghost'],
              },
              {'id': 'a', 'component': 'Text'},
            ]),
          ],
          'only a delete': [delete],
        };
        for (final entry in unrenderable.entries) {
          expect(
            check.check(entry.value),
            isA<A2uiRejected>(),
            reason: entry.key,
          );
        }
      },
    );

    test('applies the renderer validation config to each message', () {
      final bundles = <String, List<Map<String, Object?>>>{
        'child in a later message': [
          _create(),
          _update([
            {'id': 'root', 'component': 'Box', 'child': 'late'},
          ]),
          _update([
            {'id': 'late', 'component': 'Text'},
          ]),
        ],
        'root in a later message': [
          _create(),
          _update([
            {'id': 'leaf', 'component': 'Text'},
          ]),
          _update([
            {
              'id': 'root',
              'component': 'Column',
              'children': ['leaf'],
            },
          ]),
        ],
        'unreferenced component': [
          _create(),
          _update([
            {'id': 'root', 'component': 'Text'},
            {'id': 'extra', 'component': 'Text'},
          ]),
        ],
      };
      final lenient = RestageA2uiPreRenderCheck(catalogs: [_layoutCatalog()]);
      final strict = RestageA2uiPreRenderCheck(
        catalogs: [_layoutCatalog()],
        validationConfig: ValidationConfig.strict,
      );
      for (final entry in bundles.entries) {
        expect(
          lenient.check(entry.value),
          isA<A2uiRenderable>(),
          reason: entry.key,
        );
        expect(
          strict.check(entry.value),
          isA<A2uiRejected>(),
          reason: entry.key,
        );
      }
    });

    test('the finished-bundle check uses the renderer depth limit', () {
      final chain = [
        _create(),
        _update([
          for (var i = 0; i < 60; i++)
            {
              'id': i == 0 ? 'root' : 'n$i',
              'component': i == 59 ? 'Text' : 'Box',
              if (i < 59) 'child': 'n${i + 1}',
            },
        ]),
      ];
      expect(
        RestageA2uiPreRenderCheck(catalogs: [_layoutCatalog()]).check(chain),
        isA<A2uiRejected>(),
      );
      expect(
        RestageA2uiPreRenderCheck(
          catalogs: [_layoutCatalog()],
          validationConfig: const ValidationConfig(maxDepth: 80),
        ).check(chain),
        isA<A2uiRenderable>(),
      );
    });

    test('checks the root the renderer is configured with', () {
      final payload = [
        _create(),
        _update([
          {'id': 'main', 'component': 'Text'},
        ]),
      ];
      expect(
        RestageA2uiPreRenderCheck(catalogs: [_layoutCatalog()]).check(payload),
        isA<A2uiRejected>(),
      );
      expect(
        RestageA2uiPreRenderCheck(
          catalogs: [_layoutCatalog()],
          validationConfig: const ValidationConfig(rootId: 'main'),
        ).check(payload),
        isA<A2uiRenderable>(),
      );
    });

    test('accepts the messages wrapper', () {
      final check = RestageA2uiPreRenderCheck(
        catalogs: [
          _catalogOf(['Text']),
        ],
      );
      expect(
        check.check({
          'messages': _rawPayload(['Text']),
        }),
        isA<A2uiRenderable>(),
      );
    });

    test('validates inline createSurface components', () {
      final check = RestageA2uiPreRenderCheck(
        catalogs: [
          _catalogOf(['Text']),
        ],
      );
      expect(
        check.check(
          _create(
            components: [
              {'id': 'root', 'component': 'Text'},
            ],
          ),
        ),
        isA<A2uiRenderable>(),
      );
      expect(
        check.check(
          _create(
            components: [
              {'id': 'root', 'component': 'Ghost'},
            ],
          ),
        ),
        isA<A2uiRejected>(),
      );
      expect(check.check(_withRoot), isA<A2uiRenderable>());
      expect(
        check.check(
          _create(
            catalog: 'unknown',
            components: [
              {'id': 'root', 'component': 'Text'},
            ],
          ),
        ),
        isA<A2uiRejected>(),
      );
    });

    test('delete and recreate do not retain the old catalog default', () {
      final check = RestageA2uiPreRenderCheck(
        catalogs: [
          _catalogOf(['Text']),
          _catalogOf(['Other'], id: 'other'),
        ],
      );
      const delete = {
        'version': 'v1.0',
        'deleteSurface': {'surfaceId': 's'},
      };
      expect(
        check.check([
          ..._rawPayload(['Text']),
          delete,
          _create(catalog: 'other'),
          _update([
            {'id': 'root', 'component': 'Other'},
          ]),
        ]),
        isA<A2uiRenderable>(),
      );
      expect(
        check.check([
          ..._rawPayload(['Text']),
          delete,
          _create(catalog: 'other'),
          _update([
            {'id': 'root', 'component': 'Text'},
          ]),
        ]),
        isA<A2uiRejected>(),
      );
      expect(
        check.check([
          _create(),
          delete,
          _update([
            {'id': 'root', 'component': 'Text'},
          ]),
        ]),
        isA<A2uiRejected>(),
      );
    });

    test('malformed envelopes and non-v1 versions fail closed', () {
      final check = RestageA2uiPreRenderCheck(
        catalogs: [
          _catalogOf(['Text']),
        ],
      );
      for (final payload in <Object?>[
        null,
        'text',
        [null],
        {},
        {'version': 'v1.0'},
        {
          'version': 'v1.0',
          'createSurface': {'surfaceId': 's'},
          'deleteSurface': {'surfaceId': 's'},
        },
        {
          'version': 'v1.0',
          'createSurface': {'surfaceId': 1},
        },
        _create(
          components: [
            {'id': 'root', 'component': 42},
          ],
        ),
        _create(
          components: [
            {'id': 'root'},
          ],
        ),
        _create(components: []),
        for (final version in ['v0.9', 'v0.9.1', '1.0', 'v2.0'])
          {..._withRoot, 'version': version},
      ]) {
        expect(check.check(payload), isA<A2uiRejected>(), reason: '$payload');
      }
    });

    test('data-model objects are not scanned as components', () {
      final check = RestageA2uiPreRenderCheck(
        catalogs: [
          _catalogOf(['Text']),
        ],
      );
      expect(
        check.check([
          ..._rawPayload(['Text']),
          {
            'version': 'v1.0',
            'updateDataModel': {
              'surfaceId': 's',
              'path': '/business',
              'value': {
                'id': 'x',
                'component': 'NotAWidget',
                'path': 'ordinary',
              },
            },
          },
        ]),
        isA<A2uiRenderable>(),
      );
    });

    test('preflight validates registered functions without invoking them', () {
      final function = _CountingFunction();
      final catalog = Catalog<ComponentApi, FunctionImplementation>(
        id: 'restage:test/v1',
        protocolVersion: A2uiProtocolVersion.v1_0,
        components: [
          ComponentApi(
            name: 'Text',
            schema: S.object(
              properties: {'props_text': CommonSchemasV1.dynamicString},
            ),
          ),
        ],
        functions: [function],
      );
      final check = RestageA2uiPreRenderCheck(catalogs: [catalog]);
      final payload = [
        _create(
          components: [
            {
              'id': 'root',
              'component': 'Text',
              'props_text': {'@call': 'count'},
            },
          ],
        ),
        {
          'version': 'v1.0',
          'callRendererFunction': {
            'surfaceId': 's',
            'functionCallId': 'call-1',
            'callFunction': {'@call': 'count', 'catalogId': catalog.id},
          },
        },
      ];
      expect(check.check(payload), isA<A2uiRenderable>());
      expect(function.invocations, 0);
      expect(
        check.check(payload),
        isA<A2uiRenderable>(),
        reason: 'each check starts with an independent surface model',
      );
      expect(function.invocations, 0);
    });
  });
}

class _CountingFunction extends FunctionImplementation {
  _CountingFunction()
    : super(
        name: 'count',
        argumentSchema: S.object(properties: const {}),
        returnType: A2uiReturnType.string,
        allowedCallers: AllowedCallers.rendererOrAgent,
      );

  int invocations = 0;

  @override
  Object? execute(
    Map<String, dynamic> args,
    DataContext context, [
    CancellationSignal? cancellationSignal,
  ]) {
    invocations++;
    return 'called';
  }
}
