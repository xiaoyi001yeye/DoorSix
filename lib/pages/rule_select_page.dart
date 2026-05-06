import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/rule_set.dart';
import '../utils/app_theme.dart';

class RuleSelectPage extends StatelessWidget {
  const RuleSelectPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择规则版本'),
        backgroundColor: AppTheme.background,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemBuilder: (context, index) {
          final rule = rulePresets[index];
          return _RuleCard(
            ruleSet: rule,
            onTap: () => context.push('/table', extra: rule),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemCount: rulePresets.length,
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({
    required this.ruleSet,
    required this.onTap,
  });

  final RuleSet ruleSet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ruleSet.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: 10),
              Text(ruleSet.summary),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _RuleChip(label: '${ruleSet.deckCount} 副牌'),
                  _RuleChip(label: ruleSet.enableTribute ? '进贡开' : '进贡关'),
                  _RuleChip(label: ruleSet.enableFollowLead ? '接风开' : '接风关'),
                  _RuleChip(label: ruleSet.enableWildCards ? '混牌开' : '混牌关'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RuleChip extends StatelessWidget {
  const _RuleChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      side: const BorderSide(color: Color(0x334CC9F0)),
      backgroundColor: AppTheme.panelLight,
      labelStyle: const TextStyle(
        color: AppTheme.textPrimary,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
