import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

/// Guards the compatibility promise the 2.0 rename makes: every host-widget
/// name that existed at 1.x still resolves, and still names the type it was
/// renamed to.
///
/// The guard is deliberately a *compile-time* reference. A deleted or
/// re-pointed alias stops this file compiling, which is the failure the
/// promise is about — a runtime assertion could not see it, and neither could
/// a test that merely mentions the new names. Before this file existed no test
/// referenced any of these four spellings at all, so an alias could have been
/// dropped with every suite still green.
void main() {
  test('1.x host widget spellings still name their 2.0 types', () {
    // ignore: deprecated_member_use_from_same_package
    expect(RestageSurfaceScreen<Object>, RestageScreen<Object>);
    // ignore: deprecated_member_use_from_same_package
    expect(RestageSurfaceFlow<Object>, RestageFlowGraph<Object>);
    // ignore: deprecated_member_use_from_same_package
    expect(RestageSurfaceScreenResolver, RestageScreenResolver);
    // ignore: deprecated_member_use_from_same_package
    expect(RestageSurfaceEventDispatcher, RestageEventDispatcher);
  });

  test('the authored flow base class was not renamed', () {
    // `RestageFlow` is the base a `@FlowGraph` source extends. The 2.0 host
    // widget is `RestageFlowGraph`; naming it `RestageFlow` would have forced
    // this base to move with no alias possible. Asserting they are distinct
    // types is what keeps that decision from being undone by a later rename.
    expect(RestageFlow, isNot(RestageFlowGraph));
  });
}
