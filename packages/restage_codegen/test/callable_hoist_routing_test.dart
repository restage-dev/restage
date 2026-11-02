import 'dart:convert';

import 'package:build/build.dart';
import 'package:restage_codegen/src/hoisting.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';
import 'support/intl_format_authoring.dart';

void main() {
  test(
    'wrapped lookup effects cannot enter any eager host value shape',
    () async {
      for (final modifier in ['const', 'final']) {
        for (final metadata in ['', ", desc: throw StateError('metadata')"]) {
          final lookup = "lookup('fallback', name: 'fixed'$metadata)";
          for (final body in [
            "Text('label', style: wrapStyle($lookup))",
            "Padding(padding: wrapInsets($lookup), child: const Text('label'))",
            "Text('label', style: TextStyle(fontFamilyFallback: wrapList($lookup)))",
          ]) {
            final result = await translateFormatting(
              body,
              extraSource:
                  '''
$modifier lookup = i.Intl.message;
TextStyle wrapStyle(String name) => TextStyle(fontFamily: name);
EdgeInsets wrapInsets(String name) => EdgeInsets.all(name.length.toDouble());
List<String> wrapList(String name) => [name];
''',
            );
            expect(
              result.issues.where((issue) => !issue.code.isBuildNotice),
              isNotEmpty,
              reason: '$modifier $body',
            );
            expect(result.hoisted, isEmpty, reason: '$modifier $body');
          }
        }
      }
    },
  );

  test(
    'fixed non-scalar helpers keep native metadata and host computations',
    () async {
      for (final (body, call, kind) in [
        (
          "Text('label', style: wrapStyle(start, TextAlign.center))",
          'wrapStyle(start, TextAlign.center)',
          HoistValueKind.textStyle,
        ),
        (
          "Padding(padding: wrapInsets(count), child: const Text('label'))",
          'wrapInsets(count)',
          HoistValueKind.edgeInsets,
        ),
      ]) {
        final result = await translateFormatting(
          body,
          extraSource: '''
TextStyle wrapStyle(DateTime date, TextAlign align) => TextStyle(fontFamily: '\${date.year}:\$align');
EdgeInsets wrapInsets(int count) => EdgeInsets.all(count.toDouble());
''',
        );
        expect(
          result.issues.where((issue) => !issue.code.isBuildNotice),
          isEmpty,
          reason: result.issues.map((issue) => issue.message).join('\n'),
        );
        expect(result.hoisted.single.kind, kind);
        expect(result.hoisted.single.mountSource((name) => name), call);
      }
    },
  );

  test(
    'publication refuses wrapped lookup errors and preserves non-scalar capabilities',
    () async {
      for (final (declaration, fields, body, accepted) in [
        for (final modifier in ['const', 'final'])
          (
            "$modifier lookup = i.Intl.message;",
            '',
            "f.Text('label', style: wrap(lookup('fallback', name: 'fixed', desc: throw StateError('metadata'))))",
            false,
          ),
        ('', '', "f.Text('label', style: wrap('native'))", true),
        (
          '',
          'final String Function() lookup;',
          "f.Text('label', style: wrap(lookup()))",
          true,
        ),
      ]) {
        final source =
            '''
import 'package:flutter/widgets.dart' as f;
import 'package:intl/intl.dart' as i;
import 'package:restage/restage.dart' as rs;
part 'restage.generated/callable_hoist.restage.g.dart';
$declaration
f.TextStyle wrap(String name) => f.TextStyle(fontFamily: name);
@rs.Screen(id: 'callable_hoist', surface: rs.Surface.general)
class Probe extends f.StatelessWidget {
  const Probe({super.key${fields.isEmpty ? '' : ', required this.lookup'}});
  $fields
  @override
  f.Widget build(f.BuildContext context) => $body;
}
''';
        final readerWriter = await readerWriterWithFilesystemSources(
          rootPackage: 'apps_examples',
        );
        final result = await testBuilder(
          const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
          {'apps_examples|lib/callable_hoist.dart': source},
          rootPackage: 'apps_examples',
          readerWriter: readerWriter,
          flattenOutput: true,
        );
        final bundle = RestageSurfacePublicationBundle.fromJson(
          jsonDecode(
            readerWriter.testing.readString(
              AssetId(
                'apps_examples',
                kRestageSurfacePublicationCompilerBundlePath,
              ),
            ),
          ),
        );
        expect(result.succeeded, accepted, reason: result.errors.join('\n'));
        expect(bundle.valid, accepted, reason: bundle.errors.join('\n'));
        if (accepted) {
          final generated = utf8.decode(
            bundle
                .ownedOutputs['lib/restage.generated/callable_hoist.restage.g.dart']!,
          );
          expect(generated, contains('restageHostValues('));
          expect(
            generated,
            contains(fields.isEmpty ? "wrap('native')" : 'wrap(lookup())'),
          );
        } else {
          expect(bundle.errors, isNotEmpty);
          expect(bundle.ownedOutputs, isEmpty);
        }
      }
    },
  );

  test(
    'typed constructor callbacks keep their existing scalar host computation',
    () async {
      const source = """
import 'package:flutter/widgets.dart' as f;
import 'package:restage/restage.dart' as rs;
part 'restage.generated/callable_hoist.restage.g.dart';
@rs.Screen(id: 'callable_hoist', surface: rs.Surface.general)
class Probe extends f.StatelessWidget {
  const Probe({super.key, required this.lookup});
  final String Function() lookup;
  @override
  f.Widget build(f.BuildContext context) => f.Text(lookup());
}
""";
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final result = await testBuilder(
        const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
        {'apps_examples|lib/callable_hoist.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      final bundle = RestageSurfacePublicationBundle.fromJson(
        jsonDecode(
          readerWriter.testing.readString(
            AssetId(
              'apps_examples',
              kRestageSurfacePublicationCompilerBundlePath,
            ),
          ),
        ),
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
      final generated = utf8.decode(
        bundle
            .ownedOutputs['lib/restage.generated/callable_hoist.restage.g.dart']!,
      );
      expect(generated, contains('restageHostValues('));
      expect(generated, contains('lookup()'));
    },
  );

  test(
    'root callable aliases cannot use scalar hoists for native lookup effects',
    () async {
      for (final declaration in [
        'const lookup = i.Intl.message;',
        'final lookup = i.Intl.message;',
        'class Alias { static const lookup = i.Intl.message; } const lookup = Alias.lookup;',
        'class Alias { static final lookup = i.Intl.message; } final lookup = Alias.lookup;',
      ]) {
        for (final metadata in ['', ", desc: throw StateError('metadata')"]) {
          final result = await translateFormatting(
            "Text(lookup('fallback', name: 'fixed'$metadata))",
            extraSource: declaration,
          );
          expect(
            result.issues.where((issue) => !issue.code.isBuildNotice),
            isNotEmpty,
            reason: '$declaration $metadata',
          );
          expect(result.hoisted, isEmpty);
        }
      }
    },
  );

  test(
    'staged constant lookup aliases install exact metadata and final aliases refuse',
    () async {
      for (final modifier in ['const', 'final']) {
        final result = await translateFormatting(
          'LayoutBuilder(builder: (context, constraints) { '
          "final label = lookup('fallback', name: 'fixed', desc: fail()); "
          'return Text(label); })',
          extraSource:
              '$modifier lookup = i.Intl.message; String fail() => throw StateError("metadata");',
        );
        if (modifier == 'const') {
          expect(
            result.issues.where((issue) => !issue.code.isBuildNotice),
            isEmpty,
          );
          final adapter = result.hoisted.single.nativeCall!;
          expect(adapter.source, contains('lookup('));
          expect(adapter.source, contains('desc: fail()'));
          expect(adapter.source, contains('name: "fixed"'));
        } else {
          expect(
            result.issues.where((issue) => !issue.code.isBuildNotice),
            isNotEmpty,
          );
          expect(result.hoisted, isEmpty);
        }
      }
    },
  );

  test(
    'fixed native helpers retain their existing scalar hoist route',
    () async {
      for (final call in ['label()', 'fixedAlias()']) {
        final result = await translateFormatting(
          'Text($call)',
          extraSource: "String label() => 'native'; const fixedAlias = label;",
        );
        expect(
          result.issues.where((issue) => !issue.code.isBuildNotice),
          isEmpty,
        );
        expect(result.hoisted.single.kind, HoistValueKind.scalar);
        expect(result.hoisted.single.mountSource((name) => name), call);
      }
    },
  );

  test(
    'production publication refuses root aliases and stages constant aliases',
    () async {
      for (final (modifier, staged) in [
        ('const', false),
        ('final', false),
        ('const', true),
        ('final', true),
      ]) {
        const call =
            "lookup('fallback', name: 'fixed', desc: throw StateError('metadata'))";
        final body = staged
            ? 'f.LayoutBuilder(builder: (context, constraints) { final label = $call; return f.Text(label); })'
            : 'f.Text($call)';
        final source =
            '''
import 'package:flutter/widgets.dart' as f;
import 'package:intl/intl.dart' as i;
import 'package:restage/restage.dart' as rs;
part 'restage.generated/callable_hoist.restage.g.dart';
$modifier lookup = i.Intl.message;
@rs.Screen(id: 'callable_hoist', surface: rs.Surface.general)
class Probe extends f.StatelessWidget {
  const Probe({super.key});
  @override
  f.Widget build(f.BuildContext context) => $body;
}
''';
        final readerWriter = await readerWriterWithFilesystemSources(
          rootPackage: 'apps_examples',
        );
        final result = await testBuilder(
          const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
          {'apps_examples|lib/callable_hoist.dart': source},
          rootPackage: 'apps_examples',
          readerWriter: readerWriter,
          flattenOutput: true,
        );
        final bundle = RestageSurfacePublicationBundle.fromJson(
          jsonDecode(
            readerWriter.testing.readString(
              AssetId(
                'apps_examples',
                kRestageSurfacePublicationCompilerBundlePath,
              ),
            ),
          ),
        );
        final accepted = modifier == 'const' && staged;
        expect(result.succeeded, accepted, reason: result.errors.join('\n'));
        expect(bundle.valid, accepted, reason: bundle.errors.join('\n'));
        if (accepted) {
          final generated = utf8.decode(
            bundle
                .ownedOutputs['lib/restage.generated/callable_hoist.restage.g.dart']!,
          );
          expect(generated, contains('NativeCallAdapter('));
          expect(generated, contains('throw StateError'));
          expect(generated, isNot(contains('restageHostValues(')));
          expect(
            bundle.artifacts.keys,
            contains('assets/general/screens/callable_hoist.rfw'),
          );
        } else {
          expect(bundle.errors, isNotEmpty);
          expect(bundle.ownedOutputs, isEmpty);
        }
      }
    },
  );
}
