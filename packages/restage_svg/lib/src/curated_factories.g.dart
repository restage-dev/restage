// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
import 'package:flutter/widgets.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/rfw.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart'
    show WidgetBuilderContract, WidgetBuilderParameter;
import 'package:flutter_svg/svg.dart' as restageLibrary3;
import 'package:flutter/painting.dart' as restageLibrary2;
import 'dart:ui' as restageLibrary0;
import 'package:vector_graphics/src/vector_graphics.dart' as restageLibrary5;
import 'package:restage_svg/src/native_values.dart' as restageLibrary4;

Widget _buildSvgPictureAsset(BuildContext context, DataSource source) {
  source = RestageValueBinding.dataSource(source, context);
  return RestageBuilderBinding.construct((builderBindings) {
    final restagePresenceAlignment = RestageRfwConstructorPresence.read(
      source,
      <Object>['alignment'],
    );
    final restageBuilderBindingplaceholderBuilder =
        RestageBuilderBinding.optional(
            source, const <Object>['placeholderBuilder'],
            contract: const WidgetBuilderContract(
                parameters: [WidgetBuilderParameter.buildContext],
                nullableResult: false));
    if (restageBuilderBindingplaceholderBuilder != null)
      builderBindings.add(restageBuilderBindingplaceholderBuilder);

    return Function.apply(
      restageLibrary3.SvgPicture.asset,
      <Object?>[
        RestageDecoders.string(source, <Object>['assetName'],
                context: context) ??
            (throw ArgumentError('SvgPictureAsset.assetName is required.')),
      ],
      <Symbol, Object?>{
        #key: RestageDecoders.nativeBinding<Key>(
            context, source, <Object>['key'],
            type: 'flutter.Key'),
        #matchTextDirection: RestageValueBinding.read<bool>(
                source, const <Object>['matchTextDirection'], context) ??
            false,
        #bundle: restageLibrary4.SvgNativeValues.assetBundle(
            context, source, <Object>['bundle']),
        #package: RestageDecoders.string(source, <Object>['package'],
            context: context),
        #width: RestageValueBinding.read<double>(
            source, const <Object>['width'], context),
        #height: RestageValueBinding.read<double>(
            source, const <Object>['height'], context),
        #fit: RestageDecoders.enumByName<restageLibrary2.BoxFit>(
                restageLibrary2.BoxFit.values, source, <Object>['fit']) ??
            restageLibrary2.BoxFit.contain,
        if (restagePresenceAlignment.supplied)
          #alignment: RestageDecoders.alignment(
              source, restagePresenceAlignment.valuePath),
        #allowDrawingOutsideViewBox: RestageValueBinding.read<bool>(source,
                const <Object>['allowDrawingOutsideViewBox'], context) ??
            false,
        #placeholderBuilder: restageBuilderBindingplaceholderBuilder == null
            ? null
            : (BuildContext arg0) =>
                restageBuilderBindingplaceholderBuilder.build(arg0, {}),
        #semanticsLabel: RestageDecoders.string(
            source, <Object>['semanticsLabel'],
            context: context),
        #excludeFromSemantics: RestageValueBinding.read<bool>(
                source, const <Object>['excludeFromSemantics'], context) ??
            false,
        #clipBehavior: RestageDecoders.enumByName<restageLibrary0.Clip>(
                restageLibrary0.Clip.values,
                source,
                <Object>['clipBehavior']) ??
            restageLibrary0.Clip.hardEdge,
        #errorBuilder: restageLibrary4.SvgNativeValues.errorBuilder(
            context, source, <Object>['errorBuilder']),
        #imageBuilder: restageLibrary4.SvgNativeValues.imageBuilder(
            context, source, <Object>['imageBuilder']),
        #theme:
            restageLibrary4.SvgNativeValues.theme(source, <Object>['theme']),
        #colorMapper: restageLibrary4.SvgNativeValues.colorMapper(
            context, source, <Object>['colorMapper']),
        #colorFilter: restageLibrary4.SvgNativeValues.colorFilter(
            source, <Object>['colorFilter']),
        #color: RestageDecoders.color(source, <Object>['color']),
        #colorBlendMode: RestageDecoders.enumByName<restageLibrary0.BlendMode>(
                restageLibrary0.BlendMode.values,
                source,
                <Object>['colorBlendMode']) ??
            restageLibrary0.BlendMode.srcIn,
        #cacheColorFilter: RestageValueBinding.read<bool>(
                source, const <Object>['cacheColorFilter'], context) ??
            false,
        #renderingStrategy:
            RestageDecoders.enumByName<restageLibrary5.RenderingStrategy>(
                    restageLibrary5.RenderingStrategy.values,
                    source,
                    <Object>['renderingStrategy']) ??
                restageLibrary5.RenderingStrategy.picture,
      },
    ) as Widget;
  });
}

Widget _buildSvgPictureNetwork(BuildContext context, DataSource source) {
  source = RestageValueBinding.dataSource(source, context);
  return RestageBuilderBinding.construct((builderBindings) {
    final restagePresenceAlignment = RestageRfwConstructorPresence.read(
      source,
      <Object>['alignment'],
    );
    final restageBuilderBindingplaceholderBuilder =
        RestageBuilderBinding.optional(
            source, const <Object>['placeholderBuilder'],
            contract: const WidgetBuilderContract(
                parameters: [WidgetBuilderParameter.buildContext],
                nullableResult: false));
    if (restageBuilderBindingplaceholderBuilder != null)
      builderBindings.add(restageBuilderBindingplaceholderBuilder);

    return Function.apply(
      restageLibrary3.SvgPicture.network,
      <Object?>[
        RestageDecoders.string(source, <Object>['url'], context: context) ??
            (throw ArgumentError('SvgPictureNetwork.url is required.')),
      ],
      <Symbol, Object?>{
        #key: RestageDecoders.nativeBinding<Key>(
            context, source, <Object>['key'],
            type: 'flutter.Key'),
        #headers: restageLibrary4.SvgNativeValues.headers(
            source, <Object>['headers']),
        #width: RestageValueBinding.read<double>(
            source, const <Object>['width'], context),
        #height: RestageValueBinding.read<double>(
            source, const <Object>['height'], context),
        #fit: RestageDecoders.enumByName<restageLibrary2.BoxFit>(
                restageLibrary2.BoxFit.values, source, <Object>['fit']) ??
            restageLibrary2.BoxFit.contain,
        if (restagePresenceAlignment.supplied)
          #alignment: RestageDecoders.alignment(
              source, restagePresenceAlignment.valuePath),
        #matchTextDirection: RestageValueBinding.read<bool>(
                source, const <Object>['matchTextDirection'], context) ??
            false,
        #allowDrawingOutsideViewBox: RestageValueBinding.read<bool>(source,
                const <Object>['allowDrawingOutsideViewBox'], context) ??
            false,
        #placeholderBuilder: restageBuilderBindingplaceholderBuilder == null
            ? null
            : (BuildContext arg0) =>
                restageBuilderBindingplaceholderBuilder.build(arg0, {}),
        #colorFilter: restageLibrary4.SvgNativeValues.colorFilter(
            source, <Object>['colorFilter']),
        #color: RestageDecoders.color(source, <Object>['color']),
        #colorBlendMode: RestageDecoders.enumByName<restageLibrary0.BlendMode>(
                restageLibrary0.BlendMode.values,
                source,
                <Object>['colorBlendMode']) ??
            restageLibrary0.BlendMode.srcIn,
        #semanticsLabel: RestageDecoders.string(
            source, <Object>['semanticsLabel'],
            context: context),
        #excludeFromSemantics: RestageValueBinding.read<bool>(
                source, const <Object>['excludeFromSemantics'], context) ??
            false,
        #clipBehavior: RestageDecoders.enumByName<restageLibrary0.Clip>(
                restageLibrary0.Clip.values,
                source,
                <Object>['clipBehavior']) ??
            restageLibrary0.Clip.hardEdge,
        #errorBuilder: restageLibrary4.SvgNativeValues.errorBuilder(
            context, source, <Object>['errorBuilder']),
        #imageBuilder: restageLibrary4.SvgNativeValues.imageBuilder(
            context, source, <Object>['imageBuilder']),
        #cacheColorFilter: RestageValueBinding.read<bool>(
                source, const <Object>['cacheColorFilter'], context) ??
            false,
        #theme:
            restageLibrary4.SvgNativeValues.theme(source, <Object>['theme']),
        #colorMapper: restageLibrary4.SvgNativeValues.colorMapper(
            context, source, <Object>['colorMapper']),
        #httpClient: restageLibrary4.SvgNativeValues.httpClient(
            context, source, <Object>['httpClient']),
        #renderingStrategy:
            RestageDecoders.enumByName<restageLibrary5.RenderingStrategy>(
                    restageLibrary5.RenderingStrategy.values,
                    source,
                    <Object>['renderingStrategy']) ??
                restageLibrary5.RenderingStrategy.picture,
      },
    ) as Widget;
  });
}

Widget _buildSvgPictureString(BuildContext context, DataSource source) {
  source = RestageValueBinding.dataSource(source, context);
  return RestageBuilderBinding.construct((builderBindings) {
    final restagePresenceAlignment = RestageRfwConstructorPresence.read(
      source,
      <Object>['alignment'],
    );
    final restageBuilderBindingplaceholderBuilder =
        RestageBuilderBinding.optional(
            source, const <Object>['placeholderBuilder'],
            contract: const WidgetBuilderContract(
                parameters: [WidgetBuilderParameter.buildContext],
                nullableResult: false));
    if (restageBuilderBindingplaceholderBuilder != null)
      builderBindings.add(restageBuilderBindingplaceholderBuilder);

    return Function.apply(
      restageLibrary3.SvgPicture.string,
      <Object?>[
        RestageDecoders.string(source, <Object>['string'], context: context) ??
            (throw ArgumentError('SvgPictureString.string is required.')),
      ],
      <Symbol, Object?>{
        #key: RestageDecoders.nativeBinding<Key>(
            context, source, <Object>['key'],
            type: 'flutter.Key'),
        #width: RestageValueBinding.read<double>(
            source, const <Object>['width'], context),
        #height: RestageValueBinding.read<double>(
            source, const <Object>['height'], context),
        #fit: RestageDecoders.enumByName<restageLibrary2.BoxFit>(
                restageLibrary2.BoxFit.values, source, <Object>['fit']) ??
            restageLibrary2.BoxFit.contain,
        if (restagePresenceAlignment.supplied)
          #alignment: RestageDecoders.alignment(
              source, restagePresenceAlignment.valuePath),
        #matchTextDirection: RestageValueBinding.read<bool>(
                source, const <Object>['matchTextDirection'], context) ??
            false,
        #allowDrawingOutsideViewBox: RestageValueBinding.read<bool>(source,
                const <Object>['allowDrawingOutsideViewBox'], context) ??
            false,
        #placeholderBuilder: restageBuilderBindingplaceholderBuilder == null
            ? null
            : (BuildContext arg0) =>
                restageBuilderBindingplaceholderBuilder.build(arg0, {}),
        #colorFilter: restageLibrary4.SvgNativeValues.colorFilter(
            source, <Object>['colorFilter']),
        #color: RestageDecoders.color(source, <Object>['color']),
        #colorBlendMode: RestageDecoders.enumByName<restageLibrary0.BlendMode>(
                restageLibrary0.BlendMode.values,
                source,
                <Object>['colorBlendMode']) ??
            restageLibrary0.BlendMode.srcIn,
        #semanticsLabel: RestageDecoders.string(
            source, <Object>['semanticsLabel'],
            context: context),
        #excludeFromSemantics: RestageValueBinding.read<bool>(
                source, const <Object>['excludeFromSemantics'], context) ??
            false,
        #clipBehavior: RestageDecoders.enumByName<restageLibrary0.Clip>(
                restageLibrary0.Clip.values,
                source,
                <Object>['clipBehavior']) ??
            restageLibrary0.Clip.hardEdge,
        #errorBuilder: restageLibrary4.SvgNativeValues.errorBuilder(
            context, source, <Object>['errorBuilder']),
        #imageBuilder: restageLibrary4.SvgNativeValues.imageBuilder(
            context, source, <Object>['imageBuilder']),
        #theme:
            restageLibrary4.SvgNativeValues.theme(source, <Object>['theme']),
        #colorMapper: restageLibrary4.SvgNativeValues.colorMapper(
            context, source, <Object>['colorMapper']),
        #cacheColorFilter: RestageValueBinding.read<bool>(
                source, const <Object>['cacheColorFilter'], context) ??
            false,
        #renderingStrategy:
            RestageDecoders.enumByName<restageLibrary5.RenderingStrategy>(
                    restageLibrary5.RenderingStrategy.values,
                    source,
                    <Object>['renderingStrategy']) ??
                restageLibrary5.RenderingStrategy.picture,
      },
    ) as Widget;
  });
}

Widget _buildSvgPictureMemory(BuildContext context, DataSource source) {
  source = RestageValueBinding.dataSource(source, context);
  return RestageBuilderBinding.construct((builderBindings) {
    final restagePresenceAlignment = RestageRfwConstructorPresence.read(
      source,
      <Object>['alignment'],
    );
    final restageBuilderBindingplaceholderBuilder =
        RestageBuilderBinding.optional(
            source, const <Object>['placeholderBuilder'],
            contract: const WidgetBuilderContract(
                parameters: [WidgetBuilderParameter.buildContext],
                nullableResult: false));
    if (restageBuilderBindingplaceholderBuilder != null)
      builderBindings.add(restageBuilderBindingplaceholderBuilder);

    return Function.apply(
      restageLibrary3.SvgPicture.memory,
      <Object?>[
        restageLibrary4.SvgNativeValues.bytes(source, <Object>['bytes']) ??
            (throw ArgumentError('SvgPictureMemory.bytes is required.')),
      ],
      <Symbol, Object?>{
        #key: RestageDecoders.nativeBinding<Key>(
            context, source, <Object>['key'],
            type: 'flutter.Key'),
        #width: RestageValueBinding.read<double>(
            source, const <Object>['width'], context),
        #height: RestageValueBinding.read<double>(
            source, const <Object>['height'], context),
        #fit: RestageDecoders.enumByName<restageLibrary2.BoxFit>(
                restageLibrary2.BoxFit.values, source, <Object>['fit']) ??
            restageLibrary2.BoxFit.contain,
        if (restagePresenceAlignment.supplied)
          #alignment: RestageDecoders.alignment(
              source, restagePresenceAlignment.valuePath),
        #matchTextDirection: RestageValueBinding.read<bool>(
                source, const <Object>['matchTextDirection'], context) ??
            false,
        #allowDrawingOutsideViewBox: RestageValueBinding.read<bool>(source,
                const <Object>['allowDrawingOutsideViewBox'], context) ??
            false,
        #placeholderBuilder: restageBuilderBindingplaceholderBuilder == null
            ? null
            : (BuildContext arg0) =>
                restageBuilderBindingplaceholderBuilder.build(arg0, {}),
        #colorFilter: restageLibrary4.SvgNativeValues.colorFilter(
            source, <Object>['colorFilter']),
        #color: RestageDecoders.color(source, <Object>['color']),
        #colorBlendMode: RestageDecoders.enumByName<restageLibrary0.BlendMode>(
                restageLibrary0.BlendMode.values,
                source,
                <Object>['colorBlendMode']) ??
            restageLibrary0.BlendMode.srcIn,
        #semanticsLabel: RestageDecoders.string(
            source, <Object>['semanticsLabel'],
            context: context),
        #excludeFromSemantics: RestageValueBinding.read<bool>(
                source, const <Object>['excludeFromSemantics'], context) ??
            false,
        #clipBehavior: RestageDecoders.enumByName<restageLibrary0.Clip>(
                restageLibrary0.Clip.values,
                source,
                <Object>['clipBehavior']) ??
            restageLibrary0.Clip.hardEdge,
        #errorBuilder: restageLibrary4.SvgNativeValues.errorBuilder(
            context, source, <Object>['errorBuilder']),
        #imageBuilder: restageLibrary4.SvgNativeValues.imageBuilder(
            context, source, <Object>['imageBuilder']),
        #theme:
            restageLibrary4.SvgNativeValues.theme(source, <Object>['theme']),
        #colorMapper: restageLibrary4.SvgNativeValues.colorMapper(
            context, source, <Object>['colorMapper']),
        #cacheColorFilter: RestageValueBinding.read<bool>(
                source, const <Object>['cacheColorFilter'], context) ??
            false,
        #renderingStrategy:
            RestageDecoders.enumByName<restageLibrary5.RenderingStrategy>(
                    restageLibrary5.RenderingStrategy.values,
                    source,
                    <Object>['renderingStrategy']) ??
                restageLibrary5.RenderingStrategy.picture,
      },
    ) as Widget;
  });
}

Widget _buildSvgPicture(BuildContext context, DataSource source) {
  source = RestageValueBinding.dataSource(source, context);
  return RestageBuilderBinding.construct((builderBindings) {
    final restagePresenceAlignment = RestageRfwConstructorPresence.read(
      source,
      <Object>['alignment'],
    );
    final restageBuilderBindingplaceholderBuilder =
        RestageBuilderBinding.optional(
            source, const <Object>['placeholderBuilder'],
            contract: const WidgetBuilderContract(
                parameters: [WidgetBuilderParameter.buildContext],
                nullableResult: false));
    if (restageBuilderBindingplaceholderBuilder != null)
      builderBindings.add(restageBuilderBindingplaceholderBuilder);

    return Function.apply(
      restageLibrary3.SvgPicture.new,
      <Object?>[
        restageLibrary4.SvgNativeValues.loader(
                context, source, <Object>['bytesLoader']) ??
            (throw ArgumentError('SvgPicture.bytesLoader is required.')),
      ],
      <Symbol, Object?>{
        #key: RestageDecoders.nativeBinding<Key>(
            context, source, <Object>['key'],
            type: 'flutter.Key'),
        #width: RestageValueBinding.read<double>(
            source, const <Object>['width'], context),
        #height: RestageValueBinding.read<double>(
            source, const <Object>['height'], context),
        #fit: RestageDecoders.enumByName<restageLibrary2.BoxFit>(
                restageLibrary2.BoxFit.values, source, <Object>['fit']) ??
            restageLibrary2.BoxFit.contain,
        if (restagePresenceAlignment.supplied)
          #alignment: RestageDecoders.alignment(
              source, restagePresenceAlignment.valuePath),
        #matchTextDirection: RestageValueBinding.read<bool>(
                source, const <Object>['matchTextDirection'], context) ??
            false,
        #allowDrawingOutsideViewBox: RestageValueBinding.read<bool>(source,
                const <Object>['allowDrawingOutsideViewBox'], context) ??
            false,
        #placeholderBuilder: restageBuilderBindingplaceholderBuilder == null
            ? null
            : (BuildContext arg0) =>
                restageBuilderBindingplaceholderBuilder.build(arg0, {}),
        #colorFilter: restageLibrary4.SvgNativeValues.colorFilter(
            source, <Object>['colorFilter']),
        #semanticsLabel: RestageDecoders.string(
            source, <Object>['semanticsLabel'],
            context: context),
        #excludeFromSemantics: RestageValueBinding.read<bool>(
                source, const <Object>['excludeFromSemantics'], context) ??
            false,
        #clipBehavior: RestageDecoders.enumByName<restageLibrary0.Clip>(
                restageLibrary0.Clip.values,
                source,
                <Object>['clipBehavior']) ??
            restageLibrary0.Clip.hardEdge,
        #errorBuilder: restageLibrary4.SvgNativeValues.errorBuilder(
            context, source, <Object>['errorBuilder']),
        #imageBuilder: restageLibrary4.SvgNativeValues.imageBuilder(
            context, source, <Object>['imageBuilder']),
        #theme:
            restageLibrary4.SvgNativeValues.theme(source, <Object>['theme']),
        #cacheColorFilter: RestageValueBinding.read<bool>(
                source, const <Object>['cacheColorFilter'], context) ??
            false,
        #renderingStrategy:
            RestageDecoders.enumByName<restageLibrary5.RenderingStrategy>(
                    restageLibrary5.RenderingStrategy.values,
                    source,
                    <Object>['renderingStrategy']) ??
                restageLibrary5.RenderingStrategy.picture,
      },
    ) as Widget;
  });
}

Widget _buildSvgPictureFile(BuildContext context, DataSource source) {
  source = RestageValueBinding.dataSource(source, context);
  return RestageBuilderBinding.construct((builderBindings) {
    final restagePresenceAlignment = RestageRfwConstructorPresence.read(
      source,
      <Object>['alignment'],
    );
    final restageBuilderBindingplaceholderBuilder =
        RestageBuilderBinding.optional(
            source, const <Object>['placeholderBuilder'],
            contract: const WidgetBuilderContract(
                parameters: [WidgetBuilderParameter.buildContext],
                nullableResult: false));
    if (restageBuilderBindingplaceholderBuilder != null)
      builderBindings.add(restageBuilderBindingplaceholderBuilder);

    return Function.apply(
      restageLibrary3.SvgPicture.file,
      <Object?>[
        restageLibrary4.SvgNativeValues.file(
                context, source, <Object>['file']) ??
            (throw ArgumentError('SvgPictureFile.file is required.')),
      ],
      <Symbol, Object?>{
        #key: RestageDecoders.nativeBinding<Key>(
            context, source, <Object>['key'],
            type: 'flutter.Key'),
        #width: RestageValueBinding.read<double>(
            source, const <Object>['width'], context),
        #height: RestageValueBinding.read<double>(
            source, const <Object>['height'], context),
        #fit: RestageDecoders.enumByName<restageLibrary2.BoxFit>(
                restageLibrary2.BoxFit.values, source, <Object>['fit']) ??
            restageLibrary2.BoxFit.contain,
        if (restagePresenceAlignment.supplied)
          #alignment: RestageDecoders.alignment(
              source, restagePresenceAlignment.valuePath),
        #matchTextDirection: RestageValueBinding.read<bool>(
                source, const <Object>['matchTextDirection'], context) ??
            false,
        #allowDrawingOutsideViewBox: RestageValueBinding.read<bool>(source,
                const <Object>['allowDrawingOutsideViewBox'], context) ??
            false,
        #placeholderBuilder: restageBuilderBindingplaceholderBuilder == null
            ? null
            : (BuildContext arg0) =>
                restageBuilderBindingplaceholderBuilder.build(arg0, {}),
        #colorFilter: restageLibrary4.SvgNativeValues.colorFilter(
            source, <Object>['colorFilter']),
        #color: RestageDecoders.color(source, <Object>['color']),
        #colorBlendMode: RestageDecoders.enumByName<restageLibrary0.BlendMode>(
                restageLibrary0.BlendMode.values,
                source,
                <Object>['colorBlendMode']) ??
            restageLibrary0.BlendMode.srcIn,
        #semanticsLabel: RestageDecoders.string(
            source, <Object>['semanticsLabel'],
            context: context),
        #excludeFromSemantics: RestageValueBinding.read<bool>(
                source, const <Object>['excludeFromSemantics'], context) ??
            false,
        #clipBehavior: RestageDecoders.enumByName<restageLibrary0.Clip>(
                restageLibrary0.Clip.values,
                source,
                <Object>['clipBehavior']) ??
            restageLibrary0.Clip.hardEdge,
        #errorBuilder: restageLibrary4.SvgNativeValues.errorBuilder(
            context, source, <Object>['errorBuilder']),
        #imageBuilder: restageLibrary4.SvgNativeValues.imageBuilder(
            context, source, <Object>['imageBuilder']),
        #theme:
            restageLibrary4.SvgNativeValues.theme(source, <Object>['theme']),
        #colorMapper: restageLibrary4.SvgNativeValues.colorMapper(
            context, source, <Object>['colorMapper']),
        #cacheColorFilter: RestageValueBinding.read<bool>(
                source, const <Object>['cacheColorFilter'], context) ??
            false,
        #renderingStrategy:
            RestageDecoders.enumByName<restageLibrary5.RenderingStrategy>(
                    restageLibrary5.RenderingStrategy.values,
                    source,
                    <Object>['renderingStrategy']) ??
                restageLibrary5.RenderingStrategy.picture,
      },
    ) as Widget;
  });
}

LocalWidgetLibrary buildCuratedWidgetLibrary() => LocalWidgetLibrary({
      'SvgPictureAsset': _buildSvgPictureAsset,
      'SvgPictureNetwork': _buildSvgPictureNetwork,
      'SvgPictureString': _buildSvgPictureString,
      'SvgPictureMemory': _buildSvgPictureMemory,
      'SvgPicture': _buildSvgPicture,
      'SvgPictureFile': _buildSvgPictureFile,
    });
