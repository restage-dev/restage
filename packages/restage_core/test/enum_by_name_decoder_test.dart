import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/rfw.dart';

enum LabelTier {
  starter;

  @override
  String toString() => 'Tier $name';
}

enum DottedTier {
  starter;

  @override
  String toString() => 'display.${name.toUpperCase()}';
}

/// A `toString()` reached through a MIXIN rather than declared on the enum.
///
/// This is what makes the failure ordinary rather than exotic: a shared
/// `Numbered` / `Labelled` mixin applied across a family of enums is a normal
/// pattern, and every enum that applies one inherits the trigger without a
/// single override written on the enum itself.
mixin Numbered on Enum {
  @override
  String toString() => '$index';
}

enum MixedTier with Numbered { starter, premium }

enum PlainTier { starter, premium }

enum CollidingTier {
  starter,
  premium;

  @override
  String toString() => 'shared label';
}

void main() {
  group('RestageDecoders.enumByName', () {
    test('decodes declared names when toString has another spelling', () {
      final source = _MapDataSource({
        'label': 'starter',
        'dotted': 'starter',
      });

      expect(
        RestageDecoders.enumByName(
          LabelTier.values,
          source,
          const ['label'],
        ),
        LabelTier.starter,
      );
      expect(
        RestageDecoders.enumByName(
          DottedTier.values,
          source,
          const ['dotted'],
        ),
        DottedTier.starter,
      );
    });

    test('a toString reached through a MIXIN is refused too', () {
      // What this adds over its neighbours: they all declare `toString()` ON
      // the enum, so together they only pin "an author who overrode it". Here
      // the enum overrides nothing — the spelling arrives through an applied
      // mixin, which is how a family of enums picks this up wholesale.
      //
      // The decoder is indifferent to WHERE `toString()` came from because it
      // never consults it; it reads the declared name through the extension.
      // That indifference is the thing under test, and it stops being true the
      // moment anyone reaches for `toString()` as a fallback.
      final source = _MapDataSource({
        'declared': 'starter',
        'viaMixin': '0',
      });

      expect(
        RestageDecoders.enumByName(
          MixedTier.values,
          source,
          const ['declared'],
        ),
        MixedTier.starter,
      );
      // The accepting direction, and the reason this case matters most: under
      // the previous decoder `'0'` resolved to a real member while `'starter'`
      // resolved to nothing — the two failures exactly inverted.
      expect(
        RestageDecoders.enumByName(
          MixedTier.values,
          source,
          const ['viaMixin'],
        ),
        isNull,
      );
    });

    test('rejects toString spellings that are not declared names', () {
      final source = _MapDataSource({
        'label': 'Tier starter',
        'dotted': 'display.STARTER',
      });

      expect(
        RestageDecoders.enumByName(
          LabelTier.values,
          source,
          const ['label'],
        ),
        isNull,
      );
      expect(
        RestageDecoders.enumByName(
          DottedTier.values,
          source,
          const ['dotted'],
        ),
        isNull,
      );
    });

    test('ordinary enums retain declared-name behavior', () {
      // CONTROL: This path already behaved correctly and must stay green
      // through the change; its green is not coverage of the fix.
      final source = _MapDataSource({
        'declared': 'premium',
        'qualified': 'PlainTier.premium',
        'bogus': 'totally.bogus',
      });

      expect(
        RestageDecoders.enumByName(
          PlainTier.values,
          source,
          const ['declared'],
        ),
        PlainTier.premium,
      );
      expect(
        RestageDecoders.enumByName(
          PlainTier.values,
          source,
          const ['qualified'],
        ),
        isNull,
      );
      expect(
        RestageDecoders.enumByName(
          PlainTier.values,
          source,
          const ['bogus'],
        ),
        isNull,
      );
    });

    test('members with colliding toString values resolve independently', () {
      expect(
        CollidingTier.starter.toString(),
        CollidingTier.premium.toString(),
      );
      final source = _MapDataSource({
        'starter': 'starter',
        'premium': 'premium',
      });

      expect(
        RestageDecoders.enumByName(
          CollidingTier.values,
          source,
          const ['starter'],
        ),
        CollidingTier.starter,
      );
      expect(
        RestageDecoders.enumByName(
          CollidingTier.values,
          source,
          const ['premium'],
        ),
        CollidingTier.premium,
      );
    });

    test('returns null for absent and non-string values', () {
      // Also a control, and it stays green under the previous decoder too: the
      // null contract is what lets every call site keep its own `??` — a
      // default, or a throw. Its green does not discriminate this change; it
      // pins that the change did not quietly convert a miss into a throw.
      final source = _MapDataSource({'nonString': 1});

      expect(
        RestageDecoders.enumByName(
          PlainTier.values,
          source,
          const ['missing'],
        ),
        isNull,
      );
      expect(
        RestageDecoders.enumByName(
          PlainTier.values,
          source,
          const ['nonString'],
        ),
        isNull,
      );
    });
  });
}

final class _MapDataSource implements DataSource {
  const _MapDataSource(this.root);

  final Object? root;

  @override
  T? v<T extends Object>(List<Object> argsKey) {
    final value = _lookup(argsKey);
    return value is T ? value : null;
  }

  @override
  bool isList(List<Object> argsKey) => _lookup(argsKey) is List<Object?>;

  @override
  int length(List<Object> argsKey) {
    final value = _lookup(argsKey);
    return value is List<Object?> ? value.length : 0;
  }

  @override
  bool isMap(List<Object> argsKey) => _lookup(argsKey) is Map<String, Object?>;

  @override
  Widget child(List<Object> argsKey) => ErrorWidget('missing child');

  @override
  List<Widget> childList(List<Object> argsKey) => const [];

  @override
  Widget builder(List<Object> argsKey, DynamicMap builderArg) =>
      ErrorWidget('missing builder');

  @override
  T? handler<T extends Function>(
    List<Object> argsKey,
    HandlerGenerator<T> generator,
  ) =>
      null;

  @override
  Widget? optionalBuilder(List<Object> argsKey, DynamicMap builderArg) => null;

  @override
  Widget? optionalChild(List<Object> argsKey) => null;

  @override
  VoidCallback? voidHandler(
    List<Object> argsKey, [
    DynamicMap? extraArguments,
  ]) =>
      null;

  Object? _lookup(List<Object> path) {
    Object? current = root;
    for (final segment in path) {
      if (current is Map<String, Object?> && segment is String) {
        current = current[segment];
      } else if (current is List<Object?> && segment is int) {
        if (segment < 0 || segment >= current.length) return null;
        current = current[segment];
      } else {
        return null;
      }
    }
    return current;
  }
}
