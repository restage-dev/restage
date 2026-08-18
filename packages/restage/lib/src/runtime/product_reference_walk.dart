import 'package:rfw/rfw.dart';

/// Collects the `<key>` from every `data.products.<key>...` reference
/// reachable from [library]: every [DataReference] whose [Reference.parts]
/// begin with the literal `'products'`.
///
/// A one-pass walk of each widget declaration's initial state and root,
/// recursing through constructor arguments, switch inputs/cases, loop
/// inputs/bodies, nested widget builders, and event/state-setter payloads —
/// everywhere a [DataReference] can appear in a decoded remote widget
/// library. Returns the empty set for a [library] with no product
/// references, including a non-remote (locally compiled) [WidgetLibrary],
/// which never contains a [DataReference].
///
/// Used to select which product keys get the unbound-price placeholder when
/// no commerce context is configured — see `Restage.hasCommerceContext` and
/// `populatePlaceholderProductData`.
Set<String> referencedProductSlots(WidgetLibrary library) {
  if (library is! RemoteWidgetLibrary) return const <String>{};

  final keys = <String>{};

  void visit(Object? node) {
    switch (node) {
      case DataReference(:final parts):
        if (parts.length >= 2 && parts[0] == 'products') {
          final key = parts[1];
          if (key is String) keys.add(key);
        }
      case ConstructorCall(:final arguments):
        // arguments is a DynamicMap, so this recurses straight into the
        // Map() case below.
        visit(arguments);
      case Switch(:final input, :final outputs):
        visit(input);
        outputs.keys.forEach(visit);
        outputs.values.forEach(visit);
      case Loop(:final input, :final output):
        visit(input);
        visit(output);
      case WidgetBuilderDeclaration(:final widget):
        visit(widget);
      case EventHandler(:final eventArguments):
        // eventArguments is a DynamicMap too — same delegation as above.
        visit(eventArguments);
      case SetStateHandler(:final value):
        visit(value);
      case Map():
        node.values.forEach(visit);
      case List():
        node.forEach(visit);
      default:
        break;
    }
  }

  for (final declaration in library.widgets) {
    final initialState = declaration.initialState;
    if (initialState != null) visit(initialState);
    visit(declaration.root);
  }

  return Set<String>.unmodifiable(keys);
}

/// A screen/stage's placeholder-lane state: the referenced-key walk,
/// memoized once at construction, and a sticky "already logged" flag.
///
/// [keys] is [referencedProductSlots] run once against the decoded library —
/// the walk cost is paid once per surface load, not once per rebuild.
/// [logged] starts false and is set true by the caller once the
/// placeholder-prices debug log has had the chance to fire, so a later
/// re-population (e.g. a lane flip back to no commerce context) never logs a
/// second time.
///
/// Each screen/stage holder constructs and owns exactly one instance — this
/// is a plain value carrier, not shared or centralized state.
final class PlaceholderProductLane {
  /// Walks [library] once to populate [keys].
  PlaceholderProductLane(WidgetLibrary library)
      : keys = referencedProductSlots(library);

  final Set<String> keys;
  bool logged = false;
}
