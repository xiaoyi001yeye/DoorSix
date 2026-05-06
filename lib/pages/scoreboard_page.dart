import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

class ScoreboardPage extends StatelessWidget {
  const ScoreboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('总战绩'),
        backgroundColor: AppTheme.background,
      ),
      body: const Center(
        child: Text(
          '连续战绩会在多局模式中展示',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      ),
    );
  }
}
