import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

Widget onboarding(Widget child) =>
    RestageOnboardingEventDispatcher(onEvent: (_, __) {}, child: child);

Widget surface(Widget child) =>
    RestageSurfaceEventDispatcher(onEvent: (_, __) {}, child: child);
