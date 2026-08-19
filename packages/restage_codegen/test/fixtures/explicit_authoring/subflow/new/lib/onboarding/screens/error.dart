import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'error.rsscreen.g.dart';

@Screen()
final class ErrorScreen extends StatelessWidget {
  const ErrorScreen({super.key});

  @override
  Widget build(BuildContext context) => const Text('Unavailable');
}
