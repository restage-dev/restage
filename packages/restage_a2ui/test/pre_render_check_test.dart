import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:restage_a2ui/src/installed_capability.dart';
import 'package:restage_a2ui/src/pre_render_check.dart';
import 'package:restage_a2ui/src/restage_a2ui_sidecar.dart';
import 'package:restage_shared/restage_shared.dart'
    show CapabilityManifest, LibraryRequirement;

/// A genui catalog with the given component names — only the names matter for
/// the existence walk; the schema/builder are inert stubs.
Catalog _catalogOf(List<String> names) => Catalog([
  for (final name in names)
    CatalogItem(
      name: name,
      dataSchema: S.object(properties: const {}),
      widgetBuilder: (_) => const _Stub(),
    ),
]);

class _Stub extends StatelessWidget {
  const _Stub();
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// A raw (unstamped) A2UI payload referencing [types].
Map<String, Object?> _rawPayload(List<String> types) => {
  'version': 'v0.9',
  'updateComponents': {
    'surfaceId': 's',
    'components': [
      for (final t in types) {'id': t, 'component': t},
    ],
  },
};

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
          catalog: _catalogOf(['Text', 'Column']),
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

    test('part (a): rejects a missing component before genui would throw', () {
      final check = RestageA2uiPreRenderCheck(catalog: _catalogOf(['Text']));
      final result = check.check(_rawPayload(['Text', 'GhostWidget']));
      expect(result, isA<A2uiRejected>());
      expect((result as A2uiRejected).diagnostic, contains('GhostWidget'));
    });

    test(
      'part (a) is universal: a raw payload renders with no installed side',
      () {
        final check = RestageA2uiPreRenderCheck(catalog: _catalogOf(['Text']));
        expect(check.check(_rawPayload(['Text'])), isA<A2uiRenderable>());
      },
    );

    test(
      'part (b): rejects when builtInFloor exceeds the installed version',
      () {
        final check = RestageA2uiPreRenderCheck(
          catalog: _catalogOf(['Text']),
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
        catalog: _catalogOf(['Text']),
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

    test(
      'FAIL-CLOSED: a stamped payload with no installed descriptor rejects',
      () {
        // The app registered an unstamped catalog / supplied no descriptor.
        final check = RestageA2uiPreRenderCheck(catalog: _catalogOf(['Text']));
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
      final check = RestageA2uiPreRenderCheck(catalog: _catalogOf(['Text']));
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
        final check = RestageA2uiPreRenderCheck(catalog: _catalogOf(['Text']));
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
        catalog: _catalogOf(['Text']),
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
  });
}
