import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:restage_codegen/src/surface_publication/recorded_layouts.dart';
import 'package:test/test.dart';

// The facts of [build], a build whose records are marked: `v(key, x)` a
// value, `items(key, x)` a list, `isl(name, x)` an island and
// `b(key, index, x)` a recorded return. The marks are removed, so each fact
// names the app's own node `x`. A site inside `helper`'s body is reached
// through each call of `helper` in the build.
RecordedBuild _facts(String build) {
  const marks = {'v', 'items', 'isl', 'b'};
  final marked = <MethodInvocation>[];
  parseString(
    content: build,
    throwIfDiagnostics: false,
  ).unit.accept(_Calls(marked));
  final records = [
    for (final call in marked)
      if (marks.contains(call.methodName.name)) call,
  ];
  // Each mark's prefix and suffix, removed from the source.
  final cuts = <(int, int)>[];
  for (final call in records) {
    final inner = call.argumentList.arguments.last;
    cuts
      ..add((call.offset, inner.offset))
      ..add((inner.end, call.end));
  }
  int moved(int offset) => cuts.fold(
    offset,
    (at, cut) => cut.$2 <= offset
        ? at - (cut.$2 - cut.$1)
        : cut.$1 < offset
        ? at - (offset - cut.$1)
        : at,
  );
  final buffer = StringBuffer();
  for (var i = 0; i < build.length; i++) {
    if (!cuts.any((cut) => cut.$1 <= i && i < cut.$2)) buffer.write(build[i]);
  }
  final unit = parseString(
    content: buffer.toString(),
    throwIfDiagnostics: false,
  ).unit;
  final nodes = <AstNode>[];
  unit.accept(_Nodes(nodes));
  AstNode at(int start, int end) =>
      nodes.firstWhere((node) => node.offset == start && node.end == end);
  final bodies = <String, FunctionBody>{
    for (final declaration
        in unit.declarations.whereType<FunctionDeclaration>())
      declaration.name.lexeme: declaration.functionExpression.body,
    for (final type in unit.declarations.whereType<ClassDeclaration>())
      for (final method in type.body.members.whereType<MethodDeclaration>())
        method.name.lexeme: method.body,
  };
  final body = bodies['build']!;
  final calls = <MethodInvocation>[];
  unit.accept(_Calls(calls));
  final helperCalls = [
    for (final call in calls)
      if (call.methodName.name == 'helper' &&
          call.offset >= body.offset &&
          call.end <= body.end)
        call,
  ];
  final sites = <RecordedSite>[];
  final returns = <RecordedReturn>[];
  for (final call in records) {
    final arguments = call.argumentList.arguments;
    final key = (arguments.first as SimpleStringLiteral).value;
    final inner = arguments.last;
    final node = at(moved(inner.offset), moved(inner.end));
    if (call.methodName.name == 'b') {
      returns.add(
        RecordedReturn(
          key: key,
          index: (arguments[1] as IntegerLiteral).value!,
          node: node,
        ),
      );
      continue;
    }
    final kind = switch (call.methodName.name) {
      'v' => RecordedSiteKind.value,
      'items' => RecordedSiteKind.items,
      _ => RecordedSiteKind.island,
    };
    final inBuild = node.offset >= body.offset && node.end <= body.end;
    for (final chain
        in inBuild
            ? [<AstNode>[]]
            : [
                for (final c in helperCalls) [c],
              ]) {
      sites.add(RecordedSite(kind: kind, key: key, node: node, calls: chain));
    }
  }
  return RecordedBuild(body: body, sites: sites, returns: returns);
}

// Every node, outermost first.
final class _Nodes extends GeneralizingAstVisitor<void> {
  _Nodes(this.nodes);
  final List<AstNode> nodes;
  @override
  void visitNode(AstNode node) {
    nodes.add(node);
    super.visitNode(node);
  }
}

final class _Calls extends RecursiveAstVisitor<void> {
  _Calls(this.calls);
  final List<MethodInvocation> calls;
  @override
  void visitMethodInvocation(MethodInvocation node) {
    calls.add(node);
    super.visitMethodInvocation(node);
  }
}

// The facet without its condition texts.
Map<String, Object?> _layouts(String build) =>
    recordedLayoutsOf(_facts(build)).toJson()..remove('when');

void main() {
  group('recorded layouts', () {
    test('a value after an early return needs the later return', () {
      expect(
        _layouts('''Widget build() {
          if (offer == null) return b('_hB', 0, const Text('none'));
          final title = v('_hT', offer!.title);
          return b('_hB', 1, Text(title));
        }'''),
        {
          'domains': {
            '_hB': [0, 1],
          },
          'values': {
            '_hT': {
              '_hB': [1],
            },
          },
        },
      );
    });

    test('a value before every return needs nothing', () {
      expect(
        _layouts('''Widget build() {
          final title = v('_hT', load());
          if (title.isEmpty) return b('_hB', 0, const Text('none'));
          return b('_hB', 1, Text(title));
        }'''),
        isEmpty,
      );
    });

    test('a case that always returns excludes the returns after it', () {
      expect(
        _layouts('''Widget build() {
          if (offer case final o?) {
            return b('_hB', 0, isl('app.islands:Badge', Badge(v('_hF', o.first))));
          }
          return b('_hB', 1, const Text('none'));
        }'''),
        {
          'domains': {
            '_hB': [0, 1],
          },
          'values': {
            '_hF': {
              '_hB': [0],
            },
          },
          'islands': {
            'app.islands:Badge': {
              '_hB': [0],
            },
          },
        },
      );
    });

    test('a value a try returns may reach the catch return', () {
      expect(
        _layouts('''Widget build() {
          try {
            return b('_hB', 0, Text(v('_hD', describe(offer!))));
          } catch (e) {
            return b('_hB', 1, const Text('error'));
          }
        }'''),
        isEmpty,
      );
    });

    test('conditions and short-circuit parts guard what they hold', () {
      expect(
        _layouts('''Widget build() => Column(children: [
          if (v('_hA', offer != null) && v('_hE', offer!.isNotEmpty))
            Text(v('_hV', offer!)),
          if (v('_hF', flag))
            if (v('_hG', eligible()))
              for (final p in items('_hL', plans())) Text(v('_hN', p.name)),
        ]);'''),
        {
          'domains': {
            '_hA': [false, true],
            '_hE': [false, true],
            '_hF': [false, true],
            '_hG': [false, true],
          },
          'values': {
            '_hE': {
              '_hA': [true],
            },
            '_hG': {
              '_hF': [true],
            },
            '_hL': {
              '_hF': [true],
              '_hG': [true],
            },
            '_hN': {
              '_hF': [true],
              '_hG': [true],
            },
            '_hV': {
              '_hA': [true],
              '_hE': [true],
            },
          },
        },
      );
    });

    test('a statement if and a conditional guard their branches', () {
      expect(
        _layouts('''Widget build() {
          var label = 'none';
          if (v('_hC', flag)) {
            label = v('_hS', compute());
          }
          return Text(v('_hO', other) ? label : v('_hX', fallback()));
        }'''),
        {
          'domains': {
            '_hC': [false, true],
            '_hO': [false, true],
          },
          'values': {
            '_hS': {
              '_hC': [true],
            },
            '_hX': {
              '_hO': [false],
            },
          },
        },
      );
    });

    test('a helper call carries its guard into the helper', () {
      expect(
        _layouts('''
Widget helper(Offer o) => Text(v('_hH', o.title));
Widget build() => Column(children: [
  if (v('_hP', offer != null)) helper(offer!),
]);'''),
        {
          'domains': {
            '_hP': [false, true],
          },
          'values': {
            '_hH': {
              '_hP': [true],
            },
          },
        },
      );
    });

    test('each condition carries its source, plain words and place', () {
      final layouts = recordedLayoutsOf(
        _facts('''
class PlanPicker {
  Widget build() {
    if (offer == null) return b('_hB', 0, const Text('none'));
    return b('_hB', 1, Column(children: [
      if (v('_hT', isTrial)) Text(v('_hN', offer!.name)),
    ]));
  }
}'''),
      ).toJson();
      expect(layouts['build'], 'PlanPicker.build');
      expect(layouts['when'], {
        '_hB': {
          '0': {
            'source': 'offer == null',
            'plain': 'when `offer == null`',
            'location': ':3:9',
          },
          '1': {
            'source': 'offer != null',
            'plain': "when there's an offer",
            'location': ':3:9',
          },
        },
        '_hT': {
          'false': {
            'source': '!isTrial',
            'plain': 'when `!isTrial`',
            'location': ':5:11',
          },
          'true': {
            'source': 'isTrial',
            'plain': 'when `isTrial`',
            'location': ':5:11',
          },
        },
      });
    });
  });
}
