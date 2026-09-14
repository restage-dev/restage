import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/native_flow.restage.g.dart';

@Screen(id: 'native_welcome')
final class NativeWelcome extends StatefulWidget {
  const NativeWelcome({super.key});
  static const next = SurfaceEvent<void>('next');

  @override
  State<NativeWelcome> createState() => _NativeWelcomeState();
}

final class _NativeWelcomeState extends State<NativeWelcome> {
  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: surfaceEvent(NativeWelcome.next),
        child: const Text('Welcome original'),
      );
}

@Screen(id: 'native_preferences')
final class NativePreferences extends StatelessWidget {
  const NativePreferences({super.key});
  static const done = SurfaceEvent<void>('done');

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: surfaceEvent(done),
        child: const Text('Preferences original'),
      );
}

@Paywall(id: 'native_offer')
final class NativeOffer extends StatelessWidget {
  const NativeOffer({super.key});

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: paywallEvent('skip'),
        child: const Text('Offer original'),
      );
}

@FlowGraph(id: 'native_offer_flow', surface: Surface.onboarding)
const nativeOfferFlow = FlowDefinition(
  start: NativeOffer,
  transitions: [Transition.complete(PaywallEvents.skip, from: NativeOffer)],
);

const completed = FlowStateRef<bool>('completed',
    defaultValue: false, classification: FlowStateClassification.exportable);
const permission = FlowActionRef<void, bool>('permission');
const finish = Completion('done', result: {'completed': true});
const offer = Subflow('offer', flow: nativeOfferFlow, onComplete: finish);

@FlowGraph(id: 'native_welcome_flow', surface: Surface.onboarding)
final nativeWelcomeFlow = FlowDefinition(
  start: NativeWelcome,
  state: [completed],
  outbound: const FlowOutboundPolicy(terminalResult: {'completed': completed}),
  transitions: [
    Transition(
      NativeWelcome.next,
      to: NativePreferences,
      action: permission.continueWhen((granted) => granted),
    ),
    Transition(NativePreferences.done,
        to: offer, writes: [completed.set(true)]),
  ],
);

@Screen(id: 'native_named')
final class NativeNamed extends StatelessWidget {
  const NativeNamed({required this.title, super.key});
  final String title;
  static const done = SurfaceEvent<void>('done');

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: surfaceEvent(done),
        child: Text(title),
      );
}

@FlowGraph(id: 'native_named_flow', surface: Surface.general)
const nativeNamedFlow = FlowDefinition(
  start: NativeNamed,
  transitions: [Transition.complete(NativeNamed.done)],
);

@FlowGraph(id: 'native_class_flow', surface: Surface.onboarding)
final class NativeClassFlow extends RestageFlow {
  const NativeClassFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');
    return flow(
      initial: nativePreferencesRef,
      states: [
        screen(nativePreferencesRef).on(NativePreferences.done).goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
