import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/accepted.restage.g.dart';

@Screen()
final class AcceptedScreen extends StatelessWidget {
  const AcceptedScreen({super.key});

  static const finish = SurfaceEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const Text('Accepted');
}
