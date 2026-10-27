import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// The guarded replacement for an exact catalog constructor, if any.
///
/// Replacement widgets retain required runtime guards, but cannot expose the
/// original Flutter widget as a native key owner.
String? runtimeRealizationFor(WidgetEntry entry) {
  final realization = _runtimeRealizationByWidget[entry.name];
  return realization != null &&
          realization.namespace == entry.library.namespace &&
          realization.flutterType == entry.flutterType
      ? realization.className
      : null;
}

typedef _RuntimeRealization = ({
  String className,
  String flutterType,
  String namespace,
});

/// Runtime classes for built-ins that need guarded framework behavior, matched
/// by namespace, widget name, and source type.
const Map<String, _RuntimeRealization> _runtimeRealizationByWidget = {
  'Align': (
    className: 'RestageAlign',
    flutterType: 'package:flutter/src/widgets/basic.dart#Align',
    namespace: 'restage.core',
  ),
  'AnimatedAlign': (
    className: 'RestageAnimatedAlign',
    flutterType:
        'package:flutter/src/widgets/implicit_animations.dart#AnimatedAlign',
    namespace: 'restage.core',
  ),
  'AnimatedPadding': (
    className: 'RestageAnimatedPadding',
    flutterType:
        'package:flutter/src/widgets/implicit_animations.dart#AnimatedPadding',
    namespace: 'restage.core',
  ),
  'AnimatedSize': (
    className: 'RestageAnimatedSize',
    flutterType: 'package:flutter/src/widgets/animated_size.dart#AnimatedSize',
    namespace: 'restage.core',
  ),
  'AspectRatio': (
    className: 'RestageAspectRatio',
    flutterType: 'package:flutter/src/widgets/basic.dart#AspectRatio',
    namespace: 'restage.core',
  ),
  'Center': (
    className: 'RestageCenter',
    flutterType: 'package:flutter/src/widgets/basic.dart#Center',
    namespace: 'restage.core',
  ),
  'Column': (
    className: 'RestageColumn',
    flutterType: 'package:flutter/src/widgets/basic.dart#Column',
    namespace: 'restage.core',
  ),
  'FittedBox': (
    className: 'RestageFittedBox',
    flutterType: 'package:flutter/src/widgets/basic.dart#FittedBox',
    namespace: 'restage.core',
  ),
  'FadeInImageAssetNetwork': (
    className: 'RestageFadeInImage.assetNetwork',
    flutterType:
        'package:flutter/src/widgets/fade_in_image.dart#FadeInImage.assetNetwork',
    namespace: 'restage.core',
  ),
  'FractionallySizedBox': (
    className: 'RestageFractionallySizedBox',
    flutterType: 'package:flutter/src/widgets/basic.dart#FractionallySizedBox',
    namespace: 'restage.core',
  ),
  'IntrinsicWidth': (
    className: 'RestageIntrinsicWidth',
    flutterType: 'package:flutter/src/widgets/basic.dart#IntrinsicWidth',
    namespace: 'restage.core',
  ),
  'ListView': (
    className: 'RestageListView',
    flutterType: 'package:flutter/src/widgets/scroll_view.dart#ListView',
    namespace: 'restage.core',
  ),
  'Image': (
    className: 'RestageImage.network',
    flutterType: 'package:flutter/src/widgets/image.dart#Image.network',
    namespace: 'restage.core',
  ),
  'ImageAsset': (
    className: 'RestageImage.asset',
    flutterType: 'package:flutter/src/widgets/image.dart#Image.asset',
    namespace: 'restage.core',
  ),
  'Padding': (
    className: 'RestagePadding',
    flutterType: 'package:flutter/src/widgets/basic.dart#Padding',
    namespace: 'restage.core',
  ),
  'Row': (
    className: 'RestageRow',
    flutterType: 'package:flutter/src/widgets/basic.dart#Row',
    namespace: 'restage.core',
  ),
  'Stack': (
    className: 'RestageStack',
    flutterType: 'package:flutter/src/widgets/basic.dart#Stack',
    namespace: 'restage.core',
  ),
  'Wrap': (
    className: 'RestageWrap',
    flutterType: 'package:flutter/src/widgets/basic.dart#Wrap',
    namespace: 'restage.core',
  ),
};
