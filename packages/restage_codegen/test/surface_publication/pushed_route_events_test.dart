import 'package:build/build.dart';
import 'package:restage_codegen/src/surface_publication/pushed_route_events.dart';
import 'package:test/test.dart';

import '../helpers.dart';

const _plans = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Paywall(id: 'plans')
class Plans extends StatelessWidget {
  const Plans({super.key});

  static const pick = SurfaceEvent<void>('pick');

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: context.surfaceEvent(pick),
        child: const Text('Pick'),
      );
}
''';

Future<List<String>> _warnings(String offer, {bool recorded = false}) =>
    resolveWorkspaceSources(
      {
        'apps_examples|lib/offer.dart': offer,
        'apps_examples|lib/plans.dart': _plans,
      },
      (resolver) async {
        final library = await resolver.libraryFor(
          AssetId('apps_examples', 'lib/offer.dart'),
        );
        return await pushedRouteEventWarnings(
          library,
          path: 'lib/offer.dart',
          astNodeFor: (fragment) =>
              resolver.astNodeFor(fragment, resolve: true),
          recorded: {
            if (recorded) library.classes.singleWhere((c) => c.name == 'Offer'),
          },
        );
      },
      resolverFor: 'apps_examples|lib/offer.dart',
      rootPackage: 'apps_examples',
      includeFlutter: true,
    );

String _offer(String annotation) =>
    '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'plans.dart';

$annotation
class Offer extends StatefulWidget {
  const Offer({super.key});

  @override
  State<Offer> createState() => _OfferState();
}

class _OfferState extends State<Offer> {
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const Plans()),
        ),
        child: const Text('All plans'),
      );
}
''';

void main() {
  test(
    "a paywall's next screen keeps its push and names the generated mount",
    () async {
      final warnings = await _warnings(_offer('@Paywall()'));
      expect(warnings, hasLength(1));
      expect(
        warnings.single,
        'The route at lib/offer.dart:19:51 shows the paywall screen `Plans`, '
        'which fires `context.surfaceEvent(...)`. The delivered paywall '
        'carries its events, but when the app shows its own copy of the '
        'paywall, events on that screen refuse. Try adding '
        "`part 'restage.generated/offer.restage.g.dart';` to lib/offer.dart "
        'and mounting `OfferSurface`, whose copy carries them. Keep the push '
        'as it is: wrapping it would stop the delivered paywall from showing '
        'the screen.',
      );
    },
  );

  test('a recorded paywall is not warned about from its State', () async {
    final warnings = await _warnings(_offer('@Paywall()'), recorded: true);
    expect(warnings, isEmpty);
  });

  test('any other route is told how to carry the surface', () async {
    final warnings = await _warnings(_offer(''));
    expect(warnings.single, contains('Try wrapping the route'));
  });
}
