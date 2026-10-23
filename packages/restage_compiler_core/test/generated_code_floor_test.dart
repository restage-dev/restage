import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_shared/rfw_formats.dart' show parseLibraryFile;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

const _library = WidgetLibrary.custom('acme.ui');
final _ref = WireIdRef(library: 'acme.ui', wireId: WireId('s0001'));

WidgetEntry _widget(String name, List<PropertyEntry> properties) => WidgetEntry(
      wireId: WireId('w${name.length.toString().padLeft(4, '0')}'),
      name: name,
      library: _library,
      category: WidgetCategory.decoration,
      description: name,
      flutterType: 'package:acme/ui.dart#$name',
      childrenSlot: ChildrenSlot.none,
      properties: properties,
    );

PropertyEntry _property(String name, PropertyType type, {WireIdRef? ref}) =>
    PropertyEntry(
      wireId: WireId('p0001'),
      name: name,
      type: type,
      description: name,
      structuredRef: ref,
    );

StructuredEntry _part({
  List<FactoryVariant>? variants,
  PropertyType fieldType = PropertyType.real,
}) =>
    StructuredEntry(
      wireId: WireId('s0001'),
      name: 'Part',
      library: _library,
      description: 'Part',
      sourceType: 'package:acme/ui.dart#Part',
      fields: [
        StructuredField(
          wireId: WireId('p0002'),
          name: 'x',
          type: fieldType,
          description: 'x',
        ),
      ],
      variants: variants ?? [ConstructorVariant(wireId: WireId('v0001'))],
    );

Catalog _catalog(
  List<WidgetEntry> widgets, {
  List<StructuredEntry> structured = const [],
  List<PropertyExclusion> exclusions = const [],
}) =>
    Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '1970-01-01T00:00:00Z',
      libraries: {
        _library: const LibraryInfo(version: '1.0.0', capabilityVersion: 3),
      },
      widgets: widgets,
      structuredTypes: structured,
      exclusions: exclusions,
    );

void main() {
  final plain = _widget('Plain', [_property('label', PropertyType.string)]);
  final mark = _widget('Mark', [
    _property('part', PropertyType.structured, ref: _ref),
  ]);

  test('a widget of scalar properties needs only the first generated code', () {
    expect(generatedCodeFloor(plain, _catalog([plain])), 1);
    expect(
      generatedCodeFloor(mark, _catalog([mark], structured: [_part()])),
      1,
    );
  });

  test('newer value shapes need the current generated code', () {
    final named = _part(
      variants: [
        ConstructorVariant(wireId: WireId('v0001'), namedConstructor: 'dot'),
      ],
    );
    expect(generatedCodeFloor(mark, _catalog([mark], structured: [named])), 2);
    final listed = _part(fieldType: PropertyType.realList);
    expect(generatedCodeFloor(mark, _catalog([mark], structured: [listed])), 2);
    final styled = _widget('Styled', [
      _property(
        'style',
        PropertyType.structured,
        ref: WireIdRef(library: 'restage.core', wireId: WireId('s0002')),
      ),
    ]);
    expect(generatedCodeFloor(styled, _catalog([styled])), 2);
    final dropped = _catalog(
      [plain],
      exclusions: [
        const PropertyExclusion(
          widget: 'Plain',
          property: 'link',
          target: 'rfw',
          reason: 'cannot render',
          location: 'package:acme/ui.dart#Plain.link',
        ),
      ],
    );
    expect(generatedCodeFloor(plain, dropped), 2);
    final elsewhere = _catalog(
      [plain],
      exclusions: [
        const PropertyExclusion(
          widget: 'Plain',
          property: 'link',
          target: 'rfw',
          reason: 'cannot render',
          location: 'package:other/ui.dart#Plain.link',
        ),
      ],
    );
    expect(generatedCodeFloor(plain, elsewhere), 1);
  });

  test('the manifest requires the floor per library, default left implicit',
      () {
    final surface = parseLibraryFile('''
import acme.ui;
widget Screen = Mark();
''');
    final named = _part(
      variants: [
        ConstructorVariant(wireId: WireId('v0001'), namedConstructor: 'dot'),
      ],
    );
    final requirement = deriveSurfaceCapability(
      surface,
      _catalog([mark], structured: [named]),
    ).requiredLibraries.single;
    expect(requirement.minVersion, 3);
    expect(requirement.minGenerated, 2);

    final plainRequirement = deriveSurfaceCapability(
      parseLibraryFile('import acme.ui;\nwidget Screen = Plain();'),
      _catalog([plain]),
    ).requiredLibraries.single;
    expect(plainRequirement.minGenerated, 1);
    expect(plainRequirement.toJson(), {
      'namespace': 'acme.ui',
      'minVersion': 3,
    });
  });
}
