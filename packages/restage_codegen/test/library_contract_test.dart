import 'dart:io';

import 'package:restage_codegen/src/library_contract.dart';
import 'package:restage_codegen/src/user_catalog_allocation.dart';
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

const _library = WidgetLibrary.custom('app');

PropertyEntry _property(
  String name, {
  PropertyType type = PropertyType.string,
  String description = 'A property.',
  PropertyPriority? priority,
}) =>
    PropertyEntry(
      wireId: WireId.unallocatedProperty,
      name: name,
      type: type,
      description: description,
      priority: priority,
    );

const _tone = 'package:app/tone.dart#Tone';

PropertyEntry _toneProperty() => const PropertyEntry(
      wireId: WireId.unallocatedProperty,
      name: 'tone',
      type: PropertyType.enumValue,
      description: 'The tone.',
      enumType: 'Tone',
      valueShape: EnumShape(
        propertyType: PropertyType.enumValue,
        enumRef: DartTypeRef(
          libraryUri: 'package:app/tone.dart',
          symbolName: 'Tone',
        ),
      ),
    );

WidgetEntry _widget(
  String name,
  List<PropertyEntry> properties, {
  String? flutterType,
}) =>
    WidgetEntry(
      wireId: WireId.unallocatedWidget,
      name: name,
      library: _library,
      category: WidgetCategory.layout,
      description: 'A widget.',
      flutterType: flutterType ?? 'package:app/widgets.dart#$name',
      childrenSlot: ChildrenSlot.none,
      properties: properties,
    );

/// Builds the app catalog, replaying and extending the shared wire-id log.
final class _App {
  final List<WireIdEvent> events = [];

  Catalog build(
    List<WidgetEntry> widgets, {
    int? capabilityVersion,
    int compatibleSince = 1,
  }) {
    final allocation = allocateUserCatalogFromWidgets(
      package: 'app',
      widgets: widgets,
      stampedCapabilityVersions: {
        if (capabilityVersion != null) 'app': capabilityVersion,
      },
      compatibleSinceVersions: {
        if (compatibleSince > 1) 'app': compatibleSince,
      },
      existingEvents: events,
    );
    events.addAll(allocation.newEvents);
    return allocation.catalog;
  }
}

void main() {
  late Directory root;
  late _App app;

  setUp(() {
    root = Directory.systemTemp.createTempSync('library_contract_test');
    app = _App();
  });

  tearDown(() => root.deleteSync(recursive: true));

  File snapshot(int version) =>
      File('${root.path}/.restage/library-contracts/app/v$version.json');

  void enforce(
    Catalog catalog, {
    bool write = true,
    Map<String, List<String>> enumMembers = const {},
  }) =>
      enforceLibraryContracts(
        catalog,
        root: root,
        write: write,
        enumMembers: enumMembers,
      );

  Matcher refusedWith(String message) => throwsA(
        isA<LibraryContractException>().having(
          (e) => e.lines,
          'lines',
          contains(message),
        ),
      );

  final planCard = [
    _widget('PlanCard', [_property('title'), _property('badge')]),
  ];

  test('the first build writes the baseline', () {
    enforce(app.build(planCard, capabilityVersion: 3));

    final contents = snapshot(3).readAsStringSync();
    expect(contents, contains('"namespace": "app"'));
    expect(contents, contains('"capabilityVersion": 3'));
    expect(contents, contains('"compatibleSince": 1'));
    expect(contents, isNot(contains('generatedAt')));
    final decoded = LibraryContractSnapshot.decode(contents, 'v3.json');
    expect(decoded.catalog.widgets.single.name, 'PlanCard');
  });

  test('an unchanged catalog passes without rewriting the snapshot', () {
    enforce(app.build(planCard, capabilityVersion: 3));
    snapshot(3).writeAsStringSync('${snapshot(3).readAsStringSync()}\n');
    final before = snapshot(3).readAsStringSync();

    enforce(
      app.build(
        [
          _widget('PlanCard', [
            _property('title', description: 'Reworded.'),
            _property('badge'),
          ]),
        ],
        capabilityVersion: 3,
      ),
    );
    expect(snapshot(3).readAsStringSync(), before);
  });

  test('a library without a capability version records nothing', () {
    enforce(app.build(planCard));
    expect(Directory('${root.path}/.restage').existsSync(), isFalse);
  });

  test('a renamed parameter fails until the break is declared', () {
    enforce(app.build(planCard, capabilityVersion: 3));
    final renamed = [
      _widget('PlanCard', [_property('title'), _property('label')]),
    ];

    expect(
      () => enforce(app.build(renamed, capabilityVersion: 3)),
      refusedWith(
        '`PlanCard.badge` was removed since library `app` v3. To ship this '
        'break, set capabilityVersion: 4 and compatibleSince: 4.',
      ),
    );
    expect(
      () => enforce(app.build(renamed, capabilityVersion: 4)),
      refusedWith(
        '`PlanCard.badge` was removed since library `app` v3. To ship this '
        'break, set capabilityVersion: 4 and compatibleSince: 4.',
      ),
    );
    expect(snapshot(4).existsSync(), isFalse);

    enforce(app.build(renamed, capabilityVersion: 4, compatibleSince: 4));
    expect(snapshot(4).readAsStringSync(), contains('"compatibleSince": 4'));
  });

  test('a retyped parameter names the type change', () {
    enforce(app.build(planCard, capabilityVersion: 3));
    expect(
      () => enforce(
        app.build(
          [
            _widget('PlanCard', [
              _property('title'),
              _property('badge', type: PropertyType.integer),
            ]),
          ],
          capabilityVersion: 3,
        ),
      ),
      refusedWith(
        '`PlanCard.badge` changed type from string to integer since library '
        '`app` v3. To ship this break, set capabilityVersion: 4 and '
        'compatibleSince: 4.',
      ),
    );
  });

  test('an addition without a version bump fails', () {
    enforce(app.build(planCard, capabilityVersion: 3));
    expect(
      () => enforce(
        app.build(
          [...planCard, _widget('Banner', [])],
          capabilityVersion: 3,
        ),
      ),
      refusedWith(
        'Library `app` changed since v3. Raise capabilityVersion to 4.',
      ),
    );
  });

  test('an addition with a version bump writes the next snapshot', () {
    enforce(app.build(planCard, capabilityVersion: 3));
    enforce(
      app.build([...planCard, _widget('Banner', [])], capabilityVersion: 4),
    );
    expect(snapshot(4).readAsStringSync(), contains('"name": "Banner"'));
    expect(snapshot(3).readAsStringSync(), isNot(contains('Banner')));
  });

  test('compatibleSince never moves back', () {
    enforce(app.build(planCard, capabilityVersion: 4, compatibleSince: 4));
    expect(
      () => enforce(app.build(planCard, capabilityVersion: 5)),
      refusedWith(
        'Library `app` declares compatibleSince 1, below 4 at v4. It never '
        'moves back.',
      ),
    );
  });

  test('capabilityVersion never moves back', () {
    enforce(app.build(planCard, capabilityVersion: 4));
    expect(
      () => enforce(app.build(planCard, capabilityVersion: 3)),
      refusedWith(
        'Library `app` declares capabilityVersion 3, below the recorded v4. '
        'It never moves back.',
      ),
    );
  });

  test('a check without write rights records nothing', () {
    enforce(app.build(planCard, capabilityVersion: 3), write: false);
    expect(snapshot(3).existsSync(), isFalse);
  });

  test('a snapshot that names another version is rejected', () {
    enforce(app.build(planCard, capabilityVersion: 3));
    snapshot(3).renameSync(snapshot(5).path);
    expect(
      () => enforce(app.build(planCard, capabilityVersion: 5)),
      throwsA(isA<FormatException>()),
    );
  });

  group('enum members', () {
    final toneCard = [
      _widget('ToneCard', [_toneProperty()]),
    ];

    test('are recorded in the snapshot', () {
      enforce(
        app.build(toneCard, capabilityVersion: 3),
        enumMembers: {
          _tone: ['calm', 'bold'],
        },
      );
      expect(
        LibraryContractSnapshot.decode(snapshot(3).readAsStringSync(), 'v3')
            .enumMembers,
        {
          _tone: ['calm', 'bold'],
        },
      );
    });

    test('a renamed member is a break naming the property', () {
      enforce(
        app.build(toneCard, capabilityVersion: 3),
        enumMembers: {
          _tone: ['calm', 'bold'],
        },
      );
      expect(
        () => enforce(
          app.build(toneCard, capabilityVersion: 3),
          enumMembers: {
            _tone: ['calm', 'loud'],
          },
        ),
        refusedWith(
          '`ToneCard.tone` lost or renamed an enum value since library `app` '
          'v3. To ship this break, set capabilityVersion: 4 and '
          'compatibleSince: 4.',
        ),
      );
    });

    test('an added member needs a version bump', () {
      enforce(
        app.build(toneCard, capabilityVersion: 3),
        enumMembers: {
          _tone: ['calm'],
        },
      );
      expect(
        () => enforce(
          app.build(toneCard, capabilityVersion: 3),
          enumMembers: {
            _tone: ['calm', 'bold'],
          },
        ),
        refusedWith(
          'Library `app` changed since v3. Raise capabilityVersion to 4.',
        ),
      );
      enforce(
        app.build(toneCard, capabilityVersion: 4),
        enumMembers: {
          _tone: ['calm', 'bold'],
        },
      );
      expect(snapshot(4).existsSync(), isTrue);
    });
  });

  test('editor metadata changes pass without rewriting the snapshot', () {
    enforce(app.build(planCard, capabilityVersion: 3));
    final before = snapshot(3).readAsStringSync();
    enforce(
      app.build(
        [
          _widget('PlanCard', [
            _property('title', priority: PropertyPriority.primary),
            _property('badge'),
          ]),
        ],
        capabilityVersion: 3,
      ),
    );
    expect(snapshot(3).readAsStringSync(), before);
  });
}
