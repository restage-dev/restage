import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_compiler/src/walker/walker_issue_codes.dart'
    as issue_codes;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../policy/fakes/fake_dart_types.dart' as fakes;

void main() {
  const policy = PolicyLedger.builtIn();

  group('walkStructuredType cycle detection', () {
    test('emits structuredCycle when FQN is already in visited', () {
      final boxDecoration = fakes.fakeClassElement(
        'BoxDecoration',
        libraryIdentifier: 'package:flutter/src/painting/box_decoration.dart',
      );
      const fqn =
          'package:flutter/src/painting/box_decoration.dart#BoxDecoration';

      final result = walkStructuredType(
        element: boxDecoration,
        library: WidgetLibrary.core,
        policy: policy,
        location: 'test#BoxDecoration',
        visited: <String>{fqn},
        depth: 0,
      );

      final ir = result.ir;
      expect(ir, isNotNull);
      expect(ir!.fields, isEmpty);
      expect(ir.diagnostics, hasLength(1));
      expect(ir.diagnostics.single.code, issue_codes.structuredCycle);
      expect(ir.diagnostics.single.severity, DiagnosticSeverity.info);
      expect(ir.diagnostics.single.target, 'BoxDecoration');
      expect(result.descendants, isEmpty);
    });
  });

  group('walkStructuredType depth budget', () {
    test('emits structuredDepthExceeded when depth > maxDepth', () {
      final boxDecoration = fakes.fakeClassElement(
        'BoxDecoration',
        libraryIdentifier: 'package:flutter/src/painting/box_decoration.dart',
      );

      final result = walkStructuredType(
        element: boxDecoration,
        library: WidgetLibrary.core,
        policy: policy,
        location: 'test#BoxDecoration',
        visited: <String>{},
        // Built-in policy caps depth at 8.
        depth: 9,
      );

      final ir = result.ir;
      expect(ir, isNotNull);
      expect(ir!.fields, isEmpty);
      expect(ir.diagnostics, hasLength(1));
      expect(ir.diagnostics.single.code, issue_codes.structuredDepthExceeded);
      expect(ir.diagnostics.single.severity, DiagnosticSeverity.info);
      expect(ir.diagnostics.single.target, 'BoxDecoration');
      // The message should reference the configured budget value so the
      // diagnostic is self-describing in build output.
      expect(ir.diagnostics.single.message, contains('8'));
      expect(result.descendants, isEmpty);
    });

    test('respects custom maxDepth from policy', () {
      final ledger = policy.extend(
        structuredWalk: const StructuredWalkPolicy(
          concreteTypes: {
            'package:flutter/src/painting/box_decoration.dart#BoxDecoration',
          },
          abstractTypes: {},
          maxDepth: 2,
        ),
      );
      final boxDecoration = fakes.fakeClassElement(
        'BoxDecoration',
        libraryIdentifier: 'package:flutter/src/painting/box_decoration.dart',
      );

      // depth == maxDepth is still within budget.
      final atBudget = walkStructuredType(
        element: boxDecoration,
        library: WidgetLibrary.core,
        policy: ledger,
        location: 'test#BoxDecoration',
        visited: <String>{},
        depth: 2,
      );
      expect(
        atBudget.ir!.diagnostics
            .where((d) => d.code == issue_codes.structuredDepthExceeded),
        isEmpty,
      );

      // depth > maxDepth trips the diagnostic.
      final overBudget = walkStructuredType(
        element: boxDecoration,
        library: WidgetLibrary.core,
        policy: ledger,
        location: 'test#BoxDecoration',
        visited: <String>{},
        depth: 3,
      );
      expect(
        overBudget.ir!.diagnostics.single.code,
        issue_codes.structuredDepthExceeded,
      );
      expect(overBudget.ir!.diagnostics.single.message, contains('2'));
    });

    test('rejects negative depth', () {
      final boxDecoration = fakes.fakeClassElement(
        'BoxDecoration',
        libraryIdentifier: 'package:flutter/src/painting/box_decoration.dart',
      );

      expect(
        () => walkStructuredType(
          element: boxDecoration,
          library: WidgetLibrary.core,
          policy: policy,
          location: 'test#BoxDecoration',
          visited: <String>{},
          depth: -1,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
