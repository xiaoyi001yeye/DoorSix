import 'package:flutter/material.dart';

import '../models/rule_set.dart';
import '../utils/app_theme.dart';

class RuleBadge extends StatelessWidget {
  const RuleBadge({
    required this.ruleSet,
    required this.onTap,
    super.key,
  });

  final RuleSet ruleSet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppTheme.panelLight,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x334CC9F0)),
        ),
        child: Text(
          ruleSet.name,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
