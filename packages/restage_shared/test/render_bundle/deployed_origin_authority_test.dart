import 'package:restage_shared/src/render_bundle/deployed_origin_authority.dart';
import 'package:test/test.dart';

void main() {
  group('render bundle execution origin authority', () {
    test('accepts only exact code-approved parent authorities', () {
      for (final origin in <String>[
        'http://dashboard.restage.localhost:8082',
        'http://dashboard.restage.localhost:8082/',
        'https://dashboard.restage.dev',
        'https://preview-1.restage.dev/',
      ]) {
        expect(
          isApprovedRenderBundleParentOrigin(Uri.parse(origin)),
          isTrue,
          reason: origin,
        );
      }

      for (final origin in <String>[
        'http://localhost:8082',
        'http://127.0.0.1:8082',
        'http://attacker.restage.localhost:8082',
        'http://api.restage.localhost:8082',
        'http://bundles.restage.localhost:8082',
        'http://dashboard.restage.localhost',
        'https://dashboard.restage.localhost:8082',
        'https://restage.dev',
        'https://nested.dashboard.restage.dev',
        'https://dashboard.restage.dev:444',
        'http://dashboard.restage.dev',
        'https://user@dashboard.restage.dev',
        'https://dashboard.restage.dev/shell',
        'https://dashboard.restage.dev?next=evil',
        'https://dashboard.restage.dev#fragment',
        'https://dashboard.example.test',
      ]) {
        expect(
          isApprovedRenderBundleParentOrigin(Uri.parse(origin)),
          isFalse,
          reason: origin,
        );
      }
    });

    test('derives one exact finite local host per immutable id', () {
      final control = Uri.parse('http://bundles.restage.localhost:19085');

      expect(
        deriveRenderBundleExecutionOrigin(control, 7),
        Uri.parse('http://b-7.restage.localhost:19085'),
      );
      expect(
        deriveRenderBundleExecutionOrigin(control, 8),
        Uri.parse('http://b-8.restage.localhost:19085'),
      );
      expect(
        isExactRenderBundleExecutionOrigin(
          configuredBundleOrigin: control,
          renderBundleId: 7,
          executionOrigin: Uri.parse('http://b-7.restage.localhost:19085'),
        ),
        isTrue,
      );
      expect(
        isExactRenderBundleExecutionOrigin(
          configuredBundleOrigin: control,
          renderBundleId: 7,
          executionOrigin: Uri.parse('http://b-8.restage.localhost:19085'),
        ),
        isFalse,
      );
    });

    test('rejects non-role local controls instead of normalizing', () {
      for (final origin in <String>[
        'http://localhost:19085',
        'http://127.0.0.1:19085',
        'http://control.restage.localhost:19085',
      ]) {
        expect(
          deriveRenderBundleExecutionOrigin(Uri.parse(origin), 42),
          isNull,
          reason: origin,
        );
      }
    });

    test(
      'nests one deployed host per immutable id beneath the control host',
      () {
        final control = Uri.parse('https://bundles.restage.dev');
        final maxSignedRenderBundleId = int.parse(
          maxSignedRenderBundleIdDecimal,
        );

        expect(
          deriveRenderBundleExecutionOrigin(control, 42),
          Uri.parse('https://b-42.bundles.restage.dev'),
        );
        expect(
          isExactRenderBundleExecutionOrigin(
            configuredBundleOrigin: control,
            renderBundleId: 42,
            executionOrigin: Uri.parse(
              'https://b-42.bundles.restage.dev',
            ),
          ),
          isTrue,
        );
        // The derived label carries only the id, so a control label may use the
        // whole DNS-label bound.
        expect(
          deriveRenderBundleExecutionOrigin(
            Uri.parse('https://${'a' * 63}.restage.dev'),
            maxSignedRenderBundleId,
          ),
          Uri.parse(
            'https://b-$maxSignedRenderBundleId.${'a' * 63}.restage.dev',
          ),
        );
      },
      onPlatform: <String, dynamic>{'browser': const Skip('VM int boundary')},
    );

    test('derives execution origins only for control authorities', () {
      expect(
        maxSignedRenderBundleIdDecimal,
        '9223372036854775807',
      );
      for (final origin in <String>[
        'https://bundles.restage.dev',
        'https://${'a' * 63}.restage.dev',
        'http://bundles.restage.localhost:19085',
      ]) {
        expect(
          canDeriveRenderBundleExecutionOrigin(Uri.parse(origin)),
          isTrue,
          reason: origin,
        );
      }
      for (final origin in <String>[
        'https://b-42.bundles.restage.dev',
        'https://nested.bundles.restage.dev',
        'https://bundles.example.test',
        'https://bundles.restage.dev:8443',
        'http://bundles.restage.dev',
        'http://bundles.restage.localhost',
        'http://localhost:19085',
      ]) {
        expect(
          canDeriveRenderBundleExecutionOrigin(Uri.parse(origin)),
          isFalse,
          reason: origin,
        );
      }
    });

    test(
      'fails closed for invalid ids and authorities',
      () {
        final maxSignedRenderBundleId = int.parse(
          maxSignedRenderBundleIdDecimal,
        );
        for (final id in <int>[0, -1, maxSignedRenderBundleId + 1]) {
          expect(
            deriveRenderBundleExecutionOrigin(
              Uri.parse('https://bundles.restage.dev'),
              id,
            ),
            isNull,
            reason: '$id',
          );
        }
        // An execution host is never itself a control authority, so a derived
        // host cannot be fed back in to derive a deeper one.
        for (final origin in <String>[
          'http://bundles.restage.localhost',
          'http://example.test:19085',
          'https://b-42.bundles.restage.dev',
          'https://nested.bundles.restage.dev',
          'https://bundles.example.test',
        ]) {
          expect(
            deriveRenderBundleExecutionOrigin(Uri.parse(origin), 1),
            isNull,
            reason: origin,
          );
        }
      },
      onPlatform: <String, dynamic>{'browser': const Skip('VM int boundary')},
    );

    test('accepts only the exact finite local role triplet', () {
      expect(
        isApprovedRenderBundleOriginTriplet(
          Uri.parse('http://api.restage.localhost:8080'),
          Uri.parse('http://dashboard.restage.localhost:8081'),
          Uri.parse('http://bundles.restage.localhost:8082'),
        ),
        isTrue,
      );
      for (final hosts in <List<String>>[
        ['localhost', 'localhost', 'localhost'],
        ['127.0.0.1', '127.0.0.1', '127.0.0.1'],
        [
          'dashboard.restage.localhost',
          'api.restage.localhost',
          'bundles.restage.localhost',
        ],
      ]) {
        expect(
          isApprovedRenderBundleOriginTriplet(
            Uri.parse('http://${hosts[0]}:8080'),
            Uri.parse('http://${hosts[1]}:8081'),
            Uri.parse('http://${hosts[2]}:8082'),
          ),
          isFalse,
          reason: '$hosts',
        );
      }
    });

    test('accepts only the exact finite local shell/control pair', () {
      expect(
        isApprovedRenderBundleLocalShellControlPair(
          Uri.parse('http://dashboard.restage.localhost:8081'),
          Uri.parse('http://bundles.restage.localhost:8082'),
        ),
        isTrue,
      );
      expect(
        isApprovedRenderBundleLocalShellControlPair(
          Uri.parse('http://attacker.restage.localhost:8081'),
          Uri.parse('http://bundles.restage.localhost:8082'),
        ),
        isFalse,
      );
    });

    test('accepts only the exact finite local API/control pair', () {
      expect(
        isApprovedRenderBundleLocalApiControlPair(
          Uri.parse('http://api.restage.localhost:8080'),
          Uri.parse('http://bundles.restage.localhost:8082'),
        ),
        isTrue,
      );
      expect(
        isApprovedRenderBundleLocalApiControlPair(
          Uri.parse('http://localhost:8080'),
          Uri.parse('http://bundles.restage.localhost:8082'),
        ),
        isFalse,
      );
    });
  });
}
