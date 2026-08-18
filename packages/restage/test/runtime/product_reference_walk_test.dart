import 'package:flutter_test/flutter_test.dart';
// Direct path import — the walk is an internal implementation detail of the
// placeholder-price population sites, not public SDK surface.
// ignore: implementation_imports
import 'package:restage/src/runtime/product_reference_walk.dart';
import 'package:rfw/rfw.dart';

/// Wraps a single widget's [root] (and optional [initialState]) as a
/// minimal one-widget [RemoteWidgetLibrary], importing nothing (the walk
/// never follows imports).
RemoteWidgetLibrary _library(BlobNode root, {DynamicMap? initialState}) {
  return RemoteWidgetLibrary(
    const <Import>[],
    <WidgetDeclaration>[
      WidgetDeclaration('root', initialState, root),
    ],
  );
}

void main() {
  test('finds a slot-form reference (data.products.annual.localizedPrice)', () {
    final library = _library(
      const ConstructorCall('Text', <String, Object?>{
        'text': DataReference(<Object>['products', 'annual', 'localizedPrice']),
      }),
    );

    expect(referencedProductSlots(library), {'annual'});
  });

  test('finds a productId-form reference', () {
    final library = _library(
      const ConstructorCall('Text', <String, Object?>{
        'text': DataReference(
            <Object>['products', 'pro_monthly', 'localizedPrice']),
      }),
    );

    expect(referencedProductSlots(library), {'pro_monthly'});
  });

  test('finds a nested subkey reference (.title)', () {
    final library = _library(
      const ConstructorCall('Text', <String, Object?>{
        'text': DataReference(<Object>['products', 'annual', 'title']),
      }),
    );

    expect(referencedProductSlots(library), {'annual'});
  });

  test('finds a reference inside a nested widget builder', () {
    final library = _library(
      const ConstructorCall('Builder', <String, Object?>{
        'builder': WidgetBuilderDeclaration(
          'scope',
          ConstructorCall('Text', <String, Object?>{
            'text':
                DataReference(<Object>['products', 'trial', 'localizedPrice']),
          }),
        ),
      }),
    );

    expect(referencedProductSlots(library), {'trial'});
  });

  test('finds references inside a Switch input and each case', () {
    final library = _library(
      const Switch(
        DataReference(<Object>['products', 'switched', 'isTrial']),
        <Object?, Object>{
          true: ConstructorCall('Text', <String, Object?>{
            'text': DataReference(<Object>['products', 'trial_case', 'title']),
          }),
          null: ConstructorCall('Text', <String, Object?>{
            'text':
                DataReference(<Object>['products', 'default_case', 'title']),
          }),
        },
      ),
    );

    expect(
      referencedProductSlots(library),
      {'switched', 'trial_case', 'default_case'},
    );
  });

  test('finds a reference used as a Switch case KEY (not just its value)', () {
    // rfw's text-format parser reads a switch case key through the same
    // extended-value grammar as any other value, so a case key can itself
    // be a DataReference, not just a literal.
    final library = _library(
      const Switch(
        'irrelevant',
        <Object?, Object>{
          DataReference(<Object>['products', 'keycase', 'localizedPrice']):
              ConstructorCall('Text', <String, Object?>{'text': 'matched'}),
          null: ConstructorCall('Text', <String, Object?>{'text': 'default'}),
        },
      ),
    );

    expect(referencedProductSlots(library), {'keycase'});
  });

  test('finds references inside a Loop input and output template', () {
    final library = _library(
      const ConstructorCall('Column', <String, Object?>{
        'children': Loop(
          DataReference(<Object>['products', 'loop_input', 'title']),
          ConstructorCall('Text', <String, Object?>{
            'text': DataReference(<Object>['products', 'loop_output', 'title']),
          }),
        ),
      }),
    );

    expect(
      referencedProductSlots(library),
      {'loop_input', 'loop_output'},
    );
  });

  test('finds a reference inside an EventHandler payload', () {
    final library = _library(
      const ConstructorCall('ElevatedButton', <String, Object?>{
        'onPressed': EventHandler('purchase', <String, Object?>{
          'label': DataReference(<Object>['products', 'via_event', 'title']),
        }),
      }),
    );

    expect(referencedProductSlots(library), {'via_event'});
  });

  test('finds a reference inside a SetStateHandler value', () {
    final library = _library(
      const ConstructorCall('Checkbox', <String, Object?>{
        'onChanged': SetStateHandler(
          StateReference(<Object>['checked']),
          DataReference(<Object>['products', 'via_set_state', 'isTrial']),
        ),
      }),
    );

    expect(referencedProductSlots(library), {'via_set_state'});
  });

  test('finds a reference in the initial state map', () {
    final library = _library(
      const ConstructorCall('Text', <String, Object?>{'text': 'static'}),
      initialState: const <String, Object?>{
        'seed':
            DataReference(<Object>['products', 'from_initial_state', 'title']),
      },
    );

    expect(referencedProductSlots(library), {'from_initial_state'});
  });

  test('collects multiple distinct keys as a set', () {
    final library = _library(
      const ConstructorCall('Column', <String, Object?>{
        'children': <Object?>[
          ConstructorCall('Text', <String, Object?>{
            'text':
                DataReference(<Object>['products', 'annual', 'localizedPrice']),
          }),
          ConstructorCall('Text', <String, Object?>{
            'text': DataReference(<Object>['products', 'monthly', 'title']),
          }),
          // A repeated key must not appear twice.
          ConstructorCall('Text', <String, Object?>{
            'text': DataReference(<Object>['products', 'annual', 'currency']),
          }),
        ],
      }),
    );

    expect(referencedProductSlots(library), {'annual', 'monthly'});
  });

  test('ignores references outside the products namespace', () {
    final library = _library(
      const ConstructorCall('Text', <String, Object?>{
        'text': DataReference(<Object>['device', 'platform']),
      }),
    );

    expect(referencedProductSlots(library), isEmpty);
  });

  test('returns empty for a library with no product references', () {
    final library = _library(
      const ConstructorCall(
        'Text',
        <String, Object?>{'text': 'Hardcoded'},
      ),
    );

    expect(referencedProductSlots(library), isEmpty);
  });

  test('returns empty for a non-remote (locally compiled) library', () {
    expect(referencedProductSlots(const _FakeLocalLibrary()), isEmpty);
  });
}

final class _FakeLocalLibrary extends WidgetLibrary {
  const _FakeLocalLibrary();
}
