/// Material design widgets for Restage paywalls. Authoritative metadata
/// lives in [registry.dart] (`kRegistry`); the runtime registers its
/// widgets with rfw via [library_registration.dart]
/// (`buildMaterialWidgetLibrary`). Both are read by codegen, the editor,
/// and the SDK runtime.
library;

export 'library_registration.dart';
export 'registry.dart';
export 'src/widgets/express_checkout_button.dart';
export 'src/widgets/restage_draggable_sheet.dart';
export 'src/widgets/restage_dropdown.dart';
export 'src/widgets/restage_modal_sheet.dart';
export 'src/widgets/restage_pager.dart';
export 'src/widgets/restage_radio_group.dart';
export 'src/widgets/restage_segmented_button.dart';
export 'src/widgets/restage_toggle_buttons.dart';
export 'src/widgets/package.dart';
