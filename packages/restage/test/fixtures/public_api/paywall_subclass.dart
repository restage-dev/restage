import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

class ContextAwarePaywall extends RestagePaywall {
  const ContextAwarePaywall({
    super.key,
    required this.hostBuildContext,
    super.context,
  }) : super(id: 'account_upgrade');

  final BuildContext hostBuildContext;

  BuildContext get context => hostBuildContext;
}
