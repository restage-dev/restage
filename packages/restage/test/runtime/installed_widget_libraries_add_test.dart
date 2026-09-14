import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

Widget _alpha(BuildContext context, DataSource source) =>
    const SizedBox(key: ValueKey<String>('alpha'));

Widget _beta(BuildContext context, DataSource source) =>
    const SizedBox(key: ValueKey<String>('beta'));

const RestageWidgetLibraries _coreAlpha = RestageWidgetLibraries.fromVocabulary(
  core: <String, LocalWidgetBuilder>{'Alpha': _alpha},
);

const RestageWidgetLibraries _coreBeta = RestageWidgetLibraries.fromVocabulary(
  core: <String, LocalWidgetBuilder>{'Beta': _beta},
);

/// Names the same widget as [_coreAlpha] with a different builder.
const RestageWidgetLibraries _conflictingAlpha =
    RestageWidgetLibraries.fromVocabulary(
  core: <String, LocalWidgetBuilder>{'Alpha': _beta},
);

const RestageWidgetLibraries _materialAlpha =
    RestageWidgetLibraries.fromVocabulary(
  material: <String, LocalWidgetBuilder>{'Alpha': _alpha},
);

const RestageWidgetLibraries _cupertinoBeta =
    RestageWidgetLibraries.fromVocabulary(
  cupertino: <String, LocalWidgetBuilder>{'Beta': _beta},
);

void main() {
  setUp(InstalledWidgetLibraries.reset);
  tearDown(() {
    InstalledWidgetLibraries.install(RestageWidgetLibraries.builtIn());
  });

  test('direct additions select only when nonempty by default', () {
    InstalledWidgetLibraries.add(RestageWidgetLibraries.none);
    expect(InstalledWidgetLibraries.hasSelection, isFalse);
    InstalledWidgetLibraries.add(_coreAlpha);
    expect(InstalledWidgetLibraries.hasSelection, isTrue);
  });

  test('implicit additions do not select the catalog', () {
    InstalledWidgetLibraries.add(_coreAlpha, explicitSelection: false);
    expect(InstalledWidgetLibraries.current.isEmpty, isFalse);
    expect(InstalledWidgetLibraries.hasSelection, isFalse);
  });

  test('an explicit empty selection survives implicit additions', () {
    InstalledWidgetLibraries.add(RestageWidgetLibraries.none,
        explicitSelection: true);
    expect(InstalledWidgetLibraries.current, same(RestageWidgetLibraries.none));
    expect(InstalledWidgetLibraries.hasSelection, isTrue);
    InstalledWidgetLibraries.add(_coreAlpha, explicitSelection: false);
    expect(InstalledWidgetLibraries.hasSelection, isTrue);
    InstalledWidgetLibraries.reset();
    expect(InstalledWidgetLibraries.hasSelection, isFalse);
  });

  test('adding to nothing installs the added libraries', () {
    InstalledWidgetLibraries.add(_coreAlpha);

    expect(InstalledWidgetLibraries.current.core['Alpha'], same(_alpha));
  });

  test('adding unions within a namespace', () {
    InstalledWidgetLibraries.add(_coreAlpha);
    InstalledWidgetLibraries.add(_coreBeta);

    expect(InstalledWidgetLibraries.current.core.keys, {'Alpha', 'Beta'});
  });

  test('adding unions across namespaces', () {
    InstalledWidgetLibraries.add(_coreAlpha);
    InstalledWidgetLibraries.add(_materialAlpha);
    InstalledWidgetLibraries.add(_cupertinoBeta);

    expect(InstalledWidgetLibraries.current.core.keys, {'Alpha'});
    expect(InstalledWidgetLibraries.current.material.keys, {'Alpha'});
    expect(InstalledWidgetLibraries.current.cupertino.keys, {'Beta'});
  });

  test('the installed builder wins over a later conflicting one', () {
    InstalledWidgetLibraries.add(_coreAlpha);
    InstalledWidgetLibraries.add(_conflictingAlpha);

    expect(InstalledWidgetLibraries.current.core['Alpha'], same(_alpha));
  });

  test('adding composes over a prior whole-catalog install', () {
    InstalledWidgetLibraries.install(RestageWidgetLibraries.builtIn());
    InstalledWidgetLibraries.add(_coreAlpha);

    final installed = InstalledWidgetLibraries.current;
    expect(installed.core['Alpha'], same(_alpha));
    expect(installed.core['Column'], same(buildColumn));
    expect(installed.material['Icon'], same(buildIcon));
    expect(installed.cupertino['CupertinoButton'], same(buildCupertinoButton));
  });

  test('a built-in name keeps its catalog builder when added over', () {
    InstalledWidgetLibraries.install(RestageWidgetLibraries.builtIn());
    InstalledWidgetLibraries.add(
      const RestageWidgetLibraries.fromVocabulary(
        core: <String, LocalWidgetBuilder>{'Column': _alpha},
      ),
    );

    expect(InstalledWidgetLibraries.current.core['Column'], same(buildColumn));
  });

  test('adding empty libraries leaves the installation untouched', () {
    InstalledWidgetLibraries.install(_coreAlpha);
    InstalledWidgetLibraries.add(RestageWidgetLibraries.none);

    expect(InstalledWidgetLibraries.current, same(_coreAlpha));
  });

  test('reset clears what add contributed', () {
    InstalledWidgetLibraries.add(_coreAlpha);
    InstalledWidgetLibraries.add(_materialAlpha);
    InstalledWidgetLibraries.reset();

    expect(InstalledWidgetLibraries.current, same(RestageWidgetLibraries.none));
    expect(InstalledWidgetLibraries.current.isEmpty, isTrue);
  });
}
