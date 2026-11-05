import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/surfaces/guarded_reads.dart';
import 'package:restage_shared/restage_shared.dart';
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

const _bundle = 'assets/restage/bundles/lib/surfaces/guarded_reads.rsbundle';

/// The delivered design text of the paywall [id].
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
      // A design may render an interpolated string as `Text.rich`.
      for (final element in find.byType(Text).evaluate())
        (element.widget as Text).data ??
            (element.widget as Text).textSpan?.toPlainText(),
    ];

void main() {
  useSupportDirectoryChannel();

  setUp(() async {
    await Restage.debugResetAndWait();
    Restage.configure(apiKey: 'rs_pk_test', resolver: const _Resolver(null));
    guardedCalls.clear();
  });

  // Each shape with the case where the app skips the guarded work, then the
  // case where it does it: the app's own widget, the delivered design and the
  // compiled fallback render the same and make the same calls.
  for (final (id, cases)
      in <(String, List<(Widget, Widget Function(VariantResolver))>)>[
    (
      'read_early_return',
      [
        (const ReadEarlyReturn(), (r) => ReadEarlyReturnSurface(resolver: r)),
        (
          const ReadEarlyReturn(offer: ReadOffer(['Sync'])),
          (r) => ReadEarlyReturnSurface(
              offer: const ReadOffer(['Sync']), resolver: r),
        ),
      ],
    ),
    (
      'read_guarded_call',
      [
        (const ReadGuardedCall(), (r) => ReadGuardedCallSurface(resolver: r)),
        (
          const ReadGuardedCall(offer: ReadOffer(['Sync'])),
          (r) => ReadGuardedCallSurface(
              offer: const ReadOffer(['Sync']), resolver: r),
        ),
      ],
    ),
    (
      'read_nested_guard',
      [
        (const ReadNestedGuard(), (r) => ReadNestedGuardSurface(resolver: r)),
        (
          const ReadNestedGuard(offer: ReadOffer(['Sync'])),
          (r) => ReadNestedGuardSurface(
              offer: const ReadOffer(['Sync']), resolver: r),
        ),
      ],
    ),
    (
      'read_flagged_check',
      [
        (const ReadFlaggedCheck(), (r) => ReadFlaggedCheckSurface(resolver: r)),
        (
          const ReadFlaggedCheck(flag: true),
          (r) => ReadFlaggedCheckSurface(flag: true, resolver: r),
        ),
      ],
    ),
    (
      'read_conditional_call',
      [
        (
          const ReadConditionalCall(),
          (r) => ReadConditionalCallSurface(resolver: r)
        ),
        (
          const ReadConditionalCall(offer: ReadOffer(['Sync'])),
          (r) => ReadConditionalCallSurface(
              offer: const ReadOffer(['Sync']), resolver: r),
        ),
      ],
    ),
    (
      'read_early_plans',
      [
        (const ReadEarlyPlans(), (r) => ReadEarlyPlansSurface(resolver: r)),
        (
          const ReadEarlyPlans(plans: [ReadPlan('Monthly')]),
          (r) => ReadEarlyPlansSurface(
              plans: const [ReadPlan('Monthly')], resolver: r),
        ),
      ],
    ),
    (
      'read_flagged_call',
      [
        (const ReadFlaggedCall(), (r) => ReadFlaggedCallSurface(resolver: r)),
        (
          const ReadFlaggedCall(flag: true),
          (r) => ReadFlaggedCallSurface(flag: true, resolver: r),
        ),
      ],
    ),
    (
      'read_item_check',
      [
        (
          const ReadItemCheck(holders: [ReadHolder(null)]),
          (r) => ReadItemCheckSurface(
              holders: const [ReadHolder(null)], resolver: r),
        ),
        (
          const ReadItemCheck(holders: [
            ReadHolder(null),
            ReadHolder(ReadOffer(['Sync']))
          ]),
          (r) => ReadItemCheckSurface(holders: const [
                ReadHolder(null),
                ReadHolder(ReadOffer(['Sync'])),
              ], resolver: r),
        ),
      ],
    ),
    (
      'read_item_eligible',
      [
        (
          const ReadItemEligible(holders: [ReadHolder(null)]),
          (r) => ReadItemEligibleSurface(
              holders: const [ReadHolder(null)], resolver: r),
        ),
        (
          const ReadItemEligible(holders: [
            ReadHolder(ReadOffer(['Sync']))
          ]),
          (r) => ReadItemEligibleSurface(holders: const [
                ReadHolder(ReadOffer(['Sync']))
              ], resolver: r),
        ),
      ],
    ),
    (
      'read_return_in_if',
      [
        (const ReadReturnInIf(), (r) => ReadReturnInIfSurface(resolver: r)),
        (
          const ReadReturnInIf(offer: ReadOffer(['Sync'])),
          (r) => ReadReturnInIfSurface(
              offer: const ReadOffer(['Sync']), resolver: r),
        ),
      ],
    ),
    (
      'read_return_no_braces',
      [
        (
          const ReadReturnNoBraces(),
          (r) => ReadReturnNoBracesSurface(resolver: r)
        ),
        (
          const ReadReturnNoBraces(offer: ReadOffer(['Sync'])),
          (r) => ReadReturnNoBracesSurface(
              offer: const ReadOffer(['Sync']), resolver: r),
        ),
      ],
    ),
    (
      'read_return_nested',
      [
        (
          const ReadReturnNested(flag: true),
          (r) => ReadReturnNestedSurface(flag: true, resolver: r)
        ),
        (
          const ReadReturnNested(flag: true, offer: ReadOffer(['Sync'])),
          (r) => ReadReturnNestedSurface(
              flag: true, offer: const ReadOffer(['Sync']), resolver: r),
        ),
      ],
    ),
    (
      'read_item_list',
      [
        (
          const ReadItemList(holders: [ReadHolder(null)]),
          (r) => ReadItemListSurface(
              holders: const [ReadHolder(null)], resolver: r),
        ),
        (
          const ReadItemList(holders: [
            ReadHolder(ReadOffer(['Sync']))
          ]),
          (r) => ReadItemListSurface(holders: const [
                ReadHolder(ReadOffer(['Sync']))
              ], resolver: r),
        ),
      ],
    ),
    (
      'read_block_framed',
      [
        (const ReadBlockFramed(), (r) => ReadBlockFramedSurface(resolver: r)),
        (
          const ReadBlockFramed(offer: ReadOffer(['Sync', 'Backup'])),
          (r) => ReadBlockFramedSurface(
              offer: const ReadOffer(['Sync', 'Backup']), resolver: r),
        ),
      ],
    ),
    (
      'read_block_loop',
      [
        (const ReadBlockLoop(), (r) => ReadBlockLoopSurface(resolver: r)),
        (
          const ReadBlockLoop(offer: ReadOffer(['Sync', 'Backup'])),
          (r) => ReadBlockLoopSurface(
              offer: const ReadOffer(['Sync', 'Backup']), resolver: r),
        ),
      ],
    ),
    (
      'read_block_text',
      [
        (const ReadBlockText(), (r) => ReadBlockTextSurface(resolver: r)),
        (
          const ReadBlockText(offer: ReadOffer(['Sync', 'Backup'])),
          (r) => ReadBlockTextSurface(
              offer: const ReadOffer(['Sync', 'Backup']), resolver: r),
        ),
      ],
    ),
    (
      'read_block_shadow',
      [
        (const ReadBlockShadow(), (r) => ReadBlockShadowSurface(resolver: r)),
        (
          const ReadBlockShadow(offer: ReadOffer(['Sync', 'Backup'])),
          (r) => ReadBlockShadowSurface(
              offer: const ReadOffer(['Sync', 'Backup']), resolver: r),
        ),
      ],
    ),
    (
      'read_block_same_name',
      [
        (
          const ReadBlockSameName(),
          (r) => ReadBlockSameNameSurface(resolver: r)
        ),
        (
          const ReadBlockSameName(title: 'Pro'),
          (r) => ReadBlockSameNameSurface(title: 'Pro', resolver: r),
        ),
        (
          const ReadBlockSameName(offer: ReadOffer(['Sync']), title: 'Pro'),
          (r) => ReadBlockSameNameSurface(
              offer: const ReadOffer(['Sync']), title: 'Pro', resolver: r),
        ),
      ],
    ),
    (
      'read_case_text',
      [
        (const ReadCaseText(), (r) => ReadCaseTextSurface(resolver: r)),
        (
          const ReadCaseText(offer: ReadOffer(['Sync', 'Backup'])),
          (r) => ReadCaseTextSurface(
              offer: const ReadOffer(['Sync', 'Backup']), resolver: r),
        ),
      ],
    ),
    (
      'read_case_framed',
      [
        (const ReadCaseFramed(), (r) => ReadCaseFramedSurface(resolver: r)),
        (
          const ReadCaseFramed(offer: ReadOffer(['Sync', 'Backup'])),
          (r) => ReadCaseFramedSurface(
              offer: const ReadOffer(['Sync', 'Backup']), resolver: r),
        ),
      ],
    ),
    (
      'read_case_loop',
      [
        (const ReadCaseLoop(), (r) => ReadCaseLoopSurface(resolver: r)),
        (
          const ReadCaseLoop(offer: ReadOffer(['Sync', 'Backup'])),
          (r) => ReadCaseLoopSurface(
              offer: const ReadOffer(['Sync', 'Backup']), resolver: r),
        ),
      ],
    ),
    (
      'read_case_when',
      [
        (const ReadCaseWhen(), (r) => ReadCaseWhenSurface(resolver: r)),
        (
          const ReadCaseWhen(offer: ReadOffer(['Sync', 'Backup'])),
          (r) => ReadCaseWhenSurface(
              offer: const ReadOffer(['Sync', 'Backup']), resolver: r),
        ),
      ],
    ),
    (
      'read_case_when',
      [
        (
          const ReadCaseWhen(offer: ReadOffer(['Sync'])),
          (r) => ReadCaseWhenSurface(
              offer: const ReadOffer(['Sync']), resolver: r),
        ),
      ],
    ),
    (
      'read_loop_local',
      [
        (
          const ReadLoopLocal(plans: [ReadPlan('Monthly')]),
          (r) => ReadLoopLocalSurface(
              plans: const [ReadPlan('Monthly')], resolver: r),
        ),
        (
          const ReadLoopLocal(plans: [
            ReadPlan('Monthly'),
            ReadPlan('Weekly'),
            ReadPlan('Yearly')
          ]),
          (r) => ReadLoopLocalSurface(plans: const [
                ReadPlan('Monthly'),
                ReadPlan('Weekly'),
                ReadPlan('Yearly'),
              ], resolver: r),
        ),
      ],
    ),
    (
      'read_loop_variable',
      [
        (
          const ReadLoopVariable(plans: [ReadPlan('')]),
          (r) =>
              ReadLoopVariableSurface(plans: const [ReadPlan('')], resolver: r),
        ),
        (
          const ReadLoopVariable(plans: [ReadPlan(''), ReadPlan('Monthly')]),
          (r) => ReadLoopVariableSurface(
              plans: const [ReadPlan(''), ReadPlan('Monthly')], resolver: r),
        ),
      ],
    ),
    (
      'read_block_context',
      [
        (const ReadBlockContext(), (r) => ReadBlockContextSurface(resolver: r)),
        (
          const ReadBlockContext(offer: ReadOffer(['Sync', 'Backup'])),
          (r) => ReadBlockContextSurface(
              offer: const ReadOffer(['Sync', 'Backup']), resolver: r),
        ),
      ],
    ),
    (
      'read_shadow_function',
      [
        (
          const ReadShadowFunction(),
          (r) => ReadShadowFunctionSurface(resolver: r)
        ),
        (
          const ReadShadowFunction(offer: ReadOffer(['Sync', 'Backup'])),
          (r) => ReadShadowFunctionSurface(
              offer: const ReadOffer(['Sync', 'Backup']), resolver: r),
        ),
      ],
    ),
    (
      'read_shadow_final',
      [
        (const ReadShadowFinal(), (r) => ReadShadowFinalSurface(resolver: r)),
        (
          const ReadShadowFinal(offer: ReadOffer(['Sync', 'Backup'])),
          (r) => ReadShadowFinalSurface(
              offer: const ReadOffer(['Sync', 'Backup']), resolver: r),
        ),
      ],
    ),
    (
      'read_shadow_const',
      [
        (const ReadShadowConst(), (r) => ReadShadowConstSurface(resolver: r)),
        (
          const ReadShadowConst(offer: ReadOffer(['Sync', 'Backup'])),
          (r) => ReadShadowConstSurface(
              offer: const ReadOffer(['Sync', 'Backup']), resolver: r),
        ),
      ],
    ),
    (
      'read_block_destructure',
      [
        (
          const ReadBlockDestructure(),
          (r) => ReadBlockDestructureSurface(resolver: r)
        ),
        (
          const ReadBlockDestructure(offer: ReadOffer(['Sync', 'Backup'])),
          (r) => ReadBlockDestructureSurface(
              offer: const ReadOffer(['Sync', 'Backup']), resolver: r),
        ),
      ],
    ),
    (
      'read_build_context',
      [
        (const ReadBuildContext(), (r) => ReadBuildContextSurface(resolver: r)),
        (
          const ReadBuildContext(title: 'Pro', flag: true),
          (r) => ReadBuildContextSurface(title: 'Pro', flag: true, resolver: r),
        ),
      ],
    ),
    (
      'read_case_score',
      [
        (const ReadCaseScore(), (r) => ReadCaseScoreSurface(resolver: r)),
        (
          const ReadCaseScore(score: 'NaN'),
          (r) => ReadCaseScoreSurface(score: 'NaN', resolver: r),
        ),
        (
          const ReadCaseScore(score: '1.5'),
          (r) => ReadCaseScoreSurface(score: '1.5', resolver: r),
        ),
      ],
    ),
    (
      'read_classic_loop',
      [
        (
          const ReadClassicLoop(plans: [ReadPlan('Monthly')]),
          (r) => ReadClassicLoopSurface(
              plans: const [ReadPlan('Monthly')], resolver: r),
        ),
        (
          const ReadClassicLoop(plans: [
            ReadPlan('Monthly'),
            ReadPlan('Weekly'),
            ReadPlan('Yearly'),
          ]),
          (r) => ReadClassicLoopSurface(plans: const [
                ReadPlan('Monthly'),
                ReadPlan('Weekly'),
                ReadPlan('Yearly'),
              ], resolver: r),
        ),
      ],
    ),
    (
      'read_try_local',
      [
        (const ReadTryLocal(), (r) => ReadTryLocalSurface(resolver: r)),
        (
          const ReadTryLocal(offer: ReadOffer(['Sync'])),
          (r) => ReadTryLocalSurface(
              offer: const ReadOffer(['Sync']), resolver: r),
        ),
      ],
    ),
    (
      'read_switch_offer',
      [
        (const ReadSwitchOffer(), (r) => ReadSwitchOfferSurface(resolver: r)),
        (
          const ReadSwitchOffer(offer: ReadOffer(['Sync', 'Backup'])),
          (r) => ReadSwitchOfferSurface(
              offer: const ReadOffer(['Sync', 'Backup']), resolver: r),
        ),
      ],
    ),
    (
      'read_switch_flag',
      [
        (const ReadSwitchFlag(), (r) => ReadSwitchFlagSurface(resolver: r)),
        (
          const ReadSwitchFlag(flag: true),
          (r) => ReadSwitchFlagSurface(flag: true, resolver: r),
        ),
      ],
    ),
    (
      'read_switch_tier',
      [
        (const ReadSwitchTier(), (r) => ReadSwitchTierSurface(resolver: r)),
        (
          const ReadSwitchTier(plan: 'Pro'),
          (r) => ReadSwitchTierSurface(plan: 'Pro', resolver: r),
        ),
        (
          const ReadSwitchTier(plan: 'Premium'),
          (r) => ReadSwitchTierSurface(plan: 'Premium', resolver: r),
        ),
      ],
    ),
    (
      'read_switch_tier_statement',
      [
        (
          const ReadSwitchTierStatement(),
          (r) => ReadSwitchTierStatementSurface(resolver: r)
        ),
        (
          const ReadSwitchTierStatement(plan: 'Pro'),
          (r) => ReadSwitchTierStatementSurface(plan: 'Pro', resolver: r),
        ),
      ],
    ),
    (
      'read_loop_indexed',
      [
        (
          const ReadLoopIndexed(plans: [ReadPlan('Monthly')]),
          (r) => ReadLoopIndexedSurface(
              plans: const [ReadPlan('Monthly')], resolver: r),
        ),
        (
          const ReadLoopIndexed(
              plans: [ReadPlan('Monthly'), ReadPlan('Yearly')]),
          (r) => ReadLoopIndexedSurface(
              plans: const [ReadPlan('Monthly'), ReadPlan('Yearly')],
              resolver: r),
        ),
      ],
    ),
    (
      'read_catch_parameter',
      [
        (
          const ReadCatchParameter(),
          (r) => ReadCatchParameterSurface(resolver: r)
        ),
        (
          const ReadCatchParameter(offer: ReadOffer(['Sync'])),
          (r) => ReadCatchParameterSurface(
              offer: const ReadOffer(['Sync']), resolver: r),
        ),
      ],
    ),
    (
      'read_cx1',
      [
        (const ReadCx1(), (r) => ReadCx1Surface(resolver: r)),
        (
          const ReadCx1(flag: true),
          (r) => ReadCx1Surface(flag: true, resolver: r)
        ),
      ],
    ),
    (
      'read_s11',
      [
        (
          const ReadS11(offer: ReadOffer([''])),
          (r) => ReadS11Surface(offer: ReadOffer(['']), resolver: r)
        ),
        (
          const ReadS11(offer: ReadOffer(['Sync'])),
          (r) => ReadS11Surface(offer: ReadOffer(['Sync']), resolver: r)
        ),
      ],
    ),
    (
      'read_sx9',
      [
        (
          const ReadSx9(offer: ReadOffer(['a'])),
          (r) => ReadSx9Surface(offer: ReadOffer(['a']), resolver: r)
        ),
        (
          const ReadSx9(offer: ReadOffer(['a', 'b'])),
          (r) => ReadSx9Surface(offer: ReadOffer(['a', 'b']), resolver: r)
        ),
      ],
    ),
    (
      'read_s24',
      [
        (const ReadS24(), (r) => ReadS24Surface(resolver: r)),
        (
          const ReadS24(offer: ReadOffer(['a', 'b'])),
          (r) => ReadS24Surface(offer: ReadOffer(['a', 'b']), resolver: r)
        ),
      ],
    ),
    (
      'read_sx10',
      [
        (
          const ReadSx10(offer: ReadOffer(['a'])),
          (r) => ReadSx10Surface(offer: ReadOffer(['a']), resolver: r)
        ),
        (
          const ReadSx10(offer: ReadOffer(['a', 'b'])),
          (r) => ReadSx10Surface(offer: ReadOffer(['a', 'b']), resolver: r)
        ),
      ],
    ),
    (
      'read_s18',
      [
        (const ReadS18(), (r) => ReadS18Surface(resolver: r)),
        (
          const ReadS18(offer: ReadOffer(['Sync'])),
          (r) => ReadS18Surface(offer: ReadOffer(['Sync']), resolver: r)
        ),
      ],
    ),
    (
      'read_u1',
      [
        (const ReadU1(), (r) => ReadU1Surface(resolver: r)),
        (
          const ReadU1(
              plans: [ReadPlan(''), ReadPlan('x'), ReadPlan('Yearly')]),
          (r) => ReadU1Surface(
              plans: [ReadPlan(''), ReadPlan('x'), ReadPlan('Yearly')],
              resolver: r)
        ),
      ],
    ),
    (
      'read_j3',
      [
        (const ReadJ3(), (r) => ReadJ3Surface(resolver: r)),
        (
          const ReadJ3(offer: ReadOffer(['Sync'])),
          (r) => ReadJ3Surface(offer: ReadOffer(['Sync']), resolver: r)
        ),
      ],
    ),
    (
      'read_and_local',
      [
        (const ReadAndLocal(), (r) => ReadAndLocalSurface(resolver: r)),
        (
          const ReadAndLocal(offer: ReadOffer(['Sync'])),
          (r) => ReadAndLocalSurface(
              offer: const ReadOffer(['Sync']), resolver: r),
        ),
      ],
    ),
    (
      'read_or_local',
      [
        (const ReadOrLocal(), (r) => ReadOrLocalSurface(resolver: r)),
        (
          const ReadOrLocal(offer: ReadOffer(['Sync'])),
          (r) =>
              ReadOrLocalSurface(offer: const ReadOffer(['Sync']), resolver: r),
        ),
      ],
    ),
    (
      'read_sx2',
      [
        (const ReadSx2(), (r) => ReadSx2Surface(resolver: r)),
        (
          const ReadSx2(offer: ReadOffer(['Sync']), flag: true),
          (r) => ReadSx2Surface(
              offer: ReadOffer(['Sync']), flag: true, resolver: r)
        ),
      ],
    ),
    (
      'read_sx8',
      [
        (const ReadSx8(), (r) => ReadSx8Surface(resolver: r)),
        (
          const ReadSx8(offer: ReadOffer(['Sync']), flag: true),
          (r) => ReadSx8Surface(
              offer: ReadOffer(['Sync']), flag: true, resolver: r)
        ),
      ],
    ),
    (
      'read_localized',
      [
        (const ReadLocalized(), (r) => ReadLocalizedSurface(resolver: r)),
        (const ReadLocalized(), (r) => ReadLocalizedSurface(resolver: r)),
      ],
    ),
    (
      'read_print_action',
      [
        (const ReadPrintAction(), (r) => ReadPrintActionSurface(resolver: r)),
        (const ReadPrintAction(), (r) => ReadPrintActionSurface(resolver: r)),
      ],
    ),
    (
      'read_island_args',
      [
        (const ReadIslandArgs(), (r) => ReadIslandArgsSurface(resolver: r)),
        (
          const ReadIslandArgs(label: 'Plus'),
          (r) => ReadIslandArgsSurface(label: 'Plus', resolver: r)
        ),
      ],
    ),
    (
      'read_island_builder_args',
      [
        (
          const ReadIslandBuilderArgs(),
          (r) => ReadIslandBuilderArgsSurface(resolver: r)
        ),
        (
          const ReadIslandBuilderArgs(label: 'Plus'),
          (r) => ReadIslandBuilderArgsSurface(label: 'Plus', resolver: r)
        ),
      ],
    ),
    (
      'read_builder_values',
      [
        (
          const ReadBuilderValues(),
          (r) => ReadBuilderValuesSurface(resolver: r)
        ),
        (
          const ReadBuilderValues(),
          (r) => ReadBuilderValuesSurface(resolver: r)
        ),
      ],
    ),
    (
      'read_builder_slot',
      [
        (const ReadBuilderSlot(), (r) => ReadBuilderSlotSurface(resolver: r)),
        (const ReadBuilderSlot(), (r) => ReadBuilderSlotSurface(resolver: r)),
      ],
    ),
    (
      'read_island_implicit',
      [
        (
          const ReadIslandImplicit(),
          (r) => ReadIslandImplicitSurface(resolver: r)
        ),
        (
          const ReadIslandImplicit(),
          (r) => ReadIslandImplicitSurface(resolver: r)
        ),
      ],
    ),
    (
      'read_impure_twice',
      [
        (const ReadImpureTwice(), (r) => ReadImpureTwiceSurface(resolver: r)),
        (const ReadImpureTwice(), (r) => ReadImpureTwiceSurface(resolver: r)),
      ],
    ),
    (
      'read_builder_rows',
      [
        (const ReadBuilderRows(), (r) => ReadBuilderRowsSurface(resolver: r)),
        (const ReadBuilderRows(), (r) => ReadBuilderRowsSurface(resolver: r)),
      ],
    ),
    (
      'read_try_return',
      [
        (const ReadTryReturn(), (r) => ReadTryReturnSurface(resolver: r)),
        (
          const ReadTryReturn(offer: ReadOffer(['Sync'])),
          (r) => ReadTryReturnSurface(
              offer: const ReadOffer(['Sync']), resolver: r),
        ),
      ],
    ),
    (
      'read_null_check',
      [
        (const ReadNullCheck(), (r) => ReadNullCheckSurface(resolver: r)),
        (
          const ReadNullCheck(title: 'Pro'),
          (r) => ReadNullCheckSurface(title: 'Pro', resolver: r),
        ),
      ],
    ),
  ]) {
    for (final (index, (original, surface)) in cases.indexed) {
      final name = '$id, ${index == 0 ? 'skipped' : 'taken'}';
      testWidgets('$name renders and calls what the app does', (tester) async {
        final debug = <String>[];
        final previous = debugPrint;
        debugPrint = (message, {wrapWidth}) => debug.add('$message');
        try {
          await tester.pumpWidget(MaterialApp(home: Scaffold(body: original)));
          await tester.pumpAndSettle();
          final texts = _texts(tester);
          final calls = [...guardedCalls];

          for (final (path, resolver) in [
            ('delivered', _Resolver(_blob(_design(id)))),
            ('fallback', const _Resolver(null)),
          ]) {
            guardedCalls.clear();
            await tester.pumpWidget(const SizedBox());
            await tester.pumpWidget(
                MaterialApp(home: Scaffold(body: surface(resolver))));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: path);
            expect(find.byType(RemoteWidget),
                path == 'delivered' ? findsOneWidget : findsNothing,
                reason: path);
            expect(_texts(tester), texts, reason: path);
            expect(guardedCalls, calls, reason: path);
          }
        } finally {
          debugPrint = previous;
        }
        expect(debug.where((line) => line.contains('threw')), isEmpty);
      });
    }
  }

  // A root builder that runs again records only that run.
  testWidgets('read_builder_rerun: a rerun shows only its own rows',
      (tester) async {
    Future<List<String?>> show(Widget widget, List<String> names) async {
      readNames.value = ['a', 'b', 'c'];
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));
      await tester.pumpAndSettle();
      readNames.value = names;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      return _texts(tester);
    }

    for (final names in [
      ['b'],
      ['a', 'b'],
      ['x', 'y', 'z', 'w'],
    ]) {
      final app = await show(const ReadBuilderRerun(), names);
      expect(app, [for (final name in names) '${name.toUpperCase()}!']);
      for (final (path, resolver) in [
        ('delivered', _Resolver(_blob(_design('read_builder_rerun')))),
        ('fallback', const _Resolver(null)),
      ]) {
        expect(
            await show(ReadBuilderRerunSurface(resolver: resolver), names), app,
            reason: '$path $names');
      }
    }
  });

  // A new identity key each build leaves no key behind.
  testWidgets('read_unique_keyed: island keys stay bounded across builds',
      (tester) async {
    for (final (path, resolver) in [
      ('delivered', _Resolver(_blob(_design('read_unique_keyed')))),
      ('fallback', const _Resolver(null)),
    ]) {
      await tester.pumpWidget(const SizedBox());
      for (var build = 0; build < 6; build++) {
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                // ignore: prefer_const_constructors
                body: ReadUniqueKeyedSurface(resolver: resolver))));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull, reason: path);
      final owner = tester.element(find.byType(ReadUniqueKeyedSurface));
      expect(RestageIslandScope.debugKeyCount(owner), lessThanOrEqualTo(2),
          reason: path);
    }
  });

  // An island the app keys keeps its State by that key, as Flutter does.
  testWidgets('read_keyed_loop: a keyed island keeps its State on removal',
      (tester) async {
    Future<List<String>> remove(Widget Function(List<String>) widget) async {
      await tester.pumpWidget(const SizedBox());
      guardedCalls.clear();
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: widget(const ['a', 'b']))));
      await tester.pumpAndSettle();
      await tester
          .pumpWidget(MaterialApp(home: Scaffold(body: widget(const ['b']))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      return [...guardedCalls];
    }

    final app = await remove((names) => ReadKeyedLoop(names: names));
    expect(app, ['init a', 'init b', 'dispose a']);
    for (final (path, resolver) in [
      ('delivered', _Resolver(_blob(_design('read_keyed_loop')))),
      ('fallback', const _Resolver(null)),
    ]) {
      final calls = await remove(
          (names) => ReadKeyedLoopSurface(names: names, resolver: resolver));
      // The same States, and only the removed one disposed. The delivered
      // path may mount the two in another order.
      expect(calls.toSet(), app.toSet(), reason: path);
      expect(calls, hasLength(app.length), reason: path);
      expect(calls.last, 'dispose a', reason: path);
    }
  });

  // Each call site of a helper renders its island's delivered child.
  testWidgets('read_helper_twice: each call site renders its delivered child',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: ReadHelperTwice())));
    final texts = _texts(tester);
    expect(texts, ['monthly', 'yearly']);
    final design = _design('read_helper_twice');
    final edited = design.replaceAllMapped(
        RegExp(r'child: Text\(text: "(\w+)"\)'),
        (match) => 'child: Text(text: "delivered ${match[1]}")');
    expect(edited, isNot(design));
    for (final (path, resolver, shown) in [
      ('delivered', _Resolver(_blob(design)), texts),
      ('fallback', const _Resolver(null), texts),
      (
        'edited',
        _Resolver(_blob(edited)),
        ['delivered monthly', 'delivered yearly'],
      ),
    ]) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: ReadHelperTwiceSurface(resolver: resolver))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: path);
      expect(_texts(tester), shown, reason: path);
    }
  });

  // A builder's body runs when Flutter calls it, so the State's controller and
  // the colors it computes reach the design on every path.
  for (final (id, original, surface) in [
    (
      'read_builder_values',
      const ReadBuilderValues() as Widget,
      (VariantResolver r) => ReadBuilderValuesSurface(resolver: r),
    ),
    (
      'read_builder_slot',
      const ReadBuilderSlot(),
      (VariantResolver r) => ReadBuilderSlotSurface(resolver: r),
    ),
  ]) {
    testWidgets('$id resolves its controller and colors', (tester) async {
      List<Object?> seen() {
        final list = tester.widget<ScrollView>(
            find.byWidgetPredicate((widget) => widget is ScrollView));
        return [
          list.controller != null && list.controller!.hasClients,
          for (final element in find.byType(RichText).evaluate())
            if ((element.widget as RichText).text case final TextSpan span)
              (
                span.toPlainText(),
                span.style?.color ??
                    span.children
                        ?.whereType<TextSpan>()
                        .firstOrNull
                        ?.style
                        ?.color
              ),
        ];
      }

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: original)));
      await tester.pumpAndSettle();
      final expected = seen();
      expect(expected.first, isTrue);
      for (final (path, resolver) in [
        ('delivered', _Resolver(_blob(_design(id)))),
        ('fallback', const _Resolver(null)),
      ]) {
        await tester.pumpWidget(const SizedBox());
        await tester
            .pumpWidget(MaterialApp(home: Scaffold(body: surface(resolver))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: path);
        expect(seen(), expected, reason: path);
      }
    });
  }

  // A check in a loop body is tested by the mount once, whatever the list
  // holds, and a list under a check on each item is computed early. Either
  // runs inside a catch, so where it throws its value is left out (logged) and
  // the design renders what the app renders.
  const plan = [ReadPlan('Monthly')];
  const offer = ReadOffer(['Sync']);
  for (final (id, name, original, surface) in [
    (
      'read_plan_features',
      'no offer',
      const ReadPlanFeatures(plans: [ReadPlan('')]),
      (VariantResolver r) =>
          ReadPlanFeaturesSurface(plans: const [ReadPlan('')], resolver: r),
    ),
    (
      'read_plan_features',
      'an offer',
      const ReadPlanFeatures(plans: plan, offer: offer),
      (VariantResolver r) =>
          ReadPlanFeaturesSurface(plans: plan, offer: offer, resolver: r),
    ),
    (
      'read_loop_check',
      'no plans, no offer',
      const ReadLoopCheck(),
      (VariantResolver r) => ReadLoopCheckSurface(resolver: r),
    ),
    (
      'read_loop_check',
      'a plan and an offer',
      const ReadLoopCheck(plans: plan, offer: offer),
      (VariantResolver r) =>
          ReadLoopCheckSurface(plans: plan, offer: offer, resolver: r),
    ),
    (
      'read_loop_call',
      'no plans, no offer',
      const ReadLoopCall(),
      (VariantResolver r) => ReadLoopCallSurface(resolver: r),
    ),
    (
      'read_loop_call',
      'a plan and an offer',
      const ReadLoopCall(plans: plan, offer: offer),
      (VariantResolver r) =>
          ReadLoopCallSurface(plans: plan, offer: offer, resolver: r),
    ),
    (
      'read_loop_list',
      'no plans, no offer',
      const ReadLoopList(),
      (VariantResolver r) => ReadLoopListSurface(resolver: r),
    ),
    (
      'read_loop_list',
      'a plan and an offer',
      const ReadLoopList(plans: plan, offer: offer),
      (VariantResolver r) =>
          ReadLoopListSurface(plans: plan, offer: offer, resolver: r),
    ),
  ]) {
    testWidgets('$id, $name: a value that throws is left out', (tester) async {
      final debug = <String>[];
      final previous = debugPrint;
      debugPrint = (message, {wrapWidth}) => debug.add('$message');
      try {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: original)));
        await tester.pumpAndSettle();
        final texts = _texts(tester);
        final calls = [...guardedCalls];
        for (final (path, resolver) in [
          ('delivered', _Resolver(_blob(_design(id)))),
          ('fallback', const _Resolver(null)),
        ]) {
          guardedCalls.clear();
          await tester.pumpWidget(const SizedBox());
          await tester
              .pumpWidget(MaterialApp(home: Scaffold(body: surface(resolver))));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: path);
          expect(_texts(tester), texts, reason: path);
          expect(guardedCalls, calls, reason: path);
        }
      } finally {
        debugPrint = previous;
      }
      expect(
          debug
              .where((line) => line.contains('threw'))
              .every((line) => line.contains('offer!')),
          isTrue,
          reason: '$debug');
    });
  }

  // A nested list's items keep their keys too, keyed by the inner item or
  // by both.
  testWidgets('read_nested_keys: each nested item keeps its key',
      (tester) async {
    const sections = [
      ReadSection('a', ['x', 'y']),
      ReadSection('b', ['z']),
    ];
    const keys = ['x', 'y', 'z', 'a/x', 'a/y', 'b/z'];
    for (final (path, widget) in [
      ('app', const ReadNestedKeys(sections: sections)),
      (
        'delivered',
        ReadNestedKeysSurface(
            sections: sections,
            resolver: _Resolver(_blob(_design('read_nested_keys')))),
      ),
      (
        'fallback',
        const ReadNestedKeysSurface(
            sections: sections, resolver: _Resolver(null)),
      ),
    ]) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: path);
      for (final key in keys) {
        expect(tester.widget(find.byKey(ValueKey(key))), isA<ElevatedButton>(),
            reason: '$path $key');
      }
    }
  });

  // Each item's key reaches its widget, as in the app's own build.
  for (final (name, plans, offer, keys) in [
    ('no offer', const [ReadPlan('Monthly')], null, ['Monthly']),
    (
      'an offer',
      const [ReadPlan('Monthly'), ReadPlan('Yearly')],
      const ReadOffer(['Sync']),
      ['Monthly', 'Yearly', 'Sync'],
    ),
  ]) {
    testWidgets('read_item_keys, $name: each item keeps its key',
        (tester) async {
      for (final (path, widget) in [
        ('app', ReadItemKeys(plans: plans, offer: offer)),
        (
          'delivered',
          ReadItemKeysSurface(
              plans: plans,
              offer: offer,
              resolver: _Resolver(_blob(_design('read_item_keys')))),
        ),
        (
          'fallback',
          ReadItemKeysSurface(
              plans: plans, offer: offer, resolver: const _Resolver(null)),
        ),
      ]) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: path);
        expect(find.byType(ElevatedButton), findsNWidgets(keys.length),
            reason: path);
        for (final key in keys) {
          expect(
              tester.widget(find.byKey(ValueKey(key))), isA<ElevatedButton>(),
              reason: '$path $key');
        }
      }
    });
  }

  testWidgets(
      'a design that reads a list the app did not compute renders '
      'nothing for it', (tester) async {
    final items = RegExp(r'for f in data\.context\.(_h\w+)')
        .firstMatch(_design('read_nested_guard'))!
        .group(1);
    final design = _blob('import restage.core;\n'
        'widget Paywall = Column(children: [...for f in data.context.$items: '
        'Text(text: f), Text(text: "end")]);');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ReadNestedGuardSurface(resolver: _Resolver(design)))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(RemoteWidget), findsOneWidget);
    expect(_texts(tester), ['end']);
    expect(guardedCalls, isEmpty);
  });
  islandStateMain();
}

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

void islandStateMain() {
  // An island keeps its State when a reload swaps the fallback for the
  // design. A failed reload keeps a shown design, so a mount flips this way.
  testWidgets(
    'read_kept_state: an island keeps its State across a flip',
    (tester) async {
      tallyStates = 0;
      final resolver = _Switchable(null);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: ReadKeptStateSurface(resolver: resolver))));
      await tester.pumpAndSettle();
      expect(find.byType(RemoteWidget), findsNothing);
      expect(_texts(tester), contains('tally 1'));
      resolver.bytes = _blob(_design('read_kept_state'));
      final reload = Restage.reloadSurfaces();
      // The fallback stays shown, frame by frame, until the design replaces it.
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump();
        expect(_texts(tester), contains('tally 1'), reason: 'frame $frame');
      }
      await reload;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(RemoteWidget), findsOneWidget);
      expect(_texts(tester), contains('tally 1'));
      expect(tallyStates, 1);
    },
  );

  // A list scrolled through the State's controller renders on every path,
  // and the app's own offset reads keep working while a reloaded design is
  // staged beside the fallback.
  testWidgets("read_scrolled: the State's controller drives the list",
      (tester) async {
    final resolver = _Switchable(null);
    scrolledOffsets.clear();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ReadScrolledSurface(resolver: resolver))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_texts(tester), ['row a', 'row b']);
    resolver.bytes = _blob(_design('read_scrolled'));
    final reload = Restage.reloadSurfaces();
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'frame $frame');
    }
    await reload;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(RemoteWidget), findsOneWidget);
    expect(_texts(tester), ['row a', 'row b']);
    expect(scrolledOffsets, isNotEmpty);
  });

  // An island a helper places twice is two islands, each with its own key;
  // one inside a value the helper places twice is keyed at each placement.
  for (final (id, surface) in <(String, Widget Function(VariantResolver))>[
    ('read_twice', (r) => ReadTwiceSurface(resolver: r)),
    ('read_twice_framed', (r) => ReadTwiceFramedSurface(resolver: r)),
  ]) {
    testWidgets('$id: each placement renders', (tester) async {
      for (final (path, resolver) in [
        ('delivered', _Resolver(_blob(_design(id)))),
        ('fallback', const _Resolver(null)),
      ]) {
        tallyStates = 0;
        await tester.pumpWidget(const SizedBox());
        await tester
            .pumpWidget(MaterialApp(home: Scaffold(body: surface(resolver))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: path);
        expect(
            _texts(tester).where((text) => text!.startsWith('tally')).length, 2,
            reason: path);
      }
    });
  }
}
