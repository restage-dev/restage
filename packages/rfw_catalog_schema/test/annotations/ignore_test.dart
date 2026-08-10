import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

const targetAlias = <EmitTarget>[
  EmitTarget.widgetbook,
  EmitTarget.a2ui,
  EmitTarget.a2ui,
];

final class IgnoreShapeProbe {
  const IgnoreShapeProbe({
    @ignore this.legacy = '',
    @Ignore() this.legacyConstructor = '',
    // Explicit null is part of the legacy-compatible annotation shape.
    // ignore: avoid_redundant_argument_values
    @Ignore(null) this.explicitAll = '',
    @Ignore(targetAlias) this.alias = '',
    @Ignore({EmitTarget.rfw, EmitTarget.widgetbook}) this.set = '',
    @Ignore(<EmitTarget>[]) this.empty = '',
  });

  final String legacy;
  final String legacyConstructor;
  final String explicitAll;
  final String alias;
  final String set;
  final String empty;
}

void main() {
  test('EmitTarget is the public three-target authoring enum', () {
    expect(
      EmitTarget.values,
      [EmitTarget.rfw, EmitTarget.a2ui, EmitTarget.widgetbook],
    );
  });

  test('Ignore preserves legacy all-target and accepts const iterables', () {
    expect(ignore.targets, isNull);
    expect(const Ignore().targets, isNull);
    // Explicit null is part of the legacy-compatible API contract.
    // ignore: avoid_redundant_argument_values
    expect(const Ignore(null).targets, isNull);
    expect(const Ignore(targetAlias).targets, same(targetAlias));
    expect(
      const Ignore({EmitTarget.rfw, EmitTarget.widgetbook}).targets,
      {EmitTarget.rfw, EmitTarget.widgetbook},
    );
    expect(const Ignore(<EmitTarget>[]).targets, isEmpty);
    const probe = IgnoreShapeProbe();
    expect(
      [
        probe.legacy,
        probe.legacyConstructor,
        probe.explicitAll,
        probe.alias,
        probe.set,
        probe.empty,
      ],
      everyElement(isEmpty),
    );
  });
}
