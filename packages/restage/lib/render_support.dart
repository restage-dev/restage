/// Runtime pieces that preview and render hosts share with the SDK: frame
/// geometry for drawn widgets and the built-in icon table.
library;

export 'src/runtime/builtin_icon_table.dart' show addBuiltInIconTable;
export 'src/runtime/render_geometry.dart'
    show
        GeometryPostFrameScheduler,
        GeometryRenderBoxBinding,
        geometryBoundsInFrame,
        geometryDrawnOrder,
        geometryTransformToFrame;
