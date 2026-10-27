import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget(
  library: WidgetLibrary.custom('key.fixture'),
  description: 'A native state owner used to check constructor key forwarding.',
)
class NativeKeyWidget extends StatefulWidget {
  const NativeKeyWidget({super.key});

  @override
  State<NativeKeyWidget> createState() => NativeKeyWidgetState();
}

class NativeKeyWidgetState extends State<NativeKeyWidget> {
  @override
  Widget build(BuildContext context) => const Text('native');
}

@RestageWidget(
  library: WidgetLibrary.custom('key.fixture'),
  description: 'A native constructor with a canonical non-null key default.',
)
class DefaultNativeKeyWidget extends StatelessWidget {
  const DefaultNativeKeyWidget({Key? key = const ObjectKey('default')})
    : super(key: key);

  @override
  Widget build(BuildContext context) => const Text('default');
}
