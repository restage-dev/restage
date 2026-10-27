import 'package:test/test.dart';

import 'support/native_flow_fixture_generation.dart';

void main() {
  test('native fixture owner retains the public source and output paths', () {
    expect(
      nativeFlowFixtureSourcePath,
      '../restage/test/fixtures/compiled_surfaces/native_flow.dart',
    );
    expect(
      nativeFlowFixturePath,
      '../restage/test/fixtures/compiled_surfaces/restage.generated/native_flow.restage.g.dart',
    );
  });

  test('native fixture formatting retains its package language style', () {
    expect(formatNativeFlowFixture('const answer=42;'), 'const answer = 42;\n');
  });
}
