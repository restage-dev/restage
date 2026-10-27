import 'package:flutter/widgets.dart';
import 'package:restage_core/src/runtime/builder_binding.dart';
import 'package:restage_core/src/runtime/decoders.dart';
import 'package:rfw/rfw.dart';
import 'package:restage_shared/restage_shared.dart';

/// Reconstructs native list and builder child delegates.
abstract final class RestageGridChildren {
  /// Decodes the declared native delegate and its child configuration.
  static SliverChildDelegate? delegate(DataSource source, List<Object> path,
      {required BuildContext context,
      required List<RestageBuilderBinding> bindings}) {
    final kind = source.v<String>([...path, '_s']);
    if (kind == null) return null;
    final keepAlive =
        source.v<bool>([...path, 'addAutomaticKeepAlives']) ?? true;
    final repaint = source.v<bool>([...path, 'addRepaintBoundaries']) ?? true;
    final semantics = source.v<bool>([...path, 'addSemanticIndexes']) ?? true;
    final offset = source.v<int>([...path, 'semanticIndexOffset']) ?? 0;
    final semantic = RestageBuilderBinding.optional(
        source, [...path, 'semanticIndexCallback'],
        scalarContract: const ScalarCallbackContract(parameters: [
          ScalarCallbackParameter.widget,
          ScalarCallbackParameter.itemIndex
        ]));
    final findIndex = RestageDecoders.keyIndexCallback(
        context, source, [...path, 'findChildIndexCallback'],
        bindings: bindings);
    if (semantic != null) bindings.add(semantic);
    final SemanticIndexCallback semanticIndex = semantic == null
        ? _nativeSemanticIndexCallback
        : (widget, index) => semantic
            .evaluate(context, {callbackParameterName(1): index}) as int?;
    switch (kind) {
      case 'SliverChildListDelegate':
        final children = RestageDecoders.widgetList(
            source, [...path, 'children'],
            context: context, bindings: bindings);
        if (source.v<bool>([...path, 'fixed']) ?? false) {
          return SliverChildListDelegate.fixed(children,
              addAutomaticKeepAlives: keepAlive,
              addRepaintBoundaries: repaint,
              addSemanticIndexes: semantics,
              semanticIndexOffset: offset,
              semanticIndexCallback: semanticIndex);
        }
        return SliverChildListDelegate(children,
            addAutomaticKeepAlives: keepAlive,
            addRepaintBoundaries: repaint,
            addSemanticIndexes: semantics,
            semanticIndexOffset: offset,
            semanticIndexCallback: semanticIndex);
      case 'SliverChildBuilderDelegate':
        final binding = RestageBuilderBinding(source, [...path, 'builder'],
            contract: const WidgetBuilderContract(parameters: [
              WidgetBuilderParameter.buildContext,
              WidgetBuilderParameter.itemIndex
            ], nullableResult: true));
        bindings.add(binding);
        return SliverChildBuilderDelegate(
            (context, index) => binding
                .buildNullable(context, {callbackParameterName(1): index}),
            childCount: source.v<int>([...path, 'childCount']),
            findChildIndexCallback: findIndex,
            addAutomaticKeepAlives: keepAlive,
            addRepaintBoundaries: repaint,
            addSemanticIndexes: semantics,
            semanticIndexOffset: offset,
            semanticIndexCallback: semanticIndex);
      default:
        throw FormatException('Unknown native child delegate: $kind');
    }
  }
}

final SemanticIndexCallback _nativeSemanticIndexCallback =
    const SliverChildListDelegate.fixed(<Widget>[]).semanticIndexCallback;
