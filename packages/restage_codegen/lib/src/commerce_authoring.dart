import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_shared/rfw_formats.dart';

const String _restageLibraryOrigin = 'package:restage';

const String _commerceBoundaryGuidance =
    'Authored surfaces cannot initiate purchases or restores. Applications '
    'invoke the typed commerce boundary from explicit host-controlled code. '
    'The current facade is unavailable until activated.';

/// SDK helper names that cannot be used in authored surfaces.
const Set<String> unsupportedCommerceHelperNames = {
  'paywallPurchase',
  'paywallPriceFor',
};

/// Event names reserved from authored surfaces.
const Set<String> unsupportedCommerceEventNames = {
  'purchase',
  'restore',
  'restage.purchase',
  'restage.restore',
  'restage.purchase.succeeded',
  'restage.purchase.pending',
  'restage.purchase.cancelled',
  'restage.purchase.failed',
  'restage.restore.succeeded',
  'restage.restore.noPurchases',
  'restage.restore.failed',
};

/// Whether [expression] invokes an unsupported SDK commerce helper.
bool isUnsupportedCommerceHelperCall(MethodInvocation expression) {
  if (!unsupportedCommerceHelperNames.contains(expression.methodName.name)) {
    return false;
  }

  return _isRestageInvocation(expression);
}

/// Whether [expression] invokes the SDK `paywallEvent` helper.
bool isRestagePaywallEventCall(MethodInvocation expression) {
  if (expression.methodName.name != 'paywallEvent') return false;

  return _isRestageInvocation(expression);
}

bool _isRestageInvocation(MethodInvocation expression) {
  final element = expression.methodName.element;
  if (element != null) {
    return libraryUriMatchesOrigin(
      element.library?.identifier ?? '',
      _restageLibraryOrigin,
    );
  }

  final target = expression.realTarget;
  if (target == null) return true;
  if (target is! SimpleIdentifier || target.element is! PrefixElement) {
    return false;
  }
  final prefix = target.element! as PrefixElement;
  return prefix.imports.any(
    (import) => libraryUriMatchesOrigin(
      import.importedLibrary?.identifier ?? '',
      _restageLibraryOrigin,
    ),
  );
}

/// Creates the diagnostic for an unsupported SDK commerce helper call.
Issue unsupportedCommerceHelperIssue(
  MethodInvocation expression,
  String location,
) =>
    Issue(
      code: IssueCode.unsupportedCommerceAuthoring,
      message: "The authored commerce helper '${expression.methodName.name}' "
          'is unsupported. $_commerceBoundaryGuidance',
      location: location,
    );

/// Creates the diagnostic for a reserved authored event name.
Issue unsupportedCommerceEventIssue(String name, String location) => Issue(
      code: IssueCode.unsupportedCommerceAuthoring,
      message: "The authored commerce event '$name' is unsupported. "
          '$_commerceBoundaryGuidance',
      location: location,
    );

/// Creates the diagnostic for an authored product-data reference.
Issue unsupportedCommerceDataIssue(String location) => Issue(
      code: IssueCode.unsupportedCommerceAuthoring,
      message: 'The authored data.products reference is unsupported. Supply '
          'display values through application-owned data.',
      location: location,
    );

/// Finds unsupported commerce forms in a parsed [library].
List<Issue> validateCommerceAuthoring(RemoteWidgetLibrary library) {
  final issues = <Issue>[];
  for (final widget in library.widgets) {
    _visitCommerceValue(widget.initialState, widget.name, issues);
    _visitCommerceValue(widget.root, widget.name, issues);
  }
  return issues;
}

void _visitCommerceValue(
  Object? value,
  String location,
  List<Issue> issues,
) {
  if (value is EventHandler) {
    if (unsupportedCommerceEventNames.contains(value.eventName)) {
      issues.add(unsupportedCommerceEventIssue(value.eventName, location));
    }
    _visitCommerceValue(value.eventArguments, location, issues);
    return;
  }
  if (value is DataReference) {
    if (value.parts.isNotEmpty && value.parts.first == 'products') {
      issues.add(unsupportedCommerceDataIssue(location));
    }
    return;
  }
  if (value is ConstructorCall) {
    _visitCommerceValue(value.arguments, location, issues);
    return;
  }
  if (value is Switch) {
    _visitCommerceValue(value.input, location, issues);
    _visitCommerceValue(value.outputs.keys, location, issues);
    _visitCommerceValue(value.outputs.values, location, issues);
    return;
  }
  if (value is Loop) {
    _visitCommerceValue(value.input, location, issues);
    _visitCommerceValue(value.output, location, issues);
    return;
  }
  if (value is WidgetBuilderDeclaration) {
    _visitCommerceValue(value.widget, location, issues);
    return;
  }
  if (value is SetStateHandler) {
    _visitCommerceValue(value.value, location, issues);
    return;
  }
  if (value is Map) {
    _visitCommerceValue(value.values, location, issues);
    return;
  }
  if (value is Iterable) {
    for (final item in value) {
      _visitCommerceValue(item, location, issues);
    }
  }
}
