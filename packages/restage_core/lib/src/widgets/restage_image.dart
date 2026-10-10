// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in Flutter's LICENSE file.

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// An [Image] whose decoded-image layout results stay finite.
class RestageImage extends Image {
  /// Creates an image from an [ImageProvider].
  RestageImage({
    super.key,
    required super.image,
    ImageFrameBuilder? frameBuilder,
    super.loadingBuilder,
    super.errorBuilder,
    super.semanticLabel,
    super.excludeFromSemantics,
    super.width,
    super.height,
    super.color,
    super.opacity,
    super.colorBlendMode,
    super.fit,
    super.alignment,
    super.repeat,
    super.centerSlice,
    super.matchTextDirection,
    super.gaplessPlayback,
    super.isAntiAlias,
    super.filterQuality,
  }) : super(frameBuilder: _guardedFrameBuilder(frameBuilder));

  /// Creates an image from the network.
  RestageImage.network(
    super.src, {
    super.key,
    super.scale,
    ImageFrameBuilder? frameBuilder,
    super.loadingBuilder,
    super.errorBuilder,
    super.semanticLabel,
    super.excludeFromSemantics,
    super.width,
    super.height,
    super.color,
    super.opacity,
    super.colorBlendMode,
    super.fit,
    super.alignment,
    super.repeat,
    super.centerSlice,
    super.matchTextDirection,
    super.gaplessPlayback,
    super.filterQuality,
    super.isAntiAlias,
    super.headers,
    super.cacheWidth,
    super.cacheHeight,
    super.webHtmlElementStrategy,
  }) : super.network(
          frameBuilder: _guardedFrameBuilder(frameBuilder),
        );

  /// Creates an image from an asset bundle.
  RestageImage.asset(
    super.name, {
    super.key,
    super.bundle,
    ImageFrameBuilder? frameBuilder,
    super.errorBuilder,
    super.semanticLabel,
    super.excludeFromSemantics,
    super.scale,
    super.width,
    super.height,
    super.color,
    super.opacity,
    super.colorBlendMode,
    super.fit,
    super.alignment,
    super.repeat,
    super.centerSlice,
    super.matchTextDirection,
    super.gaplessPlayback,
    super.isAntiAlias,
    super.package,
    super.filterQuality,
    super.cacheWidth,
    super.cacheHeight,
  }) : super.asset(
          frameBuilder: _guardedFrameBuilder(frameBuilder),
        );

  static ImageFrameBuilder _guardedFrameBuilder(ImageFrameBuilder? caller) {
    return (BuildContext context, Widget child, int? frame, bool synchronous) {
      final Widget guarded = _replaceNativeLeaf(child);
      return caller?.call(context, guarded, frame, synchronous) ?? guarded;
    };
  }

  static Widget _replaceNativeLeaf(Widget child) {
    if (child case final RawImage raw) return _RestageRawImage.fromRaw(raw);
    if (child case final Semantics semantics) {
      final Widget? raw = semantics.child;
      if (raw == null) {
        throw FlutterError('Image semantics wrapper has no child.');
      }
      return Semantics.fromProperties(
        key: semantics.key,
        container: semantics.container,
        explicitChildNodes: semantics.explicitChildNodes,
        excludeSemantics: semantics.excludeSemantics,
        blockUserActions: semantics.blockUserActions,
        localeForSubtree: semantics.localeForSubtree,
        properties: semantics.properties,
        child: raw is RawImage ? _RestageRawImage.fromRaw(raw) : raw,
      );
    }
    // The current non-RawImage branch is Flutter's unexported web-image leaf.
    return child;
  }
}

class _RestageRawImage extends RawImage {
  _RestageRawImage.fromRaw(RawImage raw)
      : super(
          key: raw.key,
          image: raw.image,
          debugImageLabel: raw.debugImageLabel,
          width: raw.width,
          height: raw.height,
          scale: raw.scale,
          color: raw.color,
          opacity: raw.opacity,
          colorBlendMode: raw.colorBlendMode,
          fit: raw.fit,
          alignment: raw.alignment,
          repeat: raw.repeat,
          centerSlice: raw.centerSlice,
          matchTextDirection: raw.matchTextDirection,
          invertColors: raw.invertColors,
          isAntiAlias: raw.isAntiAlias,
          filterQuality: raw.filterQuality,
        );

  @override
  RenderImage createRenderObject(BuildContext context) {
    assert(
      (!matchTextDirection && alignment is Alignment) ||
          debugCheckHasDirectionality(context),
    );
    assert(
      image?.debugGetOpenHandleStackTraces()?.isNotEmpty ?? true,
      'Creator of a RawImage disposed of the image while it was still needed.',
    );
    return _RenderRestageImage(
      image: image?.clone(),
      debugImageLabel: debugImageLabel,
      width: width,
      height: height,
      scale: scale,
      color: color,
      opacity: opacity,
      colorBlendMode: colorBlendMode,
      fit: fit,
      alignment: alignment,
      repeat: repeat,
      centerSlice: centerSlice,
      matchTextDirection: matchTextDirection,
      textDirection: matchTextDirection || alignment is! Alignment
          ? Directionality.of(context)
          : null,
      invertColors: invertColors,
      isAntiAlias: isAntiAlias,
      filterQuality: filterQuality,
    );
  }
}

class _RenderRestageImage extends RenderImage {
  _RenderRestageImage({
    super.image,
    super.debugImageLabel,
    super.width,
    super.height,
    super.scale,
    super.color,
    super.opacity,
    super.colorBlendMode,
    super.fit,
    super.alignment,
    super.repeat,
    super.centerSlice,
    super.matchTextDirection,
    super.textDirection,
    super.invertColors,
    super.isAntiAlias,
    super.filterQuality,
  });

  Never _fail(String operation) =>
      throw FlutterError('Image produced a non-finite $operation.');

  Size _scaleOneSize(BoxConstraints constraints) {
    final BoxConstraints folded = BoxConstraints.tightFor(
      width: width,
      height: height,
    ).enforce(constraints);
    final ui.Image? currentImage = image;
    if (currentImage == null) return folded.smallest;
    return folded.constrainSizeAndAttemptToPreserveAspectRatio(
      Size(currentImage.width.toDouble(), currentImage.height.toDouble()),
    );
  }

  Size _finiteSize(Size native, BoxConstraints constraints, String operation) {
    if (native.isFinite) return native;
    final Size fallback = _scaleOneSize(constraints);
    return fallback.isFinite ? fallback : _fail(operation);
  }

  double _finiteScalar(
    double native,
    BoxConstraints constraints,
    bool widthAxis,
    String operation,
  ) {
    if (native.isFinite) return native;
    final Size fallback = _scaleOneSize(constraints);
    final double result = widthAxis ? fallback.width : fallback.height;
    return result.isFinite ? result : _fail(operation);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) => _finiteSize(
        super.computeDryLayout(constraints),
        constraints,
        'layout size',
      );

  @override
  void performLayout() => size = computeDryLayout(constraints);

  @override
  double computeMinIntrinsicWidth(double height) => _finiteScalar(
        super.computeMinIntrinsicWidth(height),
        BoxConstraints.tightForFinite(height: height),
        true,
        'minimum intrinsic width',
      );

  @override
  double computeMaxIntrinsicWidth(double height) => _finiteScalar(
        super.computeMaxIntrinsicWidth(height),
        BoxConstraints.tightForFinite(height: height),
        true,
        'maximum intrinsic width',
      );

  @override
  double computeMinIntrinsicHeight(double width) => _finiteScalar(
        super.computeMinIntrinsicHeight(width),
        BoxConstraints.tightForFinite(width: width),
        false,
        'minimum intrinsic height',
      );

  @override
  double computeMaxIntrinsicHeight(double width) => _finiteScalar(
        super.computeMaxIntrinsicHeight(width),
        BoxConstraints.tightForFinite(width: width),
        false,
        'maximum intrinsic height',
      );
}

/// A [FadeInImage] whose placeholder and target use [RestageImage].
class RestageFadeInImage extends FadeInImage {
  /// Creates an asset-placeholder/network-target fade.
  RestageFadeInImage.assetNetwork({
    super.key,
    required super.placeholder,
    super.placeholderErrorBuilder,
    required super.image,
    super.imageErrorBuilder,
    super.bundle,
    super.placeholderScale,
    super.imageScale,
    super.excludeFromSemantics,
    super.imageSemanticLabel,
    super.fadeOutDuration,
    super.fadeOutCurve,
    super.fadeInDuration,
    super.fadeInCurve,
    super.width,
    super.height,
    super.fit,
    super.color,
    super.colorBlendMode,
    super.placeholderColor,
    super.placeholderColorBlendMode,
    super.placeholderFit,
    super.filterQuality,
    super.placeholderFilterQuality,
    super.alignment,
    super.repeat,
    super.matchTextDirection,
    super.placeholderCacheWidth,
    super.placeholderCacheHeight,
    super.imageCacheWidth,
    super.imageCacheHeight,
  }) : super.assetNetwork();

  @override
  State<FadeInImage> createState() => _RestageFadeInImageState();
}

// Adapted from Flutter's private FadeInImage state at revision
// 4cf24164269a5ebf0c16a028a00727d0e77bbb05.
class _RestageFadeInImageState extends State<FadeInImage> {
  static const Animation<double> _opaque = AlwaysStoppedAnimation<double>(1);
  bool _targetLoaded = false;
  final ProxyAnimation _imageAnimation = ProxyAnimation(_opaque);
  final ProxyAnimation _placeholderAnimation = ProxyAnimation(_opaque);

  RestageImage _image({
    required ImageProvider image,
    ImageErrorWidgetBuilder? errorBuilder,
    ImageFrameBuilder? frameBuilder,
    BoxFit? fit,
    ui.Color? color,
    ui.BlendMode? colorBlendMode,
    required ui.FilterQuality filterQuality,
    required Animation<double> opacity,
  }) {
    return RestageImage(
      image: image,
      errorBuilder: errorBuilder,
      frameBuilder: frameBuilder,
      opacity: opacity,
      width: widget.width,
      height: widget.height,
      fit: fit,
      color: color,
      colorBlendMode: colorBlendMode,
      filterQuality: filterQuality,
      alignment: widget.alignment,
      repeat: widget.repeat,
      matchTextDirection: widget.matchTextDirection,
      gaplessPlayback: true,
      excludeFromSemantics: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget result = _image(
      image: widget.image,
      errorBuilder: widget.imageErrorBuilder,
      opacity: _imageAnimation,
      fit: widget.fit,
      color: widget.color,
      colorBlendMode: widget.colorBlendMode,
      filterQuality: widget.filterQuality,
      frameBuilder: (
        BuildContext context,
        Widget child,
        int? frame,
        bool wasSynchronouslyLoaded,
      ) {
        if (wasSynchronouslyLoaded || frame != null) _targetLoaded = true;
        return _RestageAnimatedFade(
          target: child,
          targetProxyAnimation: _imageAnimation,
          placeholder: _image(
            image: widget.placeholder,
            errorBuilder: widget.placeholderErrorBuilder,
            opacity: _placeholderAnimation,
            color: widget.placeholderColor,
            colorBlendMode: widget.placeholderColorBlendMode,
            fit: widget.placeholderFit ?? widget.fit,
            filterQuality:
                widget.placeholderFilterQuality ?? widget.filterQuality,
          ),
          placeholderProxyAnimation: _placeholderAnimation,
          isTargetLoaded: _targetLoaded,
          wasSynchronouslyLoaded: wasSynchronouslyLoaded,
          fadeInDuration: widget.fadeInDuration,
          fadeOutDuration: widget.fadeOutDuration,
          fadeInCurve: widget.fadeInCurve,
          fadeOutCurve: widget.fadeOutCurve,
        );
      },
    );
    if (!widget.excludeFromSemantics) {
      result = Semantics(
        container: widget.imageSemanticLabel != null,
        image: true,
        label: widget.imageSemanticLabel ?? '',
        child: result,
      );
    }
    return result;
  }
}

class _RestageAnimatedFade extends ImplicitlyAnimatedWidget {
  const _RestageAnimatedFade({
    required this.target,
    required this.targetProxyAnimation,
    required this.placeholder,
    required this.placeholderProxyAnimation,
    required this.isTargetLoaded,
    required this.fadeOutDuration,
    required this.fadeOutCurve,
    required this.fadeInDuration,
    required this.fadeInCurve,
    required this.wasSynchronouslyLoaded,
  })  : assert(!wasSynchronouslyLoaded || isTargetLoaded),
        super(duration: fadeInDuration + fadeOutDuration);

  final Widget target;
  final ProxyAnimation targetProxyAnimation;
  final Widget placeholder;
  final ProxyAnimation placeholderProxyAnimation;
  final bool isTargetLoaded;
  final Duration fadeInDuration;
  final Duration fadeOutDuration;
  final Curve fadeInCurve;
  final Curve fadeOutCurve;
  final bool wasSynchronouslyLoaded;

  @override
  _RestageAnimatedFadeState createState() => _RestageAnimatedFadeState();
}

class _RestageAnimatedFadeState
    extends ImplicitlyAnimatedWidgetState<_RestageAnimatedFade> {
  Tween<double>? _targetOpacity;
  Tween<double>? _placeholderOpacity;
  Animation<double>? _targetOpacityAnimation;
  Animation<double>? _placeholderOpacityAnimation;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _targetOpacity = visitor(
      _targetOpacity,
      widget.isTargetLoaded ? 1.0 : 0.0,
      (dynamic value) => Tween<double>(begin: value as double),
    ) as Tween<double>?;
    _placeholderOpacity = visitor(
      _placeholderOpacity,
      widget.isTargetLoaded ? 0.0 : 1.0,
      (dynamic value) => Tween<double>(begin: value as double),
    ) as Tween<double>?;
  }

  @override
  void didUpdateTweens() {
    if (widget.wasSynchronouslyLoaded) return;
    _placeholderOpacityAnimation = animation.drive(
      TweenSequence<double>(<TweenSequenceItem<double>>[
        TweenSequenceItem<double>(
          tween: _placeholderOpacity!.chain(
            CurveTween(curve: widget.fadeOutCurve),
          ),
          weight: widget.fadeOutDuration.inMilliseconds.toDouble(),
        ),
        TweenSequenceItem<double>(
          tween: ConstantTween<double>(0),
          weight: widget.fadeInDuration.inMilliseconds.toDouble(),
        ),
      ]),
    )..addStatusListener((AnimationStatus status) {
        if (_placeholderOpacityAnimation!.isCompleted) setState(() {});
      });
    _targetOpacityAnimation = animation.drive(
      TweenSequence<double>(<TweenSequenceItem<double>>[
        TweenSequenceItem<double>(
          tween: ConstantTween<double>(0),
          weight: widget.fadeOutDuration.inMilliseconds.toDouble(),
        ),
        TweenSequenceItem<double>(
          tween: _targetOpacity!.chain(CurveTween(curve: widget.fadeInCurve)),
          weight: widget.fadeInDuration.inMilliseconds.toDouble(),
        ),
      ]),
    );
    widget.targetProxyAnimation.parent = _targetOpacityAnimation;
    widget.placeholderProxyAnimation.parent = _placeholderOpacityAnimation;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.wasSynchronouslyLoaded ||
        (_placeholderOpacityAnimation?.isCompleted ?? true)) {
      return widget.target;
    }
    return Stack(
      fit: StackFit.passthrough,
      alignment: AlignmentDirectional.center,
      textDirection: TextDirection.ltr,
      children: <Widget>[widget.target, widget.placeholder],
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty<Animation<double>>(
        'targetOpacity',
        _targetOpacityAnimation,
      ),
    );
    properties.add(
      DiagnosticsProperty<Animation<double>>(
        'placeholderOpacity',
        _placeholderOpacityAnimation,
      ),
    );
  }
}
