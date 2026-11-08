import 'package:flutter/material.dart';

import 'flows/bare_surface.dart';

/// Hosts one screen with no required event or terminal result.
class BareSurfaceDemo extends StatelessWidget {
  /// Creates the bare surface gallery host.
  const BareSurfaceDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return BareSurfaceFlowSurface();
  }
}
