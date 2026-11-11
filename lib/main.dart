import 'package:flutter/material.dart';

void main() => runApp(const GorkApp());

/// The gork app — a free, open-source personal AI assistant.
class GorkApp extends StatelessWidget {
  const GorkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'gork',
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('gork')),
      body: const Center(
        child: Text('gork: your personal AI assistant'),
      ),
    );
  }
}
