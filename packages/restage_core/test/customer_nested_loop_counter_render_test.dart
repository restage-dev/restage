// The VALUE proof for the nested customer-collection loop counters.
//
// The counter-uniqueness assertion lives with the emitter
// (`restage_codegen/test/customer_nested_loop_counter_test.dart`). This test
// exists because that defect throws NOTHING: a shadowed counter re-points an
// enclosing index at the inner loop, the factory compiles, `dart analyze`
// reports no issues on it, and the only symptom is a wrong VALUE reconstructed
// from a correct payload. So this asserts the rebuilt map itself.
//
// [buildBoardMap] and [buildBoardListControl] are VERBATIM emitter output for
// the two shapes below, with only the `s0.` import alias stripped so the local
// stand-in data classes bind. Re-paste them if the emitter's shape changes.
//
//   MAP     — `Map<String, Row> rows`, where `Row` holds `List<Cell> cells`
//   CONTROL — `List<Row> rows`, the path that already threaded its depth
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rfw/rfw.dart';

class Cell {
  const Cell({required this.label});

  final String label;

  @override
  String toString() => label;
}

class Row {
  const Row({required this.cells});

  final List<Cell> cells;

  @override
  String toString() => cells.toString();
}

Map<String, Row> buildBoardMap(DataSource source) {
  return source.isList(<Object>['rows'])
      ? () {
          final m0 = <String, Row>{};
          for (var i0 = 0; i0 < source.length(<Object>['rows']); i0++) {
            if (!source.isMap(<Object>['rows', i0])) {
              throw ArgumentError('Board.rows entry must be an object.');
            }
            final k0 = source.v<String>(<Object>['rows', i0, 'key']) ??
                (throw ArgumentError('Board.rows entry key is required.'));
            if (m0.containsKey(k0)) {
              throw ArgumentError('Board.rows has a duplicate key.');
            }
            m0[k0] = source.isMap(<Object>['rows', i0, 'value'])
                ? Row(
                    cells: source.isList(<Object>['rows', i0, 'value', 'cells'])
                        ? [
                            for (var i1 = 0;
                                i1 <
                                    source.length(
                                        <Object>['rows', i0, 'value', 'cells']);
                                i1++)
                              source.isMap(<Object>[
                                'rows',
                                i0,
                                'value',
                                'cells',
                                i1
                              ])
                                  ? Cell(
                                      label: source.v<String>(<Object>[
                                            'rows',
                                            i0,
                                            'value',
                                            'cells',
                                            i1,
                                            'label'
                                          ]) ??
                                          (throw ArgumentError(
                                              'Cell.label is required.')))
                                  : (throw ArgumentError(
                                      'Row.cells element must be an object.'))
                          ]
                        : (throw ArgumentError('Row.cells is required.')))
                : (throw ArgumentError('Board.rows entry value is required.'));
          }
          return m0;
        }()
      : (throw ArgumentError('Board.rows is required.'));
}

List<Row> buildBoardListControl(DataSource source) {
  return source.isList(<Object>['rows'])
      ? [
          for (var i0 = 0; i0 < source.length(<Object>['rows']); i0++)
            source.isMap(<Object>['rows', i0])
                ? Row(
                    cells: source.isList(<Object>['rows', i0, 'cells'])
                        ? [
                            for (var i1 = 0;
                                i1 <
                                    source
                                        .length(<Object>['rows', i0, 'cells']);
                                i1++)
                              source.isMap(<Object>['rows', i0, 'cells', i1])
                                  ? Cell(
                                      label: source.v<String>(<Object>[
                                            'rows',
                                            i0,
                                            'cells',
                                            i1,
                                            'label'
                                          ]) ??
                                          (throw ArgumentError(
                                              'Cell.label is required.')))
                                  : (throw ArgumentError(
                                      'Row.cells element must be an object.'))
                          ]
                        : (throw ArgumentError('Row.cells is required.')))
                : (throw ArgumentError('Board.rows element must be an object.'))
        ]
      : (throw ArgumentError('Board.rows is required.'));
}

Map<String, Object?> _cell(String label) => <String, Object?>{'label': label};

void main() {
  test('a map value rebuilds ITS OWN entry, not a neighbour\'s', () {
    // Two entries with distinguishable cells, so reading the wrong entry shows
    // up as wrong TEXT rather than as an exception — the shadowed emitter
    // returned `{A: [A0, B1], B: [A0, B1]}` here and threw nothing.
    final source = _MapDataSource(<String, Object?>{
      'rows': <Object?>[
        <String, Object?>{
          'key': 'A',
          'value': <String, Object?>{
            'cells': <Object?>[_cell('A0'), _cell('A1'), _cell('A2')],
          },
        },
        <String, Object?>{
          'key': 'B',
          'value': <String, Object?>{
            'cells': <Object?>[_cell('B0'), _cell('B1'), _cell('B2')],
          },
        },
      ],
    });

    expect(
      buildBoardMap(source).toString(),
      '{A: [A0, A1, A2], B: [B0, B1, B2]}',
    );
  });

  test('CONTROL: the nested-list path stays exact', () {
    final source = _MapDataSource(<String, Object?>{
      'rows': <Object?>[
        <String, Object?>{
          'cells': <Object?>[_cell('A0'), _cell('A1'), _cell('A2')],
        },
        <String, Object?>{
          'cells': <Object?>[_cell('B0'), _cell('B1'), _cell('B2')],
        },
      ],
    });

    expect(
      buildBoardListControl(source).toString(),
      '[[A0, A1, A2], [B0, B1, B2]]',
    );
  });
}

/// A [DataSource] over a plain decoded wire map — the reconstruction reads
/// only `isList` / `isMap` / `length` / `v`.
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

  Object? _lookup(List<Object> argsKey) {
    Object? current = root;
    for (final key in argsKey) {
      if (key is int) {
        if (current is! List<Object?> || key < 0 || key >= current.length) {
          return null;
        }
        current = current[key];
      } else {
        if (current is! Map<String, Object?>) return null;
        current = current[key];
      }
    }
    return current;
  }
}
