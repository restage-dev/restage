import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/declined.restage.g.dart';

@Screen()
final class DeclinedScreen extends StatelessWidget {
  const DeclinedScreen({super.key});

  static const finish = SurfaceEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const Text('Declined');
}
