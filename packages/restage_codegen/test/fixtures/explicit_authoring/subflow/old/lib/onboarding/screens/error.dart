import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/error.restage.g.dart';

@ScreenSource(id: 'error')
final class ErrorScreen extends StatelessWidget {
  const ErrorScreen({super.key});

  @override
  Widget build(BuildContext context) => const Text('Unavailable');
}
