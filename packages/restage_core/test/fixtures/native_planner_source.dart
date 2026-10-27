import 'package:flutter/material.dart' as f;
import 'package:restage_core/restage_core.dart' as r;
import 'package:restage_shared/restage_shared.dart' as s;

part 'native_planner_source.g.dart';

f.ObjectKey Function(f.TapDownDetails) authoredClosure(
        List<Object> items, int count, void Function(f.TapDownDetails) seen) =>
    (f.TapDownDetails details) {
      seen(details);
      return f.ObjectKey(items[count++]);
    };

f.ObjectKey authoredKey(List<Object> items, int index) =>
    f.ObjectKey(items[index]);

f.MaterialColor authoredColor(Map<int, f.Color> swatch) =>
    f.MaterialColor(0xff102030, swatch);

f.MaterialColor authoredConstant() =>
    const f.MaterialColor(0xff102030, {500: f.Color(0xff102030)});

f.ObjectKey Function() authoredReassign(Object value, Object replacement) =>
    () {
      final old = value;
      value = replacement;
      return f.ObjectKey(old);
    };

f.ObjectKey? authoredNullable(Object? model) =>
    model == null ? null : f.ObjectKey(model);

int answer() => -1;

class NativePlannerStatics {
  static const constant = 1;
  static final field = 2;
  static int get getter => 3;
  static int answer() => 4;
  int Function() x() => () {
        final tearoff = answer;
        return constant + field + getter + answer() + tearoff();
      };
}

String Function() authoredInterpolation(int count) =>
    () => 'count:$count:${count++}';

f.Color authoredSelectColor(bool flag, f.MaterialColor color) =>
    flag ? color : f.Colors.red;
f.Color authoredCoalesceColor(f.Color? optional) => optional ?? f.Colors.red;
f.Key authoredSelectKey(bool flag, f.Key key) =>
    flag ? key : const f.ValueKey<String>('fallback');

void Function() authoredSelectCallback(
        bool flag, void Function() first, void Function() second) =>
    flag ? first : second;
