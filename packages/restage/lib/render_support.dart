/// Runtime pieces that preview and render hosts share with the SDK: frame
/// geometry for drawn widgets, the built-in icon table, and the render data a
/// paywall was given.
library;

export 'src/runtime/builtin_icon_table.dart' show addBuiltInIconTable;
export 'src/runtime/render_geometry.dart'
    show
        GeometryPostFrameScheduler,
        GeometryRenderBoxBinding,
        geometryBoundsInFrame,
        geometryDrawnOrder,
        geometryTransformToFrame;
export 'src/runtime/restage_paywall.dart' show paywallHostContext;
