import 'package:flutter/material.dart';

void main() {
  runApp(const InsightApp());
}

class InsightApp extends StatelessWidget {
  const InsightApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'InsightCircle',
      debugShowCheckedModeBanner: false,
      home: HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Ave Mundus!!',
          style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
