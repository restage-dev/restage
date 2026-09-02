import 'package:restage_codegen/src/dsl_emission.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:test/test.dart';

void main() {
  test('required children distinguish complete bytes from refusal', () {
    final completeIssues = <Issue>[];
    final complete = normalizePresentChild(completeIssues, () {
      completeIssues.add(
        const Issue(
          code: IssueCode.idiomAutoSubstituted,
          message: 'Canonical spelling was selected.',
          location: 'value.dart:1',
        ),
      );
      return 'data.value';
    });
    expect(complete, isA<CompleteDslEmission>());
    expect(unwrapDslEmission(complete), 'data.value');

    final refusedIssues = <Issue>[];
    final refused = normalizePresentChild(refusedIssues, () {
      refusedIssues.add(
        const Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: 'The value cannot be translated.',
          location: 'value.dart:1',
        ),
      );
      return 'partial';
    });
    expect(refused, isA<RefusedDslEmission>());
    expect(unwrapDslEmission(refused), isEmpty);

    expect(
      normalizePresentChild(<Issue>[], () => ''),
      isA<RefusedDslEmission>(),
    );
  });

  test('optional children distinguish omission from refusal', () {
    expect(
      normalizeOptionalChild(<Issue>[], () => ''),
      isA<AbsentDslEmission>(),
    );

    final issues = <Issue>[];
    final refused = normalizeOptionalChild(issues, () {
      issues.add(
        const Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: 'The value cannot be translated.',
          location: 'value.dart:1',
        ),
      );
      return '';
    });
    expect(refused, isA<RefusedDslEmission>());
  });
}
