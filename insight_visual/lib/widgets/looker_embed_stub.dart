import 'package:flutter/material.dart';

class LookerEmbed extends StatelessWidget {
  final String reportUrl;

  const LookerEmbed({super.key, required this.reportUrl});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Looker embed is only supported on web.'),
    );
  }
}
