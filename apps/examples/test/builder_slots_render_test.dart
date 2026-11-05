import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/surfaces/builder_slots.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/restage_shared.dart' show RestageBundleCodec;
import 'package:rfw/formats.dart' show encodeLibraryBlob, parseLibraryFile;
import 'package:rfw/rfw.dart' show RemoteWidget;

import '_support/support_directory_channel.dart';

final class _Resolver implements VariantResolver {
  const _Resolver(this.bytes);

  final Uint8List? bytes;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    final design = bytes;
    if (design == null) {
      throw const RestagePaywallError(
          code: RestageErrorCodes.deliveryUnavailable, message: 'No design');
    }
    return ResolvedVariant(
      bytes: design,
      surfaceVersion: '1',
      paywallId: id,
      paywallPublishedVersion: 1,
    );
  }
}

const _blue = Color(0xFF2266AA);
const _red = Color(0xFFAA2222);

const _bundle = 'assets/restage/bundles/lib/surfaces/builder_slots.rsbundle';

String _design(String id) => String.fromCharCodes(
      RestageBundleCodec.decode(File(_bundle).readAsBytesSync())
          .entries
          .singleWhere(
              (entry) => entry.logicalPath == 'assets/paywalls/$id.rfwtxt')
          .bytes,
    );

Uint8List _blob(String text) =>
    Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(text)));

List<String?> _texts(WidgetTester tester) => [
      for (final element in find.byType(Text).evaluate())
        (element.widget as Text).data ??
            (element.widget as Text).textSpan?.toPlainText(),
    ];

final class _Switchable implements VariantResolver {
  _Switchable(this.bytes);

  // The design the next load delivers; none falls back.
  Uint8List? bytes;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) =>
      _Resolver(bytes).resolve(id, placementId: placementId, locale: locale);
}

// Shows [surface] on its fallback, runs [before], then reloads it onto the
// design of [id].
Future<void> _flip(
    WidgetTester tester, String id, Widget Function(VariantResolver) surface,
    {Future<void> Function()? before}) async {
  final resolver = _Switchable(null);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: surface(resolver))));
  await tester.pump();
  await before?.call();
  expect(find.byType(RemoteWidget), findsNothing);
  resolver.bytes = _blob(_design(id));
  // Frames without elapsed time, so an animation stays where it was.
  final reload = Restage.reloadSurfaces();
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump();
  }
  await reload;
  for (var frame = 0;
      frame < 20 && find.byType(RemoteWidget).evaluate().isEmpty;
      frame++) {
    await tester.pump();
  }
  expect(tester.takeException(), isNull);
  expect(find.byType(RemoteWidget), findsOneWidget);
}

void main() {
  useSupportDirectoryChannel();

  setUp(() async {
    await Restage.debugResetAndWait();
    Restage.configure(apiKey: 'rs_pk_test', resolver: const _Resolver(null));
    slotCount.value = 1;
    slotPlan.value =
        const SlotPlan('Monthly', 9, SlotTier.basic, ['Sync'], _blue);
  });

  // The app's widget, the delivered design and the fallback show the same
  // texts, before and after the builder's value changes.
  for (final (id, surface, original, delivered, change, before, after) in <(
    String,
    Widget,
    Widget,
    bool,
    void Function(),
    List<String>,
    List<String>
  )>[
    (
      'slot_count',
      SlotCountSurface(resolver: _Resolver(_blob(_design('slot_count')))),
      const SlotCount(),
      true,
      () => slotCount.value = 2,
      ['header', 'count 1'],
      ['header', 'count 2'],
    ),
    (
      'slot_plan',
      SlotPlanCardSurface(resolver: _Resolver(_blob(_design('slot_plan')))),
      const SlotPlanCard(),
      true,
      () => slotPlan.value =
          const SlotPlan('Yearly', 79, SlotTier.pro, ['Sync', 'Share'], _red),
      ['plans', 'Monthly 9 basic', '1 features'],
      ['plans', 'Yearly 79 pro', '2 features'],
    ),
    (
      'slot_mixed',
      SlotMixedSurface(
          label: 'seats', resolver: _Resolver(_blob(_design('slot_mixed')))),
      const SlotMixed(label: 'seats'),
      true,
      () => slotCount.value = 2,
      ['mixed', 'seats 1'],
      ['mixed', 'seats 2'],
    ),
    (
      'slot_local',
      SlotLocalSurface(
          label: 'seats', resolver: _Resolver(_blob(_design('slot_local')))),
      const SlotLocal(label: 'seats'),
      // The slot records the value its body reads each time it runs.
      true,
      () => slotCount.value = 2,
      ['local', 'SEATS! 1'],
      ['local', 'SEATS! 2'],
    ),
    (
      'slot_child',
      SlotChildSurface(resolver: _Resolver(_blob(_design('slot_child')))),
      const SlotChild(),
      false,
      () => slotCount.value = 2,
      ['child', 'n 1', 'kept'],
      ['child', 'n 2', 'kept'],
    ),
  ]) {
    testWidgets('$id renders and updates as the app does', (tester) async {
      expect(_design(id).contains('__RestageBuilderContinuation'), delivered);
      for (final (path, widget) in [
        ('app', original),
        ('delivered', surface),
        (
          'fallback',
          switch (surface) {
            SlotCountSurface() =>
              const SlotCountSurface(resolver: _Resolver(null)),
            SlotPlanCardSurface() =>
              const SlotPlanCardSurface(resolver: _Resolver(null)),
            SlotMixedSurface() =>
              const SlotMixedSurface(label: 'seats', resolver: _Resolver(null)),
            SlotLocalSurface() =>
              const SlotLocalSurface(label: 'seats', resolver: _Resolver(null)),
            _ => const SlotChildSurface(resolver: _Resolver(null)),
          }
        ),
      ]) {
        slotCount.value = 1;
        slotPlan.value =
            const SlotPlan('Monthly', 9, SlotTier.basic, ['Sync'], _blue);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: path);
        expect(find.byType(RemoteWidget),
            path == 'delivered' ? findsOneWidget : findsNothing,
            reason: path);
        expect(_texts(tester), before, reason: path);
        change();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: path);
        expect(_texts(tester), after, reason: path);
        if (id == 'slot_plan') {
          expect(tester.widget<Text>(find.text('Yearly 79 pro')).style?.color,
              _red,
              reason: path);
        }
      }
    });
  }

  // A slot body's condition over a build value records in the slot.
  for (final (id, original, surface) in [
    (
      'slot_flag',
      const SlotFlag() as Widget,
      (VariantResolver r) => SlotFlagSurface(resolver: r),
    ),
    (
      'slot_if',
      const SlotIf(),
      (VariantResolver r) => SlotIfSurface(resolver: r)
    ),
    (
      'slot_and',
      const SlotAnd(),
      (VariantResolver r) => SlotAndSurface(resolver: r)
    ),
  ]) {
    testWidgets('$id: a slot condition renders as the app does',
        (tester) async {
      Future<List<List<String?>>> run(Widget widget) async {
        slotCount.value = 1;
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final before = _texts(tester);
        slotCount.value = 2;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        return [before, _texts(tester)];
      }

      final app = await run(original);
      for (final (path, resolver) in [
        ('delivered', _Resolver(_blob(_design(id)))),
        ('fallback', const _Resolver(null)),
      ]) {
        final widget = surface(resolver);
        expect(await run(widget), app, reason: path);
        expect(find.byType(RemoteWidget),
            path == 'delivered' ? findsOneWidget : findsNothing,
            reason: path);
      }
    });
  }

  // A shared argument keeps its inferred type and runs once per build.
  testWidgets('slot_tween_end renders and calls as the app does',
      (tester) async {
    expect(_design('slot_tween_end').contains('__RestageBuilderContinuation'),
        isTrue);
    List<String?>? texts;
    List<String>? calls;
    for (final (path, widget) in [
      ('app', const SlotTweenEnd()),
      (
        'delivered',
        SlotTweenEndSurface(
            resolver: _Resolver(_blob(_design('slot_tween_end')))),
      ),
      ('fallback', const SlotTweenEndSurface(resolver: _Resolver(null))),
    ]) {
      slotEndCalls.clear();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: path);
      expect(_texts(tester), texts ??= _texts(tester), reason: path);
      expect(slotEndCalls, calls ??= [...slotEndCalls], reason: path);
    }
    expect(texts, ['tween end', 't 100']);
  });

  // A new design changes the delivered body without an app release, and the
  // body still reads the app's value.
  testWidgets('slot_count: an edited body reads the value', (tester) async {
    final design = _design('slot_count');
    // The body's text is a literal of its program.
    final edited = design.replaceAll(r'\"count ', r'\"total ');
    expect(edited, isNot(design));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SlotCountSurface(resolver: _Resolver(_blob(edited))))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_texts(tester), ['header', 'total 1']);
    slotCount.value = 3;
    await tester.pumpAndSettle();
    expect(_texts(tester), ['header', 'total 3']);
  });

  // The builder island keeps its element when the design replaces the
  // fallback, so a running animation continues where it was.
  testWidgets('slot_tween: a flip mid-animation continues where it was',
      (tester) async {
    expect(
        _design('slot_tween').contains('__RestageBuilderContinuation'), isTrue);
    late State<StatefulWidget> state;
    await _flip(tester, 'slot_tween', (r) => SlotTweenSurface(resolver: r),
        before: () async {
      await tester.pump(const Duration(milliseconds: 500));
      expect(_texts(tester), ['tween', 't 50']);
      state = tester.state(find.byType(TweenAnimationBuilder<double>));
    });
    expect(
        tester.state(find.byType(TweenAnimationBuilder<double>)), same(state));
    final shown = int.parse(_texts(tester).last!.substring(2));
    expect(shown, inInclusiveRange(50, 60));
    await tester.pump(const Duration(milliseconds: 600));
    expect(_texts(tester), ['tween', 't 100']);
  });

  testWidgets('slot_count: a flip keeps the builder element', (tester) async {
    late State<StatefulWidget> state;
    await _flip(tester, 'slot_count', (r) => SlotCountSurface(resolver: r),
        before: () async {
      expect(_texts(tester), ['header', 'count 1']);
      state = tester.state(find.byType(ValueListenableBuilder<int>));
    });
    expect(tester.state(find.byType(ValueListenableBuilder<int>)), same(state));
    expect(_texts(tester), ['header', 'count 1']);
    slotCount.value = 2;
    await tester.pump();
    expect(_texts(tester), ['header', 'count 2']);
  });
}
