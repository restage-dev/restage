import 'dart:io';

import 'package:restage_codegen/src/frozen_occurrence_rebinding.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

final Catalog _catalog = decodeCatalog(
  File(
    '../restage_core/lib/src/widget_catalog/catalog.json',
  ).readAsStringSync(),
);

ResolvedRfwCatalogOccurrenceSet _frozen(fmt.RemoteWidgetLibrary library) =>
    ResolvedRfwCatalogOccurrenceSet.resolve(
      parsedLibrary: library,
      input: fmt.RfwCatalogOccurrenceResolutionInput(
        artifactProvenance: 'fixture.artifact',
        sourceLibraryIdentity: 'fixture.library',
        sourceDeclarationIdentity: 'fixture.library#Offer',
        renderEntryNames: const ['Paywall'],
        catalogConstructors: [
          for (final widget in _catalog.widgets)
            if (widget.library.namespace == 'restage.core')
              fmt.RfwCatalogConstructorProvenance(
                constructorName: widget.name,
                catalogLibraryNamespace: widget.library.namespace,
                catalogWidgetWireId: widget.wireId,
              ),
        ],
        localSymbols: [fmt.RfwCatalogLocalSymbol(name: 'Paywall')],
      ),
    );

fmt.RemoteWidgetLibrary _design(String root) => fmt.parseLibraryFile('''
  import restage.core;
  widget Paywall = $root;
''');

void main() {
  test(
    'a final design that no longer matches its frozen one is a bug report',
    () {
      final frozen = _frozen(_design('Column(children: [Text(text: "Go")])'));
      final issues = <Issue>[];
      expect(
        rebindFrozenOccurrences(
          frozen,
          _design('Text(text: "Go")'),
          name: 'Offer',
          location: 'lib/offer.dart#Offer',
          issues: issues,
        ),
        isNull,
      );
      expect(issues.single.code, IssueCode.malformedTranslatorOutput);
      expect(
        issues.single.message,
        "Restage can't generate `Offer`. Please report this as a Restage bug.",
      );
      expect(
        rebindFrozenOccurrences(
          frozen,
          _design('Column(children: [Text(text: "Go")])'),
          name: 'Offer',
          location: 'lib/offer.dart#Offer',
          issues: issues,
        ),
        isNotNull,
      );
      expect(issues, hasLength(1));
    },
  );
}
