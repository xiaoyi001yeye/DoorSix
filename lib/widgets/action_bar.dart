import 'package:flutter/material.dart';

class GameActionBar extends StatelessWidget {
  const GameActionBar({
    required this.isUserTurn,
    required this.canPlay,
    required this.canPass,
    required this.onHint,
    required this.onPlay,
    required this.onPass,
    required this.onSort,
    super.key,
  });

  final bool isUserTurn;
  final bool canPlay;
  final bool canPass;
  final VoidCallback onHint;
  final VoidCallback onPlay;
  final VoidCallback onPass;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: isUserTurn ? onHint : null,
              icon: const Icon(Icons.lightbulb_outline_rounded),
              label: const Text('提示'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onSort,
              icon: const Icon(Icons.sort_rounded),
              label: const Text('整理'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              onPressed: canPlay ? onPlay : null,
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('出牌'),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: OutlinedButton(
              onPressed: canPass ? onPass : null,
              child: const Text('过'),
            ),
          ),
        ],
      ),
    );
  }
}
