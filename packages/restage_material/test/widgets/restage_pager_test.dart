import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_material/restage_material.dart';

void main() {
  group('RestagePager', () {
    test('asserts children is non-empty', () {
      expect(
        () => RestagePager(children: const []),
        throwsA(
          isA<AssertionError>().having(
            (e) => e.message,
            'message',
            'RestagePager.children must be non-empty.',
          ),
        ),
      );
    });

    test('asserts initialPage is non-negative', () {
      expect(
        () => RestagePager(
          initialPage: -1,
          children: const [SizedBox()],
        ),
        throwsA(
          isA<AssertionError>().having(
            (e) => e.message,
            'message',
            'RestagePager.initialPage must be non-negative.',
          ),
        ),
      );
    });

    test('asserts viewportFraction is in range', () {
      expect(
        () => RestagePager(
          viewportFraction: 0,
          children: const [SizedBox()],
        ),
        throwsA(
          isA<AssertionError>().having(
            (e) => e.message,
            'message',
            'RestagePager.viewportFraction must be in (0, 1].',
          ),
        ),
      );
      expect(
        () => RestagePager(
          viewportFraction: 1.1,
          children: const [SizedBox()],
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
