import 'flow_source.dart';

/// Deprecated alias for [ScreenSource].
///
/// Onboarding screens are flow screens; author them with `@ScreenSource`. This
/// alias keeps existing `@OnboardingSource(...)` call-sites compiling.
@Deprecated('Use @ScreenSource instead.')
typedef OnboardingSource = ScreenSource;

/// Deprecated alias for [FlowSource].
///
/// Onboarding flows are flows; author them with `@FlowSource`. This alias keeps
/// existing `@OnboardingFlow(...)` call-sites compiling.
@Deprecated('Use @FlowSource instead.')
typedef OnboardingFlow = FlowSource;
