// A bar authored in `Scaffold.appBar` reaches the emitted surface against
// the shipped Material catalog, carrying the height it asks for.

import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('Scaffold.appBar reaches the emitted surface', () async {
    const source = '''
      $kStubAnnotationsAndBases

      @PaywallSource(id: 'scaffold_app_bar')
      class ScaffoldAppBarPaywall extends StatelessWidget {
        const ScaffoldAppBarPaywall();
        Widget build(BuildContext context) => Scaffold(
              appBar: AppBar(toolbarHeight: 72, title: Text('Welcome')),
              body: Center(child: SizedBox()),
            );
      }
    ''';

    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
      includeFlutter: false,
    );
    readerWriter.testing.writeString(
      AssetId('apps_examples', 'lib/paywalls/scaffold_app_bar.dart'),
      source,
    );

    await testBuilder(
      restageCodegenBuilder(BuilderOptions.empty),
      {'apps_examples|lib/paywalls/scaffold_app_bar.dart': source},
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      outputs: {
        'apps_examples|assets/paywalls/scaffold_app_bar.capability.json':
            anything,
        'apps_examples|assets/paywalls/scaffold_app_bar.rfwtxt': decodedMatches(
          allOf(
            contains('Scaffold('),
            contains('appBar: AppBar('),
            contains('title: Text(text: "Welcome")'),
            contains('toolbarHeight: 72.0'),
            contains('appBarHeight: 72.0'),
          ),
        ),
        'apps_examples|assets/paywalls/scaffold_app_bar.rfw': isNotEmpty,
        'apps_examples|assets/paywalls/screens/paywall_scaffold_app_bar.capability.json':
            anything,
        'apps_examples|assets/paywalls/screens/paywall_scaffold_app_bar.rfw':
            isNotEmpty,
      },
    );
  });

  test('a bar with a tab bar under it carries the summed height', () async {
    const source = '''
      $kStubAnnotationsAndBases

      @PaywallSource(id: 'scaffold_tab_bar')
      class ScaffoldTabBarPaywall extends StatelessWidget {
        const ScaffoldTabBarPaywall();
        Widget build(BuildContext context) => DefaultTabController(
              length: 2,
              child: Scaffold(
                appBar: AppBar(
                  title: Text('Welcome'),
                  bottom: TabBar(
                    tabs: [Tab(text: 'One'), Tab(text: 'Two')],
                  ),
                ),
                body: Center(child: SizedBox()),
              ),
            );
      }
    ''';

    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
      includeFlutter: false,
    );
    readerWriter.testing.writeString(
      AssetId('apps_examples', 'lib/paywalls/scaffold_tab_bar.dart'),
      source,
    );

    await testBuilder(
      restageCodegenBuilder(BuilderOptions.empty),
      {'apps_examples|lib/paywalls/scaffold_tab_bar.dart': source},
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      outputs: {
        'apps_examples|assets/paywalls/scaffold_tab_bar.capability.json':
            anything,
        'apps_examples|assets/paywalls/scaffold_tab_bar.rfwtxt': decodedMatches(
          allOf(
            contains('bottom: TabBar('),
            // The tab bar's own tabs plus its selection indicator.
            contains('bottomHeight: 48.0'),
            // The standard toolbar plus the bar below it.
            contains('appBarHeight: 104.0'),
          ),
        ),
        'apps_examples|assets/paywalls/scaffold_tab_bar.rfw': isNotEmpty,
        'apps_examples|assets/paywalls/screens/paywall_scaffold_tab_bar.capability.json':
            anything,
        'apps_examples|assets/paywalls/screens/paywall_scaffold_tab_bar.rfw':
            isNotEmpty,
      },
    );
  });

  test('a bar over a widget stating its own height sums the two', () async {
    const source = '''
      $kStubAnnotationsAndBases

      @PaywallSource(id: 'scaffold_stated_bottom')
      class ScaffoldStatedBottomPaywall extends StatelessWidget {
        const ScaffoldStatedBottomPaywall();
        Widget build(BuildContext context) => Scaffold(
              appBar: AppBar(
                title: Text('Welcome'),
                bottom: PreferredSize(
                  preferredSize: Size.fromHeight(30),
                  child: Text('under'),
                ),
              ),
              body: Center(child: SizedBox()),
            );
      }
    ''';

    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
      includeFlutter: false,
    );
    readerWriter.testing.writeString(
      AssetId('apps_examples', 'lib/paywalls/scaffold_stated_bottom.dart'),
      source,
    );

    await testBuilder(
      restageCodegenBuilder(BuilderOptions.empty),
      {'apps_examples|lib/paywalls/scaffold_stated_bottom.dart': source},
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      outputs: {
        'apps_examples|assets/paywalls/scaffold_stated_bottom.capability.json':
            anything,
        'apps_examples|assets/paywalls/scaffold_stated_bottom.rfwtxt':
            decodedMatches(
          allOf(
            // The size lowers to the bare height the widget asks for.
            contains('PreferredSize(preferredSize: 30.0'),
            contains('bottomHeight: 30.0'),
            contains('appBarHeight: 86.0'),
          ),
        ),
        'apps_examples|assets/paywalls/scaffold_stated_bottom.rfw': isNotEmpty,
        'apps_examples|assets/paywalls/screens/paywall_scaffold_stated_bottom.capability.json':
            anything,
        'apps_examples|assets/paywalls/screens/paywall_scaffold_stated_bottom.rfw':
            isNotEmpty,
      },
    );
  });
}
