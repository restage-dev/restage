import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

const selectedTargets = <EmitTarget>[EmitTarget.a2ui, EmitTarget.widgetbook];

final class TargetRoutingApiProbe {
  const TargetRoutingApiProbe({
    @Ignore(selectedTargets) this.localOnly = '',
  });

  final String localOnly;
}

void main() {
  test('the Restage compatibility entrypoint exposes target routing', () {
    expect(selectedTargets, [EmitTarget.a2ui, EmitTarget.widgetbook]);
    expect(ignore.targets, isNull);
    expect(const Ignore(selectedTargets).targets, same(selectedTargets));
    expect(const TargetRoutingApiProbe(), isA<TargetRoutingApiProbe>());
  });
}
