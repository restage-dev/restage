import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'restage_shifted_box.dart';

/// An [Align] that keeps derived sizes and child offsets finite.
class RestageAlign extends Align {
  /// Creates an alignment widget.
  const RestageAlign({
    super.key,
    super.alignment = Alignment.center,
    super.widthFactor,
    super.heightFactor,
    super.child,
  });

  @override
  RenderPositionedBox createRenderObject(BuildContext context) =>
      RestageRenderPositionedBox(
        alignment: alignment,
        widthFactor: widthFactor,
        heightFactor: heightFactor,
        textDirection: Directionality.maybeOf(context),
      );
}

/// A [Center] that keeps derived sizes finite.
class RestageCenter extends Center {
  /// Creates a widget that centers its child.
  const RestageCenter({
    super.key,
    super.widthFactor,
    super.heightFactor,
    super.child,
  });

  @override
  RenderPositionedBox createRenderObject(BuildContext context) =>
      RestageRenderPositionedBox(
        widthFactor: widthFactor,
        heightFactor: heightFactor,
        textDirection: Directionality.maybeOf(context),
      );
}
