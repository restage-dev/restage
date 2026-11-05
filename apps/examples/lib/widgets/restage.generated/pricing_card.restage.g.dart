part of '../pricing_card.dart';

// ignore_for_file: type=lint, unnecessary_cast

const restageIslands$PricingCard_Column_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'PricingCard_Column_0',
              builder: _restageIsland$PricingCard_Column_0)
        ],
        islands: true);

Widget _restageIsland$PricingCard_Column_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'PricingCard_Column_0',
        '`Column` (lib/widgets/pricing_card.dart:106:14) needs app code that only `PricingCard__split` provides. Try using `PricingCard__split` to build this screen.',
        context,
        source);

Widget restagePreview$PricingCard_Column_0(
        BuildContext restageContext, DataSource restageSource) =>
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
    );

Widget _restageBuild$PricingCard__split(
        BuildContext context, DataSource source) =>
    RestageIslandScope.split(
        context, source, () => _restageWidget$PricingCard(source: source));

/// [widget], placed by the app, as the design places it.
Widget restageSplitApp$PricingCard(PricingCard widget) =>
    _restageWidget$PricingCard.app(widget);

final class _restageWidget$PricingCard extends StatefulWidget {
  const _restageWidget$PricingCard({required DataSource this.source})
      : app = null;
  const _restageWidget$PricingCard.app(PricingCard this.app) : source = null;

  final DataSource? source;
  final PricingCard? app;

  @override
  __restageWidget$PricingCardState createState() =>
      __restageWidget$PricingCardState();
}

final class __restageWidget$PricingCardState
    extends State<_restageWidget$PricingCard> {
  PricingCard get _restageWidget =>
      widget.app ??
      PricingCard(
          plan: ((DataSource source) => source.isMap(<Object>['plan'])
              ? Plan(
                  name: RestageDecoders.string(source, <Object>['plan', 'name'],
                          context: context) ??
                      (throw ArgumentError('Plan.name is required.')),
                  price: source.isMap(<Object>['plan', 'price'])
                      ? (switch (source.v<String>(
                          <Object>['plan', 'price', '#constructor'])) {
                          'free' => Price.free(
                              currency: RestageDecoders.string(source,
                                      <Object>['plan', 'price', 'currency'],
                                      context: context) ??
                                  'USD'),
                          null => Price(
                              RestageValueBinding.read<int>(
                                      source,
                                      <Object>['plan', 'price', 'amount'],
                                      context) ??
                                  (throw ArgumentError(
                                      'Price.amount is required.')),
                              currency: RestageDecoders.string(source,
                                      <Object>['plan', 'price', 'currency'],
                                      context: context) ??
                                  'USD'),
                          final String name => throw ArgumentError(
                              "'Price' has no constructor named '$name'.")
                        })
                      : (throw ArgumentError('Plan.price is required.')),
                  badge: RestageDecoders.string(
                      source, <Object>['plan', 'badge'], context: context),
                  tier: RestageDecoders.enumByName<PlanTier>(
                          PlanTier.values, source, <Object>['plan', 'tier']) ??
                      PlanTier.starter)
              : (throw ArgumentError(
                  'PricingCard.plan is required.')))(widget.source!));

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    // ignore: unused_local_variable
    final _restageSurface = _restageWidget;
    Widget _restageDesign(Widget _restageBuilt) => RestageIslandScope(
        owner: context,
        builders: {
          'PricingCard_Column_0': (_restageContext, _restageSource) =>
              _restageRecording.islandAt(
                  'PricingCard_Column_0', [], _restageContext, _restageSource)
        },
        child: RestageBuilderBinding.construct((_restageBindings) {
          final _restageSource = widget.source;
          if (_restageSource == null) return _restageBuilt;
          final _restageBody = RestageBuilderBinding.optional(
              _restageSource, const <Object>['restageWidget'],
              context: context);
          if (_restageBody == null) return _restageBuilt;
          _restageBindings.add(_restageBody);
          return _restageBody.buildNullable(context, const {},
                  recorded: _restageRecording.values) ??
              const SizedBox.shrink();
        }));
    return (() {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final major =
          (_restageSurface.plan.price.amount / 100).toStringAsFixed(2);
      return _restageDesign(Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: _restageRecording.island(
            'PricingCard_Column_0',
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_restageSurface.plan.badge case final badge?)
                  Text(
                    badge,
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                Text(_restageSurface.plan.name,
                    style: theme.textTheme.titleLarge),
                Text(
                  '${_restageSurface.plan.price.currency} $major',
                  style: theme.textTheme.headlineSmall,
                ),
                Text(_restageSurface.plan.tier.name,
                    style: theme.textTheme.labelMedium),
              ],
            )),
      ));
    })();
  }
}

const restageSplit$PricingCard = RestageWidgetLibraryRegistration.constant(
    library: WidgetLibrary.custom('restage_example.widgets'),
    generatedVersion: 3,
    widgets: [
      RestageWidgetFactory(
          name: 'PricingCard__split', builder: _restageBuild$PricingCard__split)
    ]);

/// The hash of the delivered definition this wrapper renders.
const restageSplitDefinition$PricingCard = '299528a2ce1c3cfc';
