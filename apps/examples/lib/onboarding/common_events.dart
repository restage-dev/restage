import 'package:restage/restage.dart';

/// Events more than one surface fires, declared once so every surface and
/// every host names the same event.
abstract final class CommonEvents {
  /// Dismisses the surface. The app handles it by closing the surface.
  static const dismiss = SurfaceEvent<void>('dismiss');
}
