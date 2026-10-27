part of 'builder_binding.dart';

final class _BuilderBindingLifetime extends StatefulWidget {
  const _BuilderBindingLifetime({required this.bindings, required this.child});
  final List<RestageBuilderBinding> bindings;
  final Widget child;

  @override
  State<_BuilderBindingLifetime> createState() =>
      _BuilderBindingLifetimeState();
}

final class _BuilderBindingLifetimeState
    extends State<_BuilderBindingLifetime> {
  @override
  void didUpdateWidget(_BuilderBindingLifetime oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final binding in oldWidget.bindings) {
      if (!widget.bindings.contains(binding)) binding.dispose();
    }
  }

  @override
  void dispose() {
    for (final binding in widget.bindings) {
      binding.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
