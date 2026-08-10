/// A generated representation that can consume a customer widget catalog.
///
/// This enum is used only for exceptional, target-local authoring controls.
/// Package-level builder configuration remains the normal way to enable or
/// disable an output family.
enum EmitTarget {
  /// Remote Flutter Widgets catalog and factory output.
  rfw,

  /// A2UI catalog output.
  a2ui,

  /// Widgetbook story output.
  widgetbook,
}
