import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/customer_structured_admissibility.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/restage_widget_walker.dart';
import 'package:restage_codegen/src/user_catalog_allocation.dart';
import 'package:restage_codegen/src/user_factory_emitter.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final class _CollectionProbeBuilder implements Builder {
  RestageWidgetCollection? collection;
  Object? error;

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$lib$': ['record_slot_probe.txt'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    try {
      collection = await collectRestageWidgetsForPackage(buildStep);
    } on Object catch (caught) {
      error = caught;
    }
    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, 'lib/record_slot_probe.txt'),
      'collected',
    );
  }
}

Future<
    ({
      RestageWidgetCollection? collection,
      Object? error,
      List<String> logs,
    })> _collect(String source) async {
  final builder = _CollectionProbeBuilder();
  final logs = <String>[];
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'restage_codegen',
  );
  readerWriter.testing.writeString(
    AssetId('apps_examples', 'lib/header.dart'),
    source,
  );
  await testBuilder(
    builder,
    {'apps_examples|lib/header.dart': source},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    outputs: {
      'apps_examples|lib/record_slot_probe.txt': decodedMatches('collected'),
    },
    onLog: (record) => logs.add(record.message),
  );
  return (
    collection: builder.collection,
    error: builder.error,
    logs: logs,
  );
}

String _fixture(
  String declarations, {
  int? capabilityVersion,
}) =>
    '''
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageLibrary(
    library: WidgetLibrary.custom('acme.design_system'),
    ${capabilityVersion == null ? '' : 'capabilityVersion: $capabilityVersion,'}
  )
  const restageLibrary = 0;

  enum Tone { neutral, emphasis }

  class Plan {
    const Plan({required this.name});
    final String name;
  }

  $declarations
''';

const _recordWidget = '''
  @RestageWidget(
    name: 'SectionHeader',
    library: WidgetLibrary.custom('acme.design_system'),
    category: WidgetCategory.decoration,
    description: 'A section heading.',
  )
  class SectionHeader {
    const SectionHeader({required this.heading});

    @RestageProperty(description: 'The heading values.')
    final ({String title, int step, Tone tone}) heading;
  }
''';

const _nestedRecordWidget = '''
  class Entry {
    const Entry({required this.label, required this.meta});
    final String label;
    final ({String title, int step, Tone tone}) meta;
  }

  @RestageWidget(
    name: 'SectionHeader',
    library: WidgetLibrary.custom('acme.design_system'),
    category: WidgetCategory.decoration,
    description: 'A section heading.',
  )
  class SectionHeader {
    const SectionHeader({required this.entry});

    @RestageProperty(description: 'The heading entry.')
    final Entry entry;
  }
''';

const _recordReconstructionWidget = '''
  class Entry {
    const Entry({required this.meta});
    final ({String title, int step, Tone tone}) meta;
  }

  @RestageWidget(
    name: 'SectionHeader',
    library: WidgetLibrary.custom('acme.design_system'),
    category: WidgetCategory.decoration,
    description: 'A section heading.',
  )
  class SectionHeader {
    const SectionHeader({required this.heading, required this.entry});

    @RestageProperty(description: 'The heading values.')
    final ({String title, int step, Tone tone}) heading;

    @RestageProperty(description: 'The heading entry.')
    final Entry entry;
  }
''';

const _nullableRecordWidget = '''
  @RestageWidget(
    name: 'SectionHeader',
    library: WidgetLibrary.custom('acme.design_system'),
    category: WidgetCategory.decoration,
    description: 'A section heading.',
  )
  class SectionHeader {
    const SectionHeader({this.heading});

    @RestageProperty(description: 'The optional heading values.')
    final ({String title, int step, Tone tone})? heading;
  }
''';

/// A widget whose only customer value slot is a map — the shape whose
/// allocation passthrough is asserted below.
const _mapWidget = '''
  @RestageWidget(
    name: 'FieldNotes',
    library: WidgetLibrary.custom('acme.design_system'),
    category: WidgetCategory.decoration,
    description: 'A set of annotated field notes.',
  )
  class FieldNotes {
    const FieldNotes({required this.glossary});

    @RestageProperty(description: 'The term glossary.')
    final Map<String, String> glossary;
  }
''';

const _filteringWidgets = '''
  @RestageWidget(
    name: 'SectionHeader',
    library: WidgetLibrary.custom('acme.design_system'),
    category: WidgetCategory.decoration,
    description: 'A section heading.',
  )
  class SectionHeader {
    const SectionHeader({
      required this.heading,
      required this.invalid,
    });

    @RestageProperty(description: 'The heading values.')
    final ({String title, int step}) heading;

    @RestageProperty(description: 'The invalid values.')
    final ({String title, int? step}) invalid;
  }

  @RestageWidget(
    name: 'PlanCard',
    library: WidgetLibrary.custom('acme.design_system'),
    category: WidgetCategory.decoration,
    description: 'A scalar fallback.',
  )
  class PlanCard {
    const PlanCard({required this.name});

    @RestageProperty(description: 'The plan name.')
    final String name;
  }
''';

void main() {
  test('a record-only library raises its declared capability version',
      () async {
    final declaredRun = await _collect(
      _fixture(_recordWidget, capabilityVersion: 3),
    );

    expect(declaredRun.error, isNull);
    final collection = declaredRun.collection!;
    // The stamp alone does not discriminate because every declaring library is
    // stamped. The undeclared case below pins the record-property raise.
    expect(
      collection.stampedCapabilityVersions['acme.design_system'],
      3,
    );

    final undeclaredRun = await _collect(_fixture(_recordWidget));

    expect(undeclaredRun.error, isA<StateError>());
    final matchingIssues = undeclaredRun.logs.where(
      (message) =>
          message.contains(
            IssueCode.customLibraryMissingCapabilityVersion.name,
          ) &&
          message.contains('acme.design_system'),
    );
    expect(matchingIssues, hasLength(1));
  });

  test('a nested record field raises its library capability version', () async {
    final declaredRun = await _collect(
      _fixture(_nestedRecordWidget, capabilityVersion: 3),
    );

    expect(declaredRun.error, isNull);
    final collection = declaredRun.collection!;
    expect(
      collection.stampedCapabilityVersions['acme.design_system'],
      3,
    );

    final undeclaredRun = await _collect(_fixture(_nestedRecordWidget));

    expect(undeclaredRun.error, isA<StateError>());
    final matchingIssues = undeclaredRun.logs.where(
      (message) =>
          message.contains(
            IssueCode.customLibraryMissingCapabilityVersion.name,
          ) &&
          message.contains('acme.design_system'),
    );
    expect(matchingIssues, hasLength(1));
  });

  test('a scalar-only library without a capability version is not forced',
      () async {
    final run = await _collect(
      _fixture('''
        @RestageWidget(
          name: 'SectionHeader',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.decoration,
          description: 'A section heading.',
        )
        class SectionHeader {
          const SectionHeader({required this.heading});

          @RestageProperty(description: 'The heading.')
          final String heading;
        }
      '''),
    );

    expect(run.error, isNull);
    final collection = run.collection!;
    expect(
      collection.stampedCapabilityVersions,
      isNot(contains('acme.design_system')),
    );
    expect(
      run.logs.where(
        (message) => message.contains(
          IssueCode.customLibraryMissingCapabilityVersion.name,
        ),
      ),
      isEmpty,
    );
  });

  test('a record library without a capability version emits the named issue',
      () async {
    final run = await _collect(_fixture(_recordWidget));

    expect(run.error, isA<StateError>());
    final matchingIssues = run.logs.where(
      (message) =>
          message.contains(
            IssueCode.customLibraryMissingCapabilityVersion.name,
          ) &&
          message.contains('acme.design_system'),
    );
    expect(matchingIssues, hasLength(1));
  });

  test('catalog allocation bypasses an admitted record property', () async {
    final run = await _collect(
      _fixture(_recordWidget, capabilityVersion: 3),
    );
    expect(run.error, isNull);
    // A null here is this tripwire firing, not an unrelated harness fault.
    expect(
      run.collection,
      isNotNull,
      reason: 'the widget walk produced no collection: has a record shape been '
          'folded into the nominal structured slot predicate?',
    );
    final collection = run.collection!;
    final originalWidget = collection.widgets.single;
    final originalProperty = originalWidget.properties.singleWhere(
      (property) => property.name == 'heading',
    );
    expect(isCustomerRecordShape(originalProperty.valueShape), isTrue);
    expect(originalProperty.structuredRef, isNull);

    late UserCatalogAllocation allocation;
    expect(
      () {
        allocation = allocateUserCatalogFromWidgets(
          package: 'apps_examples',
          widgets: collection.widgets,
          structuredTypes: collection.structuredTypes,
          slotTargets: collection.slotTargets,
          stampedCapabilityVersions: collection.stampedCapabilityVersions,
          exclusions: collection.exclusions,
        );
      },
      returnsNormally,
    );

    final allocatedProperty = allocation.catalog.widgets.single.properties
        .singleWhere((property) => property.name == 'heading');
    expect(isCustomerRecordShape(allocatedProperty.valueShape), isTrue);
    expect(allocatedProperty.valueShape, originalProperty.valueShape);
    expect(allocatedProperty.structuredRef, isNull);
  });

  // The map shape's allocation outcome is pinned HERE, beside the record one,
  // because both pin the SAME invariant for two shapes: a customer value slot
  // travels through a build-time sidecar and must not be routed through
  // nominal target allocation. Keeping them together means a change to
  // allocation breaks both in one place, and a reader meeting one finds the
  // other.
  //
  // The OUTCOME is asserted, never the predicate: a predicate assertion just
  // restates the code and cannot fail. The outcome is that the slot reaches the
  // allocated catalog unresolved and byte-equal to what the walk produced. That
  // is the right thing to pin because the generated factory never reads an
  // allocated identity for these slots at all — the emitter carries zero
  // wire-id references across its whole surface, so a map slot that HAD been
  // resolved would still emit, and only this assertion would notice.
  test('catalog allocation bypasses an admitted map property', () async {
    final run = await _collect(_fixture(_mapWidget, capabilityVersion: 3));
    expect(run.error, isNull);
    // A null here is this tripwire firing, not an unrelated harness fault.
    expect(
      run.collection,
      isNotNull,
      reason: 'the widget walk produced no collection: has a map shape been '
          'folded into the nominal structured slot predicate?',
    );
    final collection = run.collection!;
    final originalWidget = collection.widgets.single;
    final originalProperty = originalWidget.properties.singleWhere(
      (property) => property.name == 'glossary',
    );
    expect(isCustomerMapShape(originalProperty.valueShape), isTrue);
    expect(originalProperty.structuredRef, isNull);

    late UserCatalogAllocation allocation;
    expect(
      () {
        allocation = allocateUserCatalogFromWidgets(
          package: 'apps_examples',
          widgets: collection.widgets,
          structuredTypes: collection.structuredTypes,
          slotTargets: collection.slotTargets,
          stampedCapabilityVersions: collection.stampedCapabilityVersions,
          exclusions: collection.exclusions,
        );
      },
      returnsNormally,
    );

    final allocatedProperty = allocation.catalog.widgets.single.properties
        .singleWhere((property) => property.name == 'glossary');
    expect(isCustomerMapShape(allocatedProperty.valueShape), isTrue);
    expect(allocatedProperty.valueShape, originalProperty.valueShape);
    expect(allocatedProperty.structuredRef, isNull);
  });

  test('record plans use exact slot keys, canonical labels, and enum identity',
      () async {
    final directRun = await _collect(
      _fixture(_recordWidget, capabilityVersion: 3),
    );
    expect(directRun.error, isNull);
    final directCollection = directRun.collection!;
    final sectionHeader = directCollection.widgets.single;
    final directKey = structuredSlotKey(
      sectionHeader.flutterType,
      'heading',
    );
    expect(directCollection.recordPlans, hasLength(1));
    expect(directCollection.recordPlans.keys.single, directKey);
    final directPlan = directCollection.recordPlans[directKey]!;
    expect(
      directPlan.labels.map((label) => label.name).toList(),
      ['step', 'title', 'tone'],
    );
    final labelsByName = {
      for (final label in directPlan.labels) label.name: label,
    };
    expect(labelsByName['tone']!.enumLibraryUri, isNotNull);
    expect(labelsByName['tone']!.enumTypeName, 'Tone');
    for (final name in ['step', 'title']) {
      expect(labelsByName[name]!.enumLibraryUri, isNull);
      expect(labelsByName[name]!.enumTypeName, isNull);
    }

    final nestedRun = await _collect(
      _fixture(_nestedRecordWidget, capabilityVersion: 3),
    );
    expect(nestedRun.error, isNull);
    final nestedCollection = nestedRun.collection!;
    final entry = nestedCollection.structuredTypes.singleWhere(
      (structured) => structured.name == 'Entry',
    );
    final nestedKey = structuredSlotKey(entry.sourceType, 'meta');
    expect(nestedCollection.recordPlans, hasLength(1));
    expect(nestedCollection.recordPlans.keys.single, nestedKey);
    expect(
      nestedCollection.recordPlans[nestedKey]!.labels
          .map((label) => label.name)
          .toList(),
      ['step', 'title', 'tone'],
    );
  });

  test('record plans are filtered to admitted slots with the named cause',
      () async {
    final run = await _collect(
      _fixture(
        _filteringWidgets,
        capabilityVersion: 3,
      ),
    );

    expect(run.error, isNull);
    final collection = run.collection!;
    expect(collection.widgets.map((widget) => widget.name), ['PlanCard']);
    final result = await runWidgetVisitorOn(
      {
        'lib/header.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          $_filteringWidgets
        ''',
      },
    );
    final admission = computeAdmission(
      widgets: result.widgets,
      structuredTypes: result.structuredTypes,
      slotTargets: result.slotTargets,
      localUnrenderable: result.localUnrenderable,
      widgetUnrenderable: result.widgetUnrenderable,
    );
    expect(admission.excluded, hasLength(1));
    expect(admission.excluded.single.widget.name, 'SectionHeader');
    expect(
      admission.excluded.single.reason,
      allOf(
        contains('step'),
        contains('nullable'),
      ),
    );
    expect(collection.recordPlans, isEmpty);
  });

  group('generated record reconstruction', () {
    test('an absent nullable record reconstructs as null', () async {
      final run = await _collect(
        _fixture(_nullableRecordWidget, capabilityVersion: 3),
      );

      expect(run.error, isNull);
      final collection = run.collection!;
      expect(
        collection.nullableStructuredSlots,
        contains(
          structuredSlotKey(
            'package:apps_examples/header.dart#SectionHeader',
            'heading',
          ),
        ),
      );
      final source = emitUserFactoriesDart(
        collection.widgets,
        structuredTypes: collection.structuredTypes,
        slotTargets: collection.slotTargets,
        nullableStructuredSlots: collection.nullableStructuredSlots,
        reconstructionPlans: collection.reconstructionPlans,
        recordPlans: collection.recordPlans,
        stampedCapabilityVersions: collection.stampedCapabilityVersions,
      )!;
      final flat = source.replaceAll(RegExp(r'\s+'), ' ');

      expect(
        flat,
        contains("source.isMap(<Object>['heading']) ? ("),
      );
      expect(flat, contains(': null,'));
      expect(
        flat,
        isNot(contains('SectionHeader.heading is required.')),
      );
    });

    test('emits direct and nested records as presence-guarded hard reads',
        () async {
      final run = await _collect(
        _fixture(
          _recordReconstructionWidget,
          capabilityVersion: 3,
        ),
      );

      expect(run.error, isNull);
      final collection = run.collection!;
      final source = emitUserFactoriesDart(
        collection.widgets,
        structuredTypes: collection.structuredTypes,
        slotTargets: collection.slotTargets,
        nullableStructuredSlots: collection.nullableStructuredSlots,
        reconstructionPlans: collection.reconstructionPlans,
        recordPlans: collection.recordPlans,
        stampedCapabilityVersions: collection.stampedCapabilityVersions,
      )!;

      final flat = source.replaceAll(RegExp(r'\s+'), ' ');

      expect(
        flat,
        contains("source.isMap(<Object>['heading'])"),
      );
      expect(
        flat,
        contains(
          ": (throw ArgumentError('SectionHeader.heading is required.'))",
        ),
      );
      expect(
        flat,
        contains(
          RegExp(
            r"source\.v<int>\(<Object>\['heading', 'step'\]\) \?\? "
            r'\(throw ArgumentError\(\s*'
            r"'SectionHeader\.heading\.step is required\.'\)\)",
          ),
        ),
      );
      expect(
        flat,
        contains(
          RegExp(
            r"source\.v<String>\(<Object>\['heading', 'title'\]\) \?\? "
            r'\(throw ArgumentError\(\s*'
            r"'SectionHeader\.heading\.title is required\.'\)\)",
          ),
        ),
      );
      expect(
        flat,
        contains('RestageDecoders.enumByName<s0.Tone>('),
      );
      expect(
        flat,
        contains('s0.Tone.values'),
      );
      expect(
        flat,
        contains(
          "<Object>['heading', 'tone']) ??",
        ),
      );
      expect(
        flat,
        contains(
          RegExp(
            r'\(throw ArgumentError\(\s*'
            r"'SectionHeader\.heading\.tone is required\.'\)\)",
          ),
        ),
      );
      expect(
        flat,
        isNot(contains('RestageDecoders.enumByName<Tone>(')),
      );

      const headingGuard = "source.isMap(<Object>['heading'])";
      final headingStart = flat.indexOf(headingGuard);
      expect(headingStart, greaterThanOrEqualTo(0));
      final headingEnd = flat.indexOf(
        "'SectionHeader.heading is required.'",
        headingStart,
      );
      expect(headingEnd, greaterThan(headingStart));
      final headingBlock = flat.substring(headingStart, headingEnd);
      final headingStep = headingBlock.indexOf('step:');
      final headingTitle = headingBlock.indexOf('title:');
      final headingTone = headingBlock.indexOf('tone:');
      expect(headingStep, greaterThanOrEqualTo(0));
      expect(headingStep, lessThan(headingTitle));
      expect(headingTitle, lessThan(headingTone));

      expect(
        flat,
        contains("source.isMap(<Object>['entry', 'meta'])"),
      );
      expect(
        flat,
        contains(
          RegExp(
            r'source\s*\.v<int>\('
            r"<Object>\['entry', 'meta', 'step'\]\) \?\?",
          ),
        ),
      );
      expect(
        flat,
        contains(
          RegExp(
            r'\(throw ArgumentError\(\s*'
            r"'Entry\.meta\.step is required\.'\)\)",
          ),
        ),
      );
      expect(
        flat,
        contains(
          RegExp(
            r'source\s*\.v<String>\('
            r"<Object>\['entry', 'meta', 'title'\]\) \?\?",
          ),
        ),
      );
      expect(
        flat,
        contains(
          RegExp(
            r'\(throw ArgumentError\(\s*'
            r"'Entry\.meta\.title is required\.'\)\)",
          ),
        ),
      );
      expect(
        flat,
        contains(
          RegExp(
            r'RestageDecoders\.enumByName<s0\.Tone>\(\s*s0\.Tone\.values, '
            r"source, <Object>\['entry', 'meta', 'tone'\]\) \?\?",
          ),
        ),
      );
      expect(
        flat,
        contains(
          RegExp(
            r'\(throw ArgumentError\(\s*'
            r"'Entry\.meta\.tone is required\.'\)\)",
          ),
        ),
      );
      expect(
        flat,
        contains(
          RegExp(
            r'\(throw ArgumentError\(\s*'
            r"'Entry\.meta is required\.'\)\)",
          ),
        ),
      );

      final nestedStep = flat.indexOf("<Object>['entry', 'meta', 'step']");
      final nestedTitle = flat.indexOf("<Object>['entry', 'meta', 'title']");
      final nestedTone = flat.indexOf("<Object>['entry', 'meta', 'tone']");
      expect(nestedStep, greaterThanOrEqualTo(0));
      expect(nestedStep, lessThan(nestedTitle));
      expect(nestedTitle, lessThan(nestedTone));

      // Data classes may reproduce enum defaults, but a record label must not
      // fabricate a value the author never sent.
      expect(
        flat,
        isNot(contains("<Object>['heading', 'tone']) ?? s0.Tone.")),
      );
      expect(
        flat,
        isNot(
          contains("<Object>['entry', 'meta', 'tone']) ?? s0.Tone."),
        ),
      );
      expect(
        flat,
        isNot(contains(RegExp(r'\?\?\s+s0\.Tone\.'))),
        reason: 'record enum labels must throw instead of defaulting to an '
            'enum member',
      );
    });
  });
}
