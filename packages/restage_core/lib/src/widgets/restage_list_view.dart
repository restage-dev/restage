import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'restage_padding.dart';

/// A [ListView] that keeps finite-child estimates and padding extents finite.
class RestageListView extends ListView {
  /// Creates a guarded list from an explicit finite list of children.
  RestageListView({
    super.key,
    super.scrollDirection,
    super.reverse,
    super.shrinkWrap,
    super.padding,
    super.keyboardDismissBehavior,
    super.clipBehavior,
    super.children,
  });

  @override
  Widget buildChildLayout(BuildContext context) =>
      _RestageSliverList(delegate: childrenDelegate);

  @override
  List<Widget> buildSlivers(BuildContext context) {
    final List<Widget> slivers = super.buildSlivers(context);
    final Widget sliver = slivers.single;
    if (sliver is! SliverPadding) return slivers;
    return <Widget>[
      _RestageSliverPadding(
        key: sliver.key,
        padding: sliver.padding,
        sliver: sliver.child,
      ),
    ];
  }
}

class _RestageSliverList extends SliverList {
  const _RestageSliverList({required super.delegate});

  @override
  SliverMultiBoxAdaptorElement createElement() =>
      _RestageSliverMultiBoxAdaptorElement(this);
}

class _RestageSliverMultiBoxAdaptorElement
    extends SliverMultiBoxAdaptorElement {
  _RestageSliverMultiBoxAdaptorElement(_RestageSliverList super.widget)
      : super(replaceMovedChildren: true);

  @override
  double estimateMaxScrollOffset(
    SliverConstraints? constraints, {
    int? firstIndex,
    int? lastIndex,
    double? leadingScrollOffset,
    double? trailingScrollOffset,
  }) {
    final double result = super.estimateMaxScrollOffset(
      constraints,
      firstIndex: firstIndex,
      lastIndex: lastIndex,
      leadingScrollOffset: leadingScrollOffset,
      trailingScrollOffset: trailingScrollOffset,
    );
    if (estimatedChildCount != null && !result.isFinite) {
      throw FlutterError('ListView cannot estimate a finite scroll extent.');
    }
    return result;
  }
}

class _RestageSliverPadding extends SliverPadding {
  const _RestageSliverPadding({
    super.key,
    required super.padding,
    super.sliver,
  });

  @override
  RenderSliverPadding createRenderObject(BuildContext context) =>
      _RenderRestageSliverPadding(
        padding: padding,
        textDirection: Directionality.of(context),
      );
}

class _RenderRestageSliverPadding extends RenderSliverPadding {
  _RenderRestageSliverPadding({
    required super.padding,
    super.textDirection,
  });

  @override
  EdgeInsets? get resolvedPadding {
    final EdgeInsets? resolved = super.resolvedPadding;
    return resolved == null ? null : restageSafePhysicalInsets(resolved);
  }

  Never _fail() =>
      throw FlutterError('SliverPadding cannot produce finite geometry.');

  @override
  set geometry(SliverGeometry? value) {
    if (value == null ||
        (value.scrollExtent.isFinite && value.maxPaintExtent.isFinite)) {
      super.geometry = value;
      return;
    }
    final SliverGeometry? childGeometry = child?.geometry;
    final double scrollExtent = value.scrollExtent.isFinite
        ? value.scrollExtent
        : childGeometry?.scrollExtent ?? _fail();
    final double maxPaintExtent = value.maxPaintExtent.isFinite
        ? value.maxPaintExtent
        : childGeometry?.maxPaintExtent ?? _fail();
    if (!scrollExtent.isFinite || !maxPaintExtent.isFinite) _fail();
    super.geometry = value.copyWith(
      scrollExtent: scrollExtent,
      maxPaintExtent: maxPaintExtent,
    );
  }
}
