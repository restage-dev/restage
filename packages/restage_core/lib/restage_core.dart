/// Cross-platform widget primitives for Restage paywalls. Authoritative
/// metadata lives in [registry.dart] (`kRegistry`); the runtime registers
/// its widgets with rfw via [library_registration.dart]
/// (`buildCoreWidgetLibrary`). Both are read by codegen, the editor, and
/// the SDK runtime.
library;

export 'library_registration.dart';
export 'registry.dart';
export 'src/runtime/decoders.dart';
export 'src/runtime/theme_binding_resolver.dart';
export 'src/widgets/restage_fade_in.dart';
export 'src/widgets/restage_formatted_number.dart';
export 'src/widgets/restage_motion.dart';
export 'src/widgets/restage_pulse.dart';
// Only the named-preset enum is public; the spring-math helper stays internal.
export 'src/widgets/restage_spring.dart' show RestageSpring;
export 'src/widgets/restage_stagger.dart';
