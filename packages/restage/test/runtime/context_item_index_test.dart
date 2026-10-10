import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/runtime/context_data.dart';
import 'package:rfw/formats.dart';

class _StaticResolver implements VariantResolver {
  _StaticResolver(this.bytes);
  final Uint8List bytes;
  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      ResolvedVariant(bytes: bytes, surfaceVersion: 'test', paywallId: id);
}

Uint8List _plansPaywall() {
  const source = '''
    import restage.core;
    widget Paywall = Column(children: [
      ...for plan in data.context.plans:
        GestureDetector(
          onTap: event "choose" { plan: plan },
          child: Text(text: plan.__restage_index),
        ),
    ]);
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

void main() {
  setUp(() => Restage.debugReset());

  test('each map element of a context list carries its 1-based position', () {
    final snapshot = ContextSnapshot.of(<String, Object?>{
      'plans': <Object?>[
        <String, Object?>{'id': 'monthly'},
        'loose',
        <String, Object?>{'id': 'annual', kContextItemIndexKey: 'host'},
        null,
        <String, Object?>{'id': 'lifetime'},
      ],
    });
    expect(snapshot.value['plans'], <Object?>[
      <String, Object?>{'id': 'monthly', kContextItemIndexKey: '1'},
      'loose',
      <String, Object?>{'id': 'annual', kContextItemIndexKey: '3'},
      <String, Object?>{'id': 'lifetime', kContextItemIndexKey: '4'},
    ]);
  });

  test('stripping removes the key at any depth and nothing else', () {
    expect(
      withoutContextItemIndexes(<String, Object?>{
        'plan': <String, Object?>{'id': 'a', kContextItemIndexKey: '1'},
        'tags': <Object?>[
          <String, Object?>{'t': 'x', kContextItemIndexKey: '2'},
        ],
        'n': 1,
      }),
      <String, Object?>{
        'plan': <String, Object?>{'id': 'a'},
        'tags': <Object?>[
          <String, Object?>{'t': 'x'},
        ],
        'n': 1,
      },
    );
  });

  testWidgets(
      'a loop over data.context.plans reads each position, and host callbacks '
      'never see the key', (tester) async {
    final received = <RestageEvent>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: _StaticResolver(_plansPaywall()),
          context: const <String, Object?>{
            'plans': <Object?>[
              <String, Object?>{'id': 'monthly'},
              <String, Object?>{'id': 'annual'},
              <String, Object?>{'id': 'lifetime'},
            ],
          },
          onEvent: received.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    await tester.tap(find.text('2'));
    await tester.pump();

    final chosen = received.whereType<PaywallCustomEvent>().single;
    expect(chosen.eventName, 'choose');
    expect(chosen.args, <String, Object?>{
      'plan': <String, Object?>{'id': 'annual'},
    });
  });
}
