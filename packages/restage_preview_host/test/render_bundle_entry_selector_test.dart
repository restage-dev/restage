import 'package:flutter_test/flutter_test.dart';
import 'package:restage_preview_host/restage_preview_host.dart';
import 'package:rfw/formats.dart';

RemoteWidgetLibrary _libraryWithDeclarations(List<String> names) {
  final parsed = parseLibraryFile('''
import restage.core;
widget Template = Text(text: "selected");
''');
  final template = parsed.widgets.single;
  return RemoteWidgetLibrary(
    parsed.imports,
    <WidgetDeclaration>[
      for (final name in names)
        WidgetDeclaration(name, template.initialState, template.root),
    ],
  );
}

Matcher _formatException(String message) => isA<FormatException>().having(
      (error) => error.message,
      'message',
      message,
    );

void main() {
  test('selects one main declaration', () {
    expect(
      selectRenderBundleEntryWidgetName(
        _libraryWithDeclarations(<String>['Other', 'main']),
      ),
      'main',
    );
  });

  test('one main wins over Paywall declarations', () {
    expect(
      selectRenderBundleEntryWidgetName(
        _libraryWithDeclarations(<String>['Paywall', 'main', 'Paywall']),
      ),
      'main',
    );
  });

  test('selects one Paywall declaration when main is absent', () {
    expect(
      selectRenderBundleEntryWidgetName(
        _libraryWithDeclarations(<String>['Other', 'Paywall']),
      ),
      'Paywall',
    );
  });

  test('rejects duplicate main declarations', () {
    expect(
      () => selectRenderBundleEntryWidgetName(
        _libraryWithDeclarations(<String>['main', 'main', 'Paywall']),
      ),
      throwsA(_formatException('Multiple main declarations.')),
    );
  });

  test('rejects a library without a supported declaration', () {
    expect(
      () => selectRenderBundleEntryWidgetName(
        _libraryWithDeclarations(<String>['Other']),
      ),
      throwsA(_formatException('No unique render bundle entry.')),
    );
  });

  test('rejects duplicate Paywall declarations when main is absent', () {
    expect(
      () => selectRenderBundleEntryWidgetName(
        _libraryWithDeclarations(<String>['Paywall', 'Paywall']),
      ),
      throwsA(_formatException('No unique render bundle entry.')),
    );
  });
}
