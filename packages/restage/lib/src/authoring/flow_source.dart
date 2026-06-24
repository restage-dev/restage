import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart'
    show kBaselineCatalogVersion;

/// Marks a class as a flow screen source for `restage_codegen`.
///
/// A flow screen is a single screen in a multi-screen flow — onboarding,
/// surveys, in-app messages, or a paywall flow. Authored classes extend
/// `StatelessWidget` (or a supported `StatefulWidget`) and declare their
/// graph transitions with static event markers. The codegen walks annotated
/// classes at build time and emits a matching screen descriptor + `.rfw`
/// artifact.
///
/// Example:
/// ```dart
/// @ScreenSource(id: 'welcome')
/// class WelcomeScreen extends StatelessWidget {
///   static const next = OnboardingEvent<void>('next');
///
///   @override
///   Widget build(BuildContext context) => Center(
///     child: ElevatedButton(
///       onPressed: onboardingEvent(next),
///       child: const Text('Continue'),
///     ),
///   );
/// }
/// ```
@immutable
final class ScreenSource {
  /// Creates a flow screen source annotation.
  const ScreenSource({
    required this.id,
    this.version = 1,
    this.minClient = kBaselineCatalogVersion,
  });

  /// Stable flow screen identifier.
  final String id;

  /// Descriptor version emitted for this screen.
  final int version;

  /// Minimum client descriptor version that can load this screen.
  final int minClient;
}

/// Marks a class as a flow graph source for `restage_codegen`.
///
/// A flow graph composes flow screens into a multi-screen experience —
/// onboarding, surveys, in-app messages, or a paywall flow. Authored classes
/// extend `RestageFlow` and describe their states and transitions in
/// `buildFlow()`. The codegen walks annotated classes at build time and emits a
/// typed flow descriptor + a canonical flow document.
///
/// Example:
/// ```dart
/// @FlowSource(id: 'first_run')
/// final class FirstRunFlow extends RestageFlow {
///   const FirstRunFlow();
///
///   @override
///   FlowDef buildFlow() {
///     final done = endState('done');
///     return flow(
///       initial: WelcomeScreenDescriptor.ref,
///       states: [
///         screen(WelcomeScreenDescriptor.ref)
///             .on(WelcomeScreen.next)
///             .goTo(done),
///         end(done, result: {'completed': true}),
///       ],
///     );
///   }
/// }
/// ```
@immutable
final class FlowSource {
  /// Creates a flow graph source annotation.
  const FlowSource({
    required this.id,
    this.version = 1,
    this.minClient = kBaselineCatalogVersion,
  });

  /// Stable flow graph identifier.
  final String id;

  /// Descriptor version emitted for this flow.
  final int version;

  /// Minimum client descriptor version that can load this flow.
  final int minClient;
}
