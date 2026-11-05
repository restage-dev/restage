import 'package:restage_codegen/src/issue.dart';
import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;

/// [frozen] rebound to [finalLibrary]; null, with an internal-error issue
/// for [name] at [location], when the final design no longer matches it.
({ResolvedRfwCatalogOccurrenceRebinding? rebinding})? rebindFrozenOccurrences(
  ResolvedRfwCatalogOccurrenceSet? frozen,
  fmt.RemoteWidgetLibrary finalLibrary, {
  required String name,
  required String location,
  required List<Issue> issues,
}) {
  try {
    return (rebinding: frozen?.rebindFinalLibrary(finalLibrary));
  } on FormatException {
    issues.add(
      Issue(
        code: IssueCode.malformedTranslatorOutput,
        message:
            "Restage can't generate `$name`. "
            'Please report this as a Restage bug.',
        location: location,
      ),
    );
    return null;
  }
}
