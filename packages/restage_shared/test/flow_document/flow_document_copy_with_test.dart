import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

/// A document with a distinct non-default value on EVERY field, so a
/// `copyWith` that forgets a field is caught: the forgotten field falls back to
/// its constructor default and the per-field assertion fails.
FlowDocument _fullDoc() => FlowDocument(
      flow: 'onboardingFlow',
      version: 7,
      schemaVersion: 3,
      minClient: 5,
      initial: 'welcome',
      actions: {
        'submit': const FlowActionContract(
          actionName: 'submit',
          contractVersion: 2,
          argsSchema: FlowActionSchema.object({}),
          resultSchema: FlowActionSchema.bool(),
          minClient: 4,
          idempotent: true,
        ),
      },
      flowState: const {
        'inviteCode': FlowStateDeclaration(
          type: FlowDataType.string,
          classification: FlowStateClassification.persistedDevice,
          defaultValue: 'seed',
          hostSeedable: true,
        ),
      },
      outbound: const FlowOutboundDeclarations(
        terminalResult: FlowOutboundPayloadDeclaration(
          fields: {
            'done': FlowOutboundField(
              type: FlowDataType.bool,
              ref: EventFlowOutboundRef(key: 'done'),
            ),
          },
        ),
      ),
      legacyTerminalResultPassthrough: true,
      screenArtifacts: {
        'welcome': ScreenArtifact(
          path: 'welcome.rfw',
          version: 1,
          schemaVersion: 1,
          minClient: 1,
          contentHash: FlowContentHash.compute(<int>[1, 2, 3]),
        ),
      },
      states: const {
        'welcome': ScreenFlowState(
          screen: 'welcome',
          on: {'next': FlowTransition.goto('done')},
        ),
        'done': EndFlowState(result: {'ok': true}),
      },
      unsupportedFeatures: const {'futureThing'},
      deliveryMode: FlowDeliveryMode.general,
    );

void main() {
  group('FlowDocument.copyWith', () {
    test('with no arguments preserves EVERY field (close-the-class guard)', () {
      final doc = _fullDoc();
      final copy = doc.copyWith();

      // Scalars / enums must survive verbatim — a copyWith that omits any of
      // these would default it, failing here.
      expect(copy.flow, doc.flow);
      expect(copy.version, doc.version);
      expect(copy.schemaVersion, doc.schemaVersion);
      expect(copy.minClient, doc.minClient);
      expect(copy.initial, doc.initial);
      expect(copy.legacyTerminalResultPassthrough, isTrue);
      expect(copy.deliveryMode, doc.deliveryMode);
      expect(copy.deliveryMode, FlowDeliveryMode.general);

      // Reference-typed fields ride through by reference (`?? this.field`).
      expect(copy.actions, same(doc.actions));
      expect(copy.flowState, same(doc.flowState));
      expect(copy.outbound, same(doc.outbound));
      expect(copy.screenArtifacts, same(doc.screenArtifacts));
      expect(copy.states, same(doc.states));
      expect(copy.unsupportedFeatures, same(doc.unsupportedFeatures));
    });

    test('overrides only the supplied fields, leaving the rest untouched', () {
      final doc = _fullDoc();
      final copy = doc.copyWith(
        version: 99,
        deliveryMode: FlowDeliveryMode.typed,
      );

      expect(copy.version, 99);
      expect(copy.deliveryMode, FlowDeliveryMode.typed);
      // Everything else is unchanged.
      expect(copy.flow, doc.flow);
      expect(copy.schemaVersion, doc.schemaVersion);
      expect(copy.minClient, doc.minClient);
      expect(copy.initial, doc.initial);
      expect(copy.legacyTerminalResultPassthrough, isTrue);
      expect(copy.actions, same(doc.actions));
      expect(copy.states, same(doc.states));
      expect(copy.outbound, same(doc.outbound));
    });
  });
}
