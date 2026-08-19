import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart'
    show FlowDeliveryMode, Surface, kBaselineCatalogVersion;

/// Marks a top-level [FlowDefinition] or [RestageFlow] class as a flow graph.
///
/// A flow always declares its product category in source. The generator derives
/// an omitted [id] from the library filename when that declaration is
/// unambiguous.
@immutable
final class FlowGraph {
  /// Creates a flow graph annotation.
  const FlowGraph({
    this.id,
    required this.surface,
    this.version = 1,
    this.minClient = kBaselineCatalogVersion,
    this.delivery = FlowDeliveryMode.typed,
  });

  /// Optional stable flow identity.
  final String? id;

  /// Product category of the complete flow.
  final Surface surface;

  /// App-pinned flow contract version.
  final int version;

  /// Minimum catalog version required to render the flow.
  final int minClient;

  /// Delivery discipline for the generated flow payload.
  final FlowDeliveryMode delivery;
}

/// Legacy source annotation for a reusable flow screen.
///
/// New source should use [Screen]. This annotation retains its legacy required
/// ID shape while the generator continues to support directory-routed input.
@Deprecated('Use @Screen(...) instead.')
@immutable
final class ScreenSource {
  /// Creates a legacy flow-screen source annotation.
  const ScreenSource({
    required this.id,
    this.version = 1,
    this.minClient = kBaselineCatalogVersion,
  });

  /// Stable flow-screen identifier.
  final String id;

  /// Descriptor version emitted for this screen.
  final int version;

  /// Minimum client descriptor version that can load this screen.
  final int minClient;
}

/// Legacy source annotation for a class-shaped flow graph.
///
/// New source should use [FlowGraph]. This annotation retains its legacy
/// required ID shape while the generator continues to support directory-routed
/// input.
@Deprecated('Use @FlowGraph(surface: Surface.<category>) instead.')
@immutable
final class FlowSource {
  /// Creates a legacy flow graph source annotation.
  const FlowSource({
    required this.id,
    this.version = 1,
    this.minClient = kBaselineCatalogVersion,
    this.delivery = FlowDeliveryMode.typed,
  });

  /// Stable flow graph identifier.
  final String id;

  /// Descriptor version emitted for this flow.
  final int version;

  /// Minimum client descriptor version that can load this flow.
  final int minClient;

  /// Delivery discipline for the emitted flow document.
  final FlowDeliveryMode delivery;
}
