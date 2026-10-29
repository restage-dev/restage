import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/runtime/installed_widget_vocabulary.dart';
import 'package:restage/src/runtime/library_runtime_registry.dart';
import 'package:restage_shared/restage_shared.dart' show InstalledCapability;

void main() {
  tearDown(LibraryRuntimeRegistry.clear);

  // Every way what the hash covers can change: a caller-owned widget map, a
  // caller-owned icon map, and the library registry.
  test(
      'the installed capability is built again only when what it reports '
      'changes', () {
    final builders = <String, LocalWidgetBuilder>{
      'MemoProbe': (_, __) => const SizedBox(),
    };
    final glyphs = <int, IconData>{0xe001: const IconData(0xe001)};
    InstalledWidgetLibraries.install(
        RestageWidgetLibraries.fromVocabulary(core: builders));
    InstalledIconTable.install(
        RestageIconTable.fromFamilies(families: {'MemoIcons': glyphs}));
    final first = currentInstalledCapability();
    expect(currentInstalledCapability(), same(first));

    InstalledCapability changed(void Function() change) {
      final before = currentInstalledCapability();
      change();
      final after = currentInstalledCapability();
      expect(after, isNot(same(before)));
      expect(after.contentHash, isNot(before.contentHash));
      expect(currentInstalledCapability(), same(after));
      return after;
    }

    expect(
        changed(() => builders['MemoOther'] = (_, __) => const SizedBox())
            .vocabulary!
            .widgetNames,
        contains('restage.core:MemoOther'));
    expect(
        changed(() => glyphs[0xe002] = const IconData(0xe002))
            .vocabulary!
            .iconCodePoints['MemoIcons'],
        {0xe001, 0xe002});
    expect(
        changed(() => LibraryRuntimeRegistry.register(
                WidgetLibrary.custom('memo.probe'), const [],
                capabilityVersion: 1))
            .installedLibraries
            .map((library) => library.namespace),
        contains('memo.probe'));
    changed(LibraryRuntimeRegistry.clear);
  });
}
