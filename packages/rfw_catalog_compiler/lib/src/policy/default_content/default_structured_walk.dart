// packages/rfw_catalog_compiler/lib/src/policy/default_content/default_structured_walk.dart

/// Concrete value types the walker recurses INTO when expanding
/// structured property surfaces. Each entry is the canonical
/// `<library identifier>#<class name>` for a Flutter / Dart core type
/// whose constructor parameters round-trip cleanly through the
/// catalog wire format.
const Set<String> kBuiltInStructuredConcrete = {
  'package:flutter/src/painting/box_decoration.dart#BoxDecoration',
  'package:flutter/src/rendering/box.dart#BoxConstraints',
  'package:flutter/src/painting/text_style.dart#TextStyle',
  'package:flutter/src/painting/border_radius.dart#BorderRadius',
  'package:flutter/src/painting/edge_insets.dart#EdgeInsets',
  'dart:ui#Color',
  'package:flutter/src/painting/box_shadow.dart#BoxShadow',
  'package:flutter/src/painting/borders.dart#BorderSide',
  'package:flutter/src/painting/rounded_rectangle_border.dart#RoundedRectangleBorder',
  'package:flutter/src/painting/rounded_rectangle_border.dart#RoundedSuperellipseBorder',
  'package:flutter/src/painting/circle_border.dart#CircleBorder',
  'package:flutter/src/painting/stadium_border.dart#StadiumBorder',
  'package:flutter/src/painting/continuous_rectangle_border.dart#ContinuousRectangleBorder',
  'package:flutter/src/painting/beveled_rectangle_border.dart#BeveledRectangleBorder',
  'package:flutter/src/painting/linear_border.dart#LinearBorder',
  'package:flutter/src/painting/linear_border.dart#LinearBorderEdge',
  'package:flutter/src/painting/star_border.dart#StarBorder',
  'package:flutter/src/painting/box_border.dart#Border',
  'package:flutter/src/painting/alignment.dart#Alignment',
  'dart:ui#Offset',
  'dart:ui#Size',
  'dart:ui#Radius',
  'package:flutter/src/widgets/icon_data.dart#IconData',
  'dart:core#Duration',
};

/// Abstract base types the walker short-circuits on. Subtype
/// dispatch is handled by the union registry; the walker should not
/// attempt to recurse INTO an abstract base's parameter surface.
const Set<String> kBuiltInStructuredAbstract = {
  'package:flutter/src/painting/gradient.dart#Gradient',
  'package:flutter/src/painting/decoration.dart#Decoration',
  'package:flutter/src/painting/borders.dart#ShapeBorder',
  'package:flutter/src/painting/borders.dart#OutlinedBorder',
  'package:flutter/src/painting/box_border.dart#BoxBorder',
  'package:flutter/src/material/input_border.dart#InputBorder',
};

/// Default maximum recursion depth for the structured walker.
const int kBuiltInStructuredMaxDepth = 8;
