import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

const _library = 'restage.core';
const _at = '2026-05-11T12:00:00Z';
const _by = 'rfw_catalog_compiler@0.1.0';

void main() {
  group('wire ID replay', () {
    test('is deterministic after event-log round trip', () {
      final events = [
        AllocWireIdEvent(
          type: WireIdKind.widget,
          id: WireId('w0001'),
          name: 'Container',
          source: 'package:flutter/src/widgets/container.dart#Container',
          at: _at,
          by: _by,
        ),
        AllocWireIdEvent(
          type: WireIdKind.property,
          id: WireId('p0001'),
          owner: WireId('w0001'),
          name: 'color',
          source: 'package:flutter/src/widgets/container.dart#Container.color',
          at: _at,
          by: _by,
        ),
        AllocWireIdEvent(
          type: WireIdKind.structured,
          id: WireId('s0001'),
          name: 'LinearGradient',
          source: 'package:flutter/src/painting/gradient.dart#LinearGradient',
          at: _at,
          by: _by,
        ),
        AllocWireIdEvent(
          type: WireIdKind.variant,
          id: WireId('v0001'),
          owner: WireId('s0001'),
          sourceKind: VariantSourceKind.constructor,
          source: 'package:flutter/src/painting/gradient.dart#LinearGradient.',
          at: _at,
          by: _by,
        ),
        AllocWireIdEvent(
          type: WireIdKind.union,
          id: WireId('u0001'),
          name: 'Gradient',
          source: 'package:flutter/src/painting/gradient.dart#Gradient',
          at: _at,
          by: _by,
        ),
        AddMemberWireIdEvent(
          target: WireIdRef(library: _library, wireId: WireId('u0001')),
          member: WireIdRef(library: _library, wireId: WireId('s0001')),
          at: _at,
          by: _by,
        ),
        AllocWireIdEvent(
          type: WireIdKind.designToken,
          id: WireId('t0001'),
          name: 'primary',
          tokenType: 'color',
          resolver: const WireIdEventField<Map<String, Object?>?>.value(
            {'path': 'colorScheme.primary'},
          ),
          at: _at,
          by: _by,
        ),
        RenameWireIdEvent(
          type: WireIdKind.widget,
          id: WireId('w0001'),
          from: 'Container',
          to: 'Box',
          source: 'package:flutter/src/widgets/container.dart#Container',
          at: '2026-05-11T12:01:00Z',
          by: _by,
        ),
        UpdateTokenWireIdEvent(
          id: WireId('t0001'),
          stability: const WireIdEventField<String>.value('stable'),
          at: '2026-05-11T12:02:00Z',
          by: _by,
        ),
      ];

      final first = replayWireIdEvents(
        library: _library,
        events: events,
        generatedAt: '2026-05-11T12:03:00Z',
      );
      final second = replayWireIdEvents(
        library: _library,
        events: parseWireIdEventsJsonl(encodeWireIdEventsJsonl(events)),
        generatedAt: '2026-05-11T12:03:00Z',
      );

      expect(
        encodeWireIdCurrentStateJson(second),
        encodeWireIdCurrentStateJson(first),
      );
      expect(first.widgets[WireId('w0001')]!.name, 'Box');
      expect(first.unions[WireId('u0001')]!.members, hasLength(1));
      expect(first.designTokens[WireId('t0001')]!.stability, 'stable');
    });

    test('rejects references that do not resolve to prior allocs', () {
      expect(
        () => replayWireIdEvents(
          library: _library,
          events: [
            AllocWireIdEvent(
              type: WireIdKind.property,
              id: WireId('p0001'),
              owner: WireId('w0001'),
              name: 'color',
              source: 'src#Widget.color',
              at: _at,
              by: _by,
            ),
          ],
        ),
        throwsA(
          isA<WireIdReplayException>().having(
            (error) => error.message,
            'message',
            contains('prior local alloc'),
          ),
        ),
      );
    });

    test('records parameter entries separately from properties', () {
      final state = replayWireIdEvents(
        library: _library,
        events: [
          AllocWireIdEvent(
            type: WireIdKind.structured,
            id: WireId('s0001'),
            name: 'BorderRadius',
            source: 'src#BorderRadius',
            at: _at,
            by: _by,
          ),
          AllocWireIdEvent(
            type: WireIdKind.variant,
            id: WireId('v0001'),
            owner: WireId('s0001'),
            sourceKind: VariantSourceKind.constructor,
            namedConstructor: 'circular',
            source: 'src#BorderRadius.circular',
            at: _at,
            by: _by,
          ),
          AllocWireIdEvent(
            type: WireIdKind.parameter,
            id: WireId('a0001'),
            owner: WireId('v0001'),
            name: 'radius',
            source: 'src#BorderRadius.circular.radius',
            at: _at,
            by: _by,
          ),
        ],
      );

      expect(state.parameters, contains(WireId('a0001')));
      expect(state.properties, isNot(contains(WireId('a0001'))));
      expect(state.resolve(WireId('a0001'))!.owner, WireId('v0001'));
      expect(state.highestSequence(WireIdKind.parameter), 1);
      expect(
        encodeWireIdCurrentStateJson(state),
        contains('"parameters"'),
      );
    });

    test('rejects parameter owners that are not variants', () {
      expect(
        () => replayWireIdEvents(
          library: _library,
          events: [
            AllocWireIdEvent(
              type: WireIdKind.widget,
              id: WireId('w0001'),
              name: 'Box',
              source: 'src#Box',
              at: _at,
              by: _by,
            ),
            AllocWireIdEvent(
              type: WireIdKind.parameter,
              id: WireId('a0001'),
              owner: WireId('w0001'),
              name: 'radius',
              source: 'src#Box.radius',
              at: _at,
              by: _by,
            ),
          ],
        ),
        throwsA(
          isA<WireIdReplayException>().having(
            (error) => error.message,
            'message',
            contains('parameter owner w0001 must be a variant entry'),
          ),
        ),
      );
    });

    test('failed alloc apply does not advance builder state', () {
      final builder = WireIdReplayBuilder(
        library: _library,
        externalStates: const {},
      )..apply(
          AllocWireIdEvent(
            type: WireIdKind.widget,
            id: WireId('w0001'),
            name: 'Container',
            source: 'src#Container',
            at: _at,
            by: _by,
          ),
        );

      expect(
        () => builder.apply(
          AllocWireIdEvent(
            type: WireIdKind.property,
            id: WireId('p0001'),
            owner: WireId('w9999'),
            name: 'color',
            source: 'src#Missing.color',
            at: _at,
            by: _by,
          ),
        ),
        throwsA(
          isA<WireIdReplayException>().having(
            (error) => error.message,
            'message',
            contains('prior local alloc'),
          ),
        ),
      );

      expect(builder.highestSequence(WireIdKind.property), 0);
      expect(builder.contains(WireId('p0001')), isFalse);
      expect(builder.resolve(WireId('p0001')), isNull);

      builder.apply(
        AllocWireIdEvent(
          type: WireIdKind.property,
          id: WireId('p0001'),
          owner: WireId('w0001'),
          name: 'color',
          source: 'src#Container.color',
          at: _at,
          by: _by,
        ),
      );

      expect(builder.highestSequence(WireIdKind.property), 1);
      expect(builder.resolve(WireId('p0001'))!.owner, WireId('w0001'));
    });

    test('failed rename apply does not change label or source', () {
      final builder = WireIdReplayBuilder(
        library: _library,
        externalStates: const {},
      )..apply(
          AllocWireIdEvent(
            type: WireIdKind.widget,
            id: WireId('w0001'),
            name: 'Container',
            source: 'src#Container',
            at: _at,
            by: _by,
          ),
        );

      expect(
        () => builder.apply(
          RenameWireIdEvent(
            type: WireIdKind.widget,
            id: WireId('w0001'),
            from: 'Container',
            to: 'Box',
            source: 'src#Wrong',
            at: '2026-05-11T12:01:00Z',
            by: _by,
          ),
        ),
        throwsA(
          isA<WireIdReplayException>().having(
            (error) => error.message,
            'message',
            contains('source mismatch'),
          ),
        ),
      );

      expect(builder.resolve(WireId('w0001'))!.name, 'Container');
      expect(builder.resolve(WireId('w0001'))!.source, 'src#Container');

      builder.apply(
        RenameWireIdEvent(
          type: WireIdKind.widget,
          id: WireId('w0001'),
          from: 'Container',
          to: 'Box',
          source: 'src#Container',
          at: '2026-05-11T12:02:00Z',
          by: _by,
        ),
      );

      expect(builder.resolve(WireId('w0001'))!.name, 'Box');
    });

    test('source-only rename preserves the wire ID', () {
      final builder = WireIdReplayBuilder(
        library: _library,
        externalStates: const {},
      )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.widget,
            id: WireId('w0001'),
            name: 'StatusPanel',
            source: 'package:acme/old.dart#StatusPanel',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.property,
            id: WireId('p0001'),
            owner: WireId('w0001'),
            name: 'label',
            source: 'package:acme/old.dart#StatusPanel.label',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          RenameWireIdEvent(
            type: WireIdKind.widget,
            id: WireId('w0001'),
            from: 'StatusPanel',
            to: 'StatusPanel',
            fromSource: 'package:acme/old.dart#StatusPanel',
            toSource: 'package:acme/new.dart#StatusPanel',
            cascade: true,
            at: '2026-05-11T12:01:00Z',
            by: _by,
          ),
        );

      final entry = builder.resolve(WireId('w0001'))!;
      expect(entry.id, WireId('w0001'));
      expect(entry.name, 'StatusPanel');
      expect(entry.source, 'package:acme/new.dart#StatusPanel');
      expect(
        builder.resolve(WireId('p0001'))!.source,
        'package:acme/new.dart#StatusPanel.label',
      );
    });

    test('source-only rename rejects a duplicate live widget identity', () {
      final builder = WireIdReplayBuilder(
        library: _library,
        externalStates: const {},
      )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.widget,
            id: WireId('w0001'),
            name: 'StatusPanel',
            source: 'package:acme/old.dart#StatusPanel',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.widget,
            id: WireId('w0002'),
            name: 'StatusPanel',
            source: 'package:acme/new.dart#StatusPanel',
            at: _at,
            by: _by,
          ),
        );

      expect(
        () => builder.apply(
          RenameWireIdEvent(
            type: WireIdKind.widget,
            id: WireId('w0001'),
            from: 'StatusPanel',
            to: 'StatusPanel',
            fromSource: 'package:acme/old.dart#StatusPanel',
            toSource: 'package:acme/new.dart#StatusPanel',
            cascade: true,
            at: '2026-05-11T12:01:00Z',
            by: _by,
          ),
        ),
        throwsA(
          predicate(
            (error) =>
                error is WireIdReplayException &&
                error.toString().contains('duplicate active widget') &&
                error.toString().contains('w0001') &&
                error.toString().contains('w0002'),
          ),
        ),
      );
      expect(
        builder.resolve(WireId('w0001'))!.source,
        'package:acme/old.dart#StatusPanel',
      );
      expect(
        builder.resolve(WireId('w0002'))!.source,
        'package:acme/new.dart#StatusPanel',
      );
    });

    test('source-only unnamed variant rename cascades to parameters', () {
      final builder = WireIdReplayBuilder(
        library: _library,
        externalStates: const {},
      )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.structured,
            id: WireId('s0001'),
            name: 'Palette',
            source: 'package:acme/old.dart#Palette',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.variant,
            id: WireId('v0001'),
            owner: WireId('s0001'),
            sourceKind: VariantSourceKind.constructor,
            source: 'package:acme/old.dart#Palette.',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.parameter,
            id: WireId('a0001'),
            owner: WireId('v0001'),
            name: 'color',
            source: 'package:acme/old.dart#Palette.color',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          RenameWireIdEvent(
            type: WireIdKind.variant,
            id: WireId('v0001'),
            from: '<unnamed>',
            to: '<unnamed>',
            fromSource: 'package:acme/old.dart#Palette.',
            toSource: 'package:acme/new.dart#Palette.',
            cascade: true,
            at: '2026-05-11T12:01:00Z',
            by: _by,
          ),
        );

      final variant = builder.resolve(WireId('v0001'))!;
      expect(variant.namedConstructor, isNull);
      expect(variant.source, 'package:acme/new.dart#Palette.');
      expect(
        builder.resolve(WireId('a0001'))!.source,
        'package:acme/new.dart#Palette.color',
      );
    });

    for (final target in const [
      (
        description: 'malformed target',
        source: 'package:acme/new.dart#MovedPalette',
      ),
      (
        description: 'multi-dot target',
        source: 'package:acme/new.dart#Palette..',
      ),
    ]) {
      test('unnamed variant rename rejects a ${target.description} atomically',
          () {
        final builder = WireIdReplayBuilder(
          library: _library,
          externalStates: const {},
        )
          ..apply(
            AllocWireIdEvent(
              type: WireIdKind.structured,
              id: WireId('s0001'),
              name: 'Palette',
              source: 'package:acme/old.dart#Palette',
              at: _at,
              by: _by,
            ),
          )
          ..apply(
            AllocWireIdEvent(
              type: WireIdKind.variant,
              id: WireId('v0001'),
              owner: WireId('s0001'),
              sourceKind: VariantSourceKind.constructor,
              source: 'package:acme/old.dart#Palette.',
              at: _at,
              by: _by,
            ),
          )
          ..apply(
            AllocWireIdEvent(
              type: WireIdKind.parameter,
              id: WireId('a0001'),
              owner: WireId('v0001'),
              name: 'color',
              source: 'package:acme/old.dart#Palette.color',
              at: _at,
              by: _by,
            ),
          );

        expect(
          () => builder.apply(
            RenameWireIdEvent(
              type: WireIdKind.variant,
              id: WireId('v0001'),
              from: '<unnamed>',
              to: '<unnamed>',
              fromSource: 'package:acme/old.dart#Palette.',
              toSource: target.source,
              cascade: true,
              at: '2026-05-11T12:01:00Z',
              by: _by,
            ),
          ),
          throwsA(
            predicate(
              (error) =>
                  error is WireIdReplayException &&
                  error.toString().contains(
                        'unnamed constructor source must end in exactly one .',
                      ),
            ),
          ),
        );
        expect(
          builder.resolve(WireId('v0001'))!.source,
          'package:acme/old.dart#Palette.',
        );
        expect(
          builder.resolve(WireId('a0001'))!.source,
          'package:acme/old.dart#Palette.color',
        );
      });
    }

    test('named variant rename to unnamed keeps one source delimiter', () {
      final builder = WireIdReplayBuilder(
        library: _library,
        externalStates: const {},
      )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.structured,
            id: WireId('s0001'),
            name: 'Palette',
            source: 'package:acme/old.dart#Palette',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.variant,
            id: WireId('v0001'),
            owner: WireId('s0001'),
            sourceKind: VariantSourceKind.constructor,
            namedConstructor: 'fromColor',
            source: 'package:acme/old.dart#Palette.fromColor',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.parameter,
            id: WireId('a0001'),
            owner: WireId('v0001'),
            name: 'color',
            source: 'package:acme/old.dart#Palette.fromColor.color',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          RenameWireIdEvent(
            type: WireIdKind.variant,
            id: WireId('v0001'),
            from: 'fromColor',
            to: '<unnamed>',
            fromSource: 'package:acme/old.dart#Palette.fromColor',
            toSource: 'package:acme/new.dart#Palette.',
            cascade: true,
            at: '2026-05-11T12:01:00Z',
            by: _by,
          ),
        );

      final variant = builder.resolve(WireId('v0001'))!;
      expect(variant.namedConstructor, isNull);
      expect(variant.source, 'package:acme/new.dart#Palette.');
      expect(
        builder.resolve(WireId('a0001'))!.source,
        'package:acme/new.dart#Palette.color',
      );
    });

    test('unnamed variant rename to named keeps one source delimiter', () {
      final builder = WireIdReplayBuilder(
        library: _library,
        externalStates: const {},
      )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.structured,
            id: WireId('s0001'),
            name: 'Palette',
            source: 'package:acme/old.dart#Palette',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.variant,
            id: WireId('v0001'),
            owner: WireId('s0001'),
            sourceKind: VariantSourceKind.constructor,
            source: 'package:acme/old.dart#Palette.',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.parameter,
            id: WireId('a0001'),
            owner: WireId('v0001'),
            name: 'color',
            source: 'package:acme/old.dart#Palette.color',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          RenameWireIdEvent(
            type: WireIdKind.variant,
            id: WireId('v0001'),
            from: '<unnamed>',
            to: 'fromColor',
            fromSource: 'package:acme/old.dart#Palette.',
            toSource: 'package:acme/new.dart#Palette.fromColor',
            cascade: true,
            at: '2026-05-11T12:01:00Z',
            by: _by,
          ),
        );

      final variant = builder.resolve(WireId('v0001'))!;
      expect(variant.namedConstructor, 'fromColor');
      expect(variant.source, 'package:acme/new.dart#Palette.fromColor');
      expect(
        builder.resolve(WireId('a0001'))!.source,
        'package:acme/new.dart#Palette.fromColor.color',
      );
    });

    test('later cascade prefers the most specific legacy source prefix', () {
      final builder = WireIdReplayBuilder(
        library: _library,
        externalStates: const {},
      )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.structured,
            id: WireId('s0001'),
            name: 'Palette',
            source: 'package:acme/palette.dart#Palette',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.variant,
            id: WireId('v0001'),
            owner: WireId('s0001'),
            sourceKind: VariantSourceKind.constructor,
            namedConstructor: 'fromColor',
            source: 'package:acme/palette.dart#Palette.fromColor',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.parameter,
            id: WireId('a0001'),
            owner: WireId('v0001'),
            name: 'color',
            source: 'package:acme/palette.dart#Palette.fromColor.color',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          RenameWireIdEvent(
            type: WireIdKind.variant,
            id: WireId('v0001'),
            from: 'fromColor',
            to: '<unnamed>',
            fromSource: 'package:acme/palette.dart#Palette.fromColor',
            toSource: 'package:acme/palette.dart#Palette.',
            at: '2026-05-11T12:01:00Z',
            by: _by,
          ),
        )
        ..apply(
          RenameWireIdEvent(
            type: WireIdKind.variant,
            id: WireId('v0001'),
            from: '<unnamed>',
            to: '<unnamed>',
            fromSource: 'package:acme/palette.dart#Palette.',
            toSource: 'package:acme/new.dart#NewPalette.',
            cascade: true,
            at: '2026-05-11T12:02:00Z',
            by: _by,
          ),
        );

      expect(
        builder.resolve(WireId('a0001'))!.source,
        'package:acme/new.dart#NewPalette.color',
      );
    });

    test('source rename does not move descendants unless cascade is set', () {
      final builder = WireIdReplayBuilder(
        library: _library,
        externalStates: const {},
      )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.widget,
            id: WireId('w0001'),
            name: 'StatusPanel',
            source: 'package:acme/old.dart#StatusPanel',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.property,
            id: WireId('p0001'),
            owner: WireId('w0001'),
            name: 'label',
            source: 'package:acme/old.dart#StatusPanel.label',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          RenameWireIdEvent(
            type: WireIdKind.widget,
            id: WireId('w0001'),
            from: 'StatusPanel',
            to: 'StatusPanel',
            fromSource: 'package:acme/old.dart#StatusPanel',
            toSource: 'package:acme/new.dart#StatusPanel',
            at: '2026-05-11T12:01:00Z',
            by: _by,
          ),
        );

      expect(
        builder.resolve(WireId('p0001'))!.source,
        'package:acme/old.dart#StatusPanel.label',
      );
    });

    test('a later cascade moves descendants left under a legacy source', () {
      final builder = WireIdReplayBuilder(
        library: _library,
        externalStates: const {},
      )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.widget,
            id: WireId('w0001'),
            name: 'StatusPanel',
            source: 'package:acme/old.dart#StatusPanel',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.property,
            id: WireId('p0001'),
            owner: WireId('w0001'),
            name: 'label',
            source: 'package:acme/old.dart#StatusPanel.label',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          RenameWireIdEvent(
            type: WireIdKind.widget,
            id: WireId('w0001'),
            from: 'StatusPanel',
            to: 'StatusPanel',
            fromSource: 'package:acme/old.dart#StatusPanel',
            toSource: 'package:acme/mid.dart#StatusPanel',
            at: '2026-05-11T12:01:00Z',
            by: _by,
          ),
        )
        ..apply(
          RenameWireIdEvent(
            type: WireIdKind.widget,
            id: WireId('w0001'),
            from: 'StatusPanel',
            to: 'StatusPanel',
            fromSource: 'package:acme/mid.dart#StatusPanel',
            toSource: 'package:acme/new.dart#StatusPanel',
            cascade: true,
            at: '2026-05-11T12:02:00Z',
            by: _by,
          ),
        );

      expect(
        builder.resolve(WireId('p0001'))!.source,
        'package:acme/new.dart#StatusPanel.label',
      );
    });

    test('a later cascade rejects duplicate live descendant identities', () {
      final builder = WireIdReplayBuilder(
        library: _library,
        externalStates: const {},
      )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.widget,
            id: WireId('w0001'),
            name: 'StatusPanel',
            source: 'package:acme/old.dart#StatusPanel',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.property,
            id: WireId('p0001'),
            owner: WireId('w0001'),
            name: 'label',
            source: 'package:acme/old.dart#StatusPanel.label',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          RenameWireIdEvent(
            type: WireIdKind.widget,
            id: WireId('w0001'),
            from: 'StatusPanel',
            to: 'StatusPanel',
            fromSource: 'package:acme/old.dart#StatusPanel',
            toSource: 'package:acme/mid.dart#StatusPanel',
            at: '2026-05-11T12:01:00Z',
            by: _by,
          ),
        )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.property,
            id: WireId('p0002'),
            owner: WireId('w0001'),
            name: 'label',
            source: 'package:acme/mid.dart#StatusPanel.label',
            at: '2026-05-11T12:02:00Z',
            by: _by,
          ),
        );

      expect(
        () => builder.apply(
          RenameWireIdEvent(
            type: WireIdKind.widget,
            id: WireId('w0001'),
            from: 'StatusPanel',
            to: 'StatusPanel',
            fromSource: 'package:acme/mid.dart#StatusPanel',
            toSource: 'package:acme/new.dart#StatusPanel',
            cascade: true,
            at: '2026-05-11T12:03:00Z',
            by: _by,
          ),
        ),
        throwsA(
          predicate(
            (error) =>
                error is WireIdReplayException &&
                error.toString().contains('duplicate active descendant') &&
                error.toString().contains('p0001') &&
                error.toString().contains('p0002'),
          ),
        ),
      );
      expect(
        builder.resolve(WireId('w0001'))!.source,
        'package:acme/mid.dart#StatusPanel',
      );
      expect(
        builder.resolve(WireId('p0001'))!.source,
        'package:acme/old.dart#StatusPanel.label',
      );
      expect(
        builder.resolve(WireId('p0002'))!.source,
        'package:acme/mid.dart#StatusPanel.label',
      );
    });

    test('cascade only moves descendants owned by the renamed entry', () {
      final builder = WireIdReplayBuilder(
        library: _library,
        externalStates: const {},
      )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.widget,
            id: WireId('w0001'),
            name: 'StatusPanel',
            source: 'package:acme/old.dart#StatusPanel',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.property,
            id: WireId('p0001'),
            owner: WireId('w0001'),
            name: 'label',
            source: 'package:acme/old.dart#StatusPanel.label',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.widget,
            id: WireId('w0002'),
            name: 'OtherPanel',
            source: 'package:acme/other.dart#OtherPanel',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.property,
            id: WireId('p0002'),
            owner: WireId('w0002'),
            name: 'misleading',
            source: 'package:acme/old.dart#StatusPanel.misleading',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          RenameWireIdEvent(
            type: WireIdKind.widget,
            id: WireId('w0001'),
            from: 'StatusPanel',
            to: 'StatusPanel',
            fromSource: 'package:acme/old.dart#StatusPanel',
            toSource: 'package:acme/new.dart#StatusPanel',
            cascade: true,
            at: '2026-05-11T12:01:00Z',
            by: _by,
          ),
        );

      expect(
        builder.resolve(WireId('p0001'))!.source,
        'package:acme/new.dart#StatusPanel.label',
      );
      expect(
        builder.resolve(WireId('p0002'))!.source,
        'package:acme/old.dart#StatusPanel.misleading',
      );
    });

    test('a malformed descendant makes cascade failure atomic', () {
      final builder = WireIdReplayBuilder(
        library: _library,
        externalStates: const {},
      )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.widget,
            id: WireId('w0001'),
            name: 'StatusPanel',
            source: 'package:acme/old.dart#StatusPanel',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.property,
            id: WireId('p0001'),
            owner: WireId('w0001'),
            name: 'label',
            source: 'package:acme/old.dart#StatusPanel.label',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.property,
            id: WireId('p0002'),
            owner: WireId('w0001'),
            name: 'broken',
            source: 'package:acme/unrelated.dart#Broken.value',
            at: _at,
            by: _by,
          ),
        );

      expect(
        () => builder.apply(
          RenameWireIdEvent(
            type: WireIdKind.widget,
            id: WireId('w0001'),
            from: 'StatusPanel',
            to: 'StatusPanel',
            fromSource: 'package:acme/old.dart#StatusPanel',
            toSource: 'package:acme/new.dart#StatusPanel',
            cascade: true,
            at: '2026-05-11T12:01:00Z',
            by: _by,
          ),
        ),
        throwsA(isA<WireIdReplayException>()),
      );
      expect(
        builder.resolve(WireId('w0001'))!.source,
        'package:acme/old.dart#StatusPanel',
      );
      expect(
        builder.resolve(WireId('p0001'))!.source,
        'package:acme/old.dart#StatusPanel.label',
      );
      expect(
        builder.resolve(WireId('p0002'))!.source,
        'package:acme/unrelated.dart#Broken.value',
      );
    });

    test('structured source rename moves fields, variants, and parameters', () {
      final builder = WireIdReplayBuilder(
        library: _library,
        externalStates: const {},
      )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.structured,
            id: WireId('s0001'),
            name: 'OldData',
            source: 'package:acme/data.dart#OldData',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.property,
            id: WireId('p0001'),
            owner: WireId('s0001'),
            name: 'label',
            source: 'package:acme/data.dart#OldData.label',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.variant,
            id: WireId('v0001'),
            owner: WireId('s0001'),
            sourceKind: VariantSourceKind.constructor,
            source: 'package:acme/data.dart#OldData.',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          AllocWireIdEvent(
            type: WireIdKind.parameter,
            id: WireId('a0001'),
            owner: WireId('v0001'),
            name: 'label',
            source: 'package:acme/data.dart#OldData.label',
            at: _at,
            by: _by,
          ),
        )
        ..apply(
          RenameWireIdEvent(
            type: WireIdKind.structured,
            id: WireId('s0001'),
            from: 'OldData',
            to: 'NewData',
            fromSource: 'package:acme/data.dart#OldData',
            toSource: 'package:acme/data.dart#NewData',
            cascade: true,
            at: '2026-05-11T12:01:00Z',
            by: _by,
          ),
        );

      expect(
        builder.resolve(WireId('s0001'))!.source,
        'package:acme/data.dart#NewData',
      );
      expect(
        builder.resolve(WireId('p0001'))!.source,
        'package:acme/data.dart#NewData.label',
      );
      expect(
        builder.resolve(WireId('v0001'))!.source,
        'package:acme/data.dart#NewData.',
      );
      expect(
        builder.resolve(WireId('a0001'))!.source,
        'package:acme/data.dart#NewData.label',
      );
    });

    test('rejects non-monotonic and duplicate allocations', () {
      final first = AllocWireIdEvent(
        type: WireIdKind.widget,
        id: WireId('w0002'),
        name: 'A',
        source: 'src#A',
        at: _at,
        by: _by,
      );

      expect(
        () => replayWireIdEvents(
          library: _library,
          events: [
            first,
            AllocWireIdEvent(
              type: WireIdKind.widget,
              id: WireId('w0001'),
              name: 'B',
              source: 'src#B',
              at: _at,
              by: _by,
            ),
          ],
        ),
        throwsA(isA<WireIdReplayException>()),
      );
      expect(
        () => replayWireIdEvents(
          library: _library,
          events: [
            first,
            AllocWireIdEvent(
              type: WireIdKind.widget,
              id: WireId('w0002'),
              name: 'Again',
              source: 'src#Again',
              at: _at,
              by: _by,
            ),
          ],
        ),
        throwsA(
          isA<WireIdReplayException>().having(
            (error) => error.message,
            'message',
            contains('duplicate alloc'),
          ),
        ),
      );
    });

    test('rejects duplicate membership and owner kind mismatches', () {
      final events = [
        AllocWireIdEvent(
          type: WireIdKind.widget,
          id: WireId('w0001'),
          name: 'Widget',
          source: 'src#Widget',
          at: _at,
          by: _by,
        ),
        AllocWireIdEvent(
          type: WireIdKind.structured,
          id: WireId('s0001'),
          name: 'Shape',
          source: 'src#Shape',
          at: _at,
          by: _by,
        ),
        AllocWireIdEvent(
          type: WireIdKind.union,
          id: WireId('u0001'),
          name: 'ShapeUnion',
          source: 'src#ShapeUnion',
          at: _at,
          by: _by,
        ),
        AddMemberWireIdEvent(
          target: WireIdRef(library: _library, wireId: WireId('u0001')),
          member: WireIdRef(library: _library, wireId: WireId('s0001')),
          at: _at,
          by: _by,
        ),
        AddMemberWireIdEvent(
          target: WireIdRef(library: _library, wireId: WireId('u0001')),
          member: WireIdRef(library: _library, wireId: WireId('s0001')),
          at: _at,
          by: _by,
        ),
      ];

      expect(
        () => replayWireIdEvents(library: _library, events: events),
        throwsA(
          isA<WireIdReplayException>().having(
            (error) => error.message,
            'message',
            contains('duplicate addMember'),
          ),
        ),
      );
      expect(
        () => replayWireIdEvents(
          library: _library,
          events: [
            events.first,
            AllocWireIdEvent(
              type: WireIdKind.variant,
              id: WireId('v0001'),
              owner: WireId('w0001'),
              sourceKind: VariantSourceKind.constructor,
              source: 'src#Widget.variant',
              at: _at,
              by: _by,
            ),
          ],
        ),
        throwsA(
          isA<WireIdReplayException>().having(
            (error) => error.message,
            'message',
            contains('variant owner'),
          ),
        ),
      );
    });

    test('applies valid replace events to both endpoints', () {
      final state = replayWireIdEvents(
        library: _library,
        events: [
          AllocWireIdEvent(
            type: WireIdKind.widget,
            id: WireId('w0001'),
            name: 'OldWidget',
            source: 'src#OldWidget',
            at: _at,
            by: _by,
          ),
          AllocWireIdEvent(
            type: WireIdKind.widget,
            id: WireId('w0002'),
            name: 'NewWidget',
            source: 'src#NewWidget',
            at: _at,
            by: _by,
          ),
          ReplaceWireIdEvent(
            type: WireIdKind.widget,
            from: WireId('w0001'),
            to: WireId('w0002'),
            transition: 'tx0001',
            at: '2026-05-11T12:01:00Z',
            by: _by,
          ),
        ],
      );

      expect(
        state.widgets[WireId('w0001')]!.successor,
        WireIdRef(library: _library, wireId: WireId('w0002')),
      );
      expect(
        state.widgets[WireId('w0002')]!.predecessor,
        WireIdRef(library: _library, wireId: WireId('w0001')),
      );
      expect(
        state.widgets[WireId('w0001')]!.replacementTransition,
        'tx0001',
      );
    });

    test('rejects invalid replace self-links and transitions', () {
      final base = [
        AllocWireIdEvent(
          type: WireIdKind.widget,
          id: WireId('w0001'),
          name: 'OldWidget',
          source: 'src#OldWidget',
          at: _at,
          by: _by,
        ),
        AllocWireIdEvent(
          type: WireIdKind.widget,
          id: WireId('w0002'),
          name: 'NewWidget',
          source: 'src#NewWidget',
          at: _at,
          by: _by,
        ),
      ];

      expect(
        () => replayWireIdEvents(
          library: _library,
          events: [
            ...base,
            ReplaceWireIdEvent(
              type: WireIdKind.widget,
              from: WireId('w0001'),
              to: WireId('w0001'),
              transition: 'tx0001',
              at: '2026-05-11T12:01:00Z',
              by: _by,
            ),
          ],
        ),
        throwsA(
          isA<WireIdReplayException>().having(
            (error) => error.message,
            'message',
            contains('different IDs'),
          ),
        ),
      );
      expect(
        () => replayWireIdEvents(
          library: _library,
          events: [
            ...base,
            ReplaceWireIdEvent(
              type: WireIdKind.widget,
              from: WireId('w0001'),
              to: WireId('w0002'),
              transition: 'tx1',
              at: '2026-05-11T12:01:00Z',
              by: _by,
            ),
          ],
        ),
        throwsA(
          isA<WireIdReplayException>().having(
            (error) => error.message,
            'message',
            contains('transition'),
          ),
        ),
      );
    });

    test('rejects no-op or unresolvable token updates', () {
      final token = AllocWireIdEvent(
        type: WireIdKind.designToken,
        id: WireId('t0001'),
        name: 'primary',
        tokenType: 'color',
        literalFallback: const WireIdEventField<Object?>.value(0xFF000000),
        stability: 'stable',
        at: _at,
        by: _by,
      );

      expect(
        () => replayWireIdEvents(
          library: _library,
          events: [
            token,
            UpdateTokenWireIdEvent(
              id: WireId('t0001'),
              stability: const WireIdEventField<String>.value('stable'),
              at: '2026-05-11T12:01:00Z',
              by: _by,
            ),
          ],
        ),
        throwsA(
          isA<WireIdReplayException>().having(
            (error) => error.message,
            'message',
            contains('must change'),
          ),
        ),
      );
      expect(
        () => replayWireIdEvents(
          library: _library,
          events: [
            token,
            UpdateTokenWireIdEvent(
              id: WireId('t0001'),
              literalFallback: const WireIdEventField<Object?>.value(null),
              at: '2026-05-11T12:01:00Z',
              by: _by,
            ),
          ],
        ),
        throwsA(
          isA<WireIdReplayException>().having(
            (error) => error.message,
            'message',
            contains('unresolvable'),
          ),
        ),
      );
    });
  });
}
