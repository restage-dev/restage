part of '../minimal_paywall.dart';

final class MinimalPaywallSurface extends StatelessWidget {
  const MinimalPaywallSurface({
    Key? key,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : super(key: key);

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    const SurfaceVocabulary(
      widgets: RestageWidgetLibraries.fromVocabulary(
        core: {
          'Column': buildColumn,
          'Container': buildContainer,
          'Expanded': buildExpanded,
          'GestureDetector': buildGestureDetector,
          'Padding': buildPadding,
          'Row': buildRow,
          'SafeArea': buildSafeArea,
          'SizedBox': buildSizedBox,
          'Spacer': buildSpacer,
          'Text': buildText,
        },
        material: {
          'AppBar': buildAppBar,
          'Scaffold': buildScaffold,
        },
      ),
    ).addToInstalled();
    return RestagePaywall(
      id: "minimal_paywall",
      fallbackBuilder: (context) => MinimalPaywall(),
      onEvent: onEvent,
      resolver: resolver,
      errorBuilder: errorBuilder,
      loadingBuilder: loadingBuilder,
    );
  }
}
