import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/flow/flow_runtime_support.dart'
    show normalizeEventArgs;
import 'package:restage/src/measurement/measurement_event_sanitizer.dart';

const _routeKey = '__restage_measurement_route_v1';
const _reservedPrefix = '__restage_measurement_';

void main() {
  group('MeasurementEventSanitizer', () {
    test('preserves no-argument and scalar values without a carrier', () {
      for (final value in <Object?>[null, 7, true, 'business']) {
        final sanitized = MeasurementEventSanitizer.sanitize(value);

        expect(sanitized.businessValue, same(value));
        expect(
          sanitized.carrierStatus,
          MeasurementEventCarrierStatus.noCarrier,
        );
        expect(sanitized.rawV1CarrierForResolution, isNull);
        expect(
          normalizeEventArgs(sanitized.businessValue),
          value == null
              ? const <String, Object?>{}
              : <String, Object?>{'value': value},
        );
      }
    });

    test('copies a business map without a reserved key', () {
      final nested = <String, Object?>{
        '$_reservedPrefix nested': 'business-owned nested value',
      };
      final input = <String, Object?>{'cta': 'primary', 'nested': nested};

      final sanitized = MeasurementEventSanitizer.sanitize(input);

      expect(sanitized.businessValue, isNot(same(input)));
      expect(sanitized.businessValue, {
        'cta': 'primary',
        'nested': same(nested),
      });
      expect(sanitized.carrierStatus, MeasurementEventCarrierStatus.noCarrier);
      expect((sanitized.businessValue! as Map)['nested'], same(nested));
    });

    test(
      'copies mutable and immutable maps while stripping only top-level keys',
      () {
        final nested = <String, Object?>{
          _routeKey: 'nested carrier-shaped business data',
        };
        final mutable = <String, Object?>{
          'cta': 'primary',
          'nested': nested,
          _routeKey: _validCarrier(),
        };
        final immutable = Map<String, Object?>.unmodifiable(mutable);

        for (final input in <Map<String, Object?>>[mutable, immutable]) {
          final sanitized = MeasurementEventSanitizer.sanitize(input);
          final business = sanitized.businessValue! as Map<String, Object?>;

          expect(business, {'cta': 'primary', 'nested': same(nested)});
          expect(business, isNot(same(input)));
          expect(business['nested'], same(nested));
          expect(
            sanitized.carrierStatus,
            MeasurementEventCarrierStatus.exactV1Carrier,
          );
          expect(sanitized.rawV1CarrierForResolution, _validCarrier());
          expect(input[_routeKey], _validCarrier());
        }
      },
    );

    test('accepts only a canonical exact V1 carrier', () {
      final carrier = _validCarrier();
      final sanitized = MeasurementEventSanitizer.sanitize({
        'business': 1,
        _routeKey: carrier,
      });

      expect(sanitized.businessValue, {'business': 1});
      expect(
        sanitized.carrierStatus,
        MeasurementEventCarrierStatus.exactV1Carrier,
      );
      expect(sanitized.rawV1CarrierForResolution, carrier);
    });

    test('classifies wrong type and malformed exact V1 carriers privately', () {
      final cases = <Object?>[
        null,
        7,
        'mrv1.not-a-valid-edge.${'a' * 32}',
        'mrv1.${_base64Url(utf8.encode('Edge.UPPER'))}.${'a' * 32}',
        'mrv1.${_base64Url(utf8.encode('edge.valid'))}.${'=' * 32}',
        'mrv1.${_base64Url(utf8.encode('edge.valid'))}.${_base64Url(List<int>.filled(23, 1))}',
        'mrv1.${_base64Url(utf8.encode('edge.valid'))}.${_base64Url(List<int>.filled(24, 1))}.extra',
        'mrv1.${_base64Url(utf8.encode('edge.valid'))}.${_base64Url(List<int>.filled(24, 1))}${'x' * 220}',
      ];

      for (final carrier in cases) {
        final input = <String, Object?>{
          'business': 'continues',
          _routeKey: carrier,
        };
        final sanitized = MeasurementEventSanitizer.sanitize(input);

        expect(sanitized.businessValue, {'business': 'continues'});
        expect(
          sanitized.carrierStatus,
          MeasurementEventCarrierStatus.malformedOrWrongType,
          reason: '$carrier',
        );
        expect(sanitized.rawV1CarrierForResolution, isNull);
        expect(input[_routeKey], carrier);
      }
    });

    test(
      'classifies unknown, future, and multiple reserved keys privately',
      () {
        final cases = <Map<String, Object?>>[
          {'business': 1, '${_reservedPrefix}future_v2': 'ignored'},
          {
            'business': 1,
            _routeKey: _validCarrier(),
            '${_reservedPrefix}future': 2,
          },
          {
            'business': 1,
            '${_reservedPrefix}first': 'a',
            '${_reservedPrefix}second': 'b',
          },
        ];

        for (final input in cases) {
          final sanitized = MeasurementEventSanitizer.sanitize(input);

          expect(sanitized.businessValue, {'business': 1});
          expect(
            sanitized.carrierStatus,
            MeasurementEventCarrierStatus.unknownFutureOrMultipleReservedKeys,
          );
          expect(sanitized.rawV1CarrierForResolution, isNull);
        }
      },
    );

    test('does not mutate source maps when Measurement is disabled', () {
      final input = <String, Object?>{
        'business': <String, Object?>{'nested': true},
        _routeKey: 'malformed',
        '${_reservedPrefix}future': 'also removed',
      };
      final before = Map<String, Object?>.from(input);

      final sanitized = MeasurementEventSanitizer.sanitize(input);

      expect(input, before);
      expect(sanitized.businessValue, {'business': same(before['business'])});
      expect(
        sanitized.carrierStatus,
        MeasurementEventCarrierStatus.unknownFutureOrMultipleReservedKeys,
      );
    });
  });
}

String _validCarrier() =>
    'mrv1.${_base64Url(utf8.encode('edge.checkout-root'))}.${_base64Url(List<int>.generate(24, (index) => index))}';

String _base64Url(List<int> bytes) =>
    base64UrlEncode(bytes).replaceAll('=', '');
