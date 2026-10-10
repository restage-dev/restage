/// Cross-platform widget primitives for Restage paywalls. Authoritative
/// metadata lives in [registry.dart] (`kRegistry`); the runtime registers
/// its widgets with rfw via [library_registration.dart]
/// (`buildCoreWidgetLibrary`). Both are read by codegen, the editor, and
/// the SDK runtime.
library;

export 'library_registration.dart';
export 'registry.dart';
export 'src/runtime/decoders.dart';
export 'src/runtime/icon_table.dart';
export 'src/runtime/theme_binding_resolver.dart';
export 'src/widgets/restage_align.dart' show RestageAlign, RestageCenter;
export 'src/widgets/restage_animated_align.dart' show RestageAnimatedAlign;
export 'src/widgets/restage_padding.dart'
    show RestageAnimatedPadding, RestagePadding;
export 'src/widgets/restage_stack.dart' show RestageStack;
export 'src/widgets/restage_animated_size.dart' show RestageAnimatedSize;
export 'src/widgets/restage_aspect_ratio.dart' show RestageAspectRatio;
export 'src/widgets/restage_fade_in.dart';
export 'src/widgets/restage_fitted_box.dart' show RestageFittedBox;
export 'src/widgets/restage_flex.dart' show RestageRow, RestageColumn;
export 'src/widgets/restage_wrap.dart' show RestageWrap;
export 'src/widgets/restage_fractionally_sized_box.dart'
    show RestageFractionallySizedBox;
export 'src/widgets/restage_formatted_number.dart';
export 'src/widgets/restage_intrinsic_width.dart' show RestageIntrinsicWidth;
export 'src/widgets/restage_image.dart' show RestageFadeInImage, RestageImage;
export 'src/widgets/restage_list_view.dart' show RestageListView;
export 'src/widgets/restage_motion.dart';
export 'src/widgets/restage_pulse.dart';
// Only the named-preset enum is public; the spring-math helper stays internal.
export 'src/widgets/restage_spring.dart' show RestageSpring;
export 'src/widgets/restage_stagger.dart';
