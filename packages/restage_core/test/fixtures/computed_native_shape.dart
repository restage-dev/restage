import 'package:flutter/widgets.dart';

class NativeShapeProbe extends StatelessWidget {
  const NativeShapeProbe({super.key, this.shape});
  final ShapeBorder? shape;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

Widget computedNativeShape() => LayoutBuilder(
      builder: (context, constraints) => NativeShapeProbe(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(constraints.maxWidth / 10),
        ),
      ),
    );

Widget directNativeShape(double width) => NativeShapeProbe(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(width / 10),
      ),
    );

class NativeShapeScreen extends StatelessWidget {
  const NativeShapeScreen({super.key, required this.width});
  final double width;
  @override
  Widget build(BuildContext context) => NativeShapeProbe(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(width / 10),
        ),
      );
}
