import 'dart:typed_data';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:restage_codegen/src/hoisting.dart';
import 'package:restage_codegen/src/islands/islands.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/island_promotion.dart';
import 'package:restage_codegen/src/surface_publication/screen_contract_reference_emitter.dart'
    show ResolvedWidgetMountInput;
import 'package:restage_shared/restage_shared.dart' show WidgetVocabulary;
import 'package:restage_shared/rfw_formats.dart' as fmt;

/// Every part of the mount [mountName] of [surface]: its delivered design
/// (counted in [blob], when there is one), islands, values, actions and kept
/// wrappers.
List<SplitSite> mountReportSites(
  String surface,
  String mountName,
  ResolvedWidgetMountInput mount,
  Uint8List? blob,
) {
  SplitSite site(
    SplitSiteKind kind,
    String name,
    String widget,
    String location, {
    String? reason,
    String? token,
    String? interface,
    int? widgets,
    Map<String, Object?>? promotion,
    List<({String name, String reason, String message})> compiled = const [],
    String? reasonCode,
  }) => SplitSite(
    surface: surface,
    mount: mountName,
    name: name,
    widget: widget,
    location: location,
    kind: kind,
    reason: reason,
    token: token,
    interface: interface,
    widgets: widgets,
    promotion: promotion,
    compiled: compiled,
    reasonCode: reasonCode,
  );
  final split = mount.split;
  return [
    if (blob != null)
      site(
        SplitSiteKind.design,
        mountName,
        mount.screen.name ?? mountName,
        mount.assetId.path,
        widgets: deliveredWidgetCount(blob, {
          for (final island in mount.islands) island.name,
        }),
      ),
    for (final island in mount.islands)
      site(
        SplitSiteKind.island,
        WidgetVocabulary.qualifiedName(island.library, island.name),
        island.widget,
        island.location,
        reason: island.reason?.message,
        reasonCode: island.reason?.code.name,
        token: island.token,
        interface: island.interface,
        widgets: islandWidgetCount(island),
        promotion: switch (planIslandPromotion(island)) {
          (plan: final plan?, refusal: _) => plan.toJson(),
          (plan: _, refusal: final refusal) => {'refusal': refusal},
        },
        compiled: [
          for (final argument in island.compiled)
            (
              name: argument.name,
              reason: argument.reason.name,
              message: argument.message(
                island.widget,
                appWidget: islandCanJoinCatalog(island),
              ),
            ),
        ],
      ),
    for (final value in mount.hoisted)
      if (isIslandAction(value))
        site(SplitSiteKind.action, value.key, value.label, value.location!)
      else if (value.location case final location?)
        site(SplitSiteKind.value, value.key, value.label, location),
    for (final kept in split?.shell ?? const <Never>[])
      site(
        SplitSiteKind.mount,
        kept.widget,
        kept.widget,
        kept.location,
        reason: kept.reason.name,
      ),
    if (split?.state case final state?)
      site(
        SplitSiteKind.mount,
        state.name,
        state.name,
        state.location,
        reason: MountReason.state.name,
      ),
  ];
}

/// The widgets [blob] delivers: its constructor calls, less calls to its own
/// local widgets and to [islands].
int deliveredWidgetCount(Uint8List blob, Set<String> islands) {
  final library = fmt.decodeLibraryBlob(blob);
  final locals = {for (final widget in library.widgets) widget.name};
  var count = 0;
  void visit(Object? node) {
    switch (node) {
      case fmt.ConstructorCall(:final name, :final arguments):
        if (!locals.contains(name) && !islands.contains(name)) count++;
        visit(arguments);
      case fmt.Switch(:final input, :final outputs):
        visit(input);
        visit(outputs);
      case fmt.Loop(:final input, :final output):
        visit(input);
        visit(output);
      case fmt.WidgetBuilderDeclaration(:final widget):
        visit(widget);
      case fmt.EventHandler(:final eventArguments):
        visit(eventArguments);
      case final Map<Object?, Object?> map:
        map.values.forEach(visit);
      case final List<Object?> list:
        list.forEach(visit);
    }
  }

  for (final widget in library.widgets) {
    visit(widget.root);
  }
  return count;
}

/// The widgets [island] renders from the app: itself and the widget
/// expressions inside it, less its slots.
int islandWidgetCount(Island island) {
  final counter = _WidgetCounter({for (final slot in island.slots) slot.node});
  island.node.accept(counter);
  return counter.count == 0 ? 1 : counter.count;
}

final class _WidgetCounter extends GeneralizingAstVisitor<void> {
  _WidgetCounter(this.slots);

  final Set<AstNode> slots;
  int count = 0;

  @override
  void visitNode(AstNode node) {
    if (slots.contains(node)) return;
    if ((node is InstanceCreationExpression || node is MethodInvocation) &&
        classifyHoistType((node as Expression).staticType) is HoistIsWidget) {
      count++;
    }
    node.visitChildren(this);
  }
}
