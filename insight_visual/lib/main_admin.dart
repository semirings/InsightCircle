import 'package:flutter/material.dart';

import 'pages/dashboard_page.dart';
import 'theme.dart';

void main() {
  runApp(const InsightVisualApp());
}

class InsightVisualApp extends StatelessWidget {
  const InsightVisualApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InsightCircle',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const DashboardPage(),
    );
  }
}
