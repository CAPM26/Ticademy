import 'package:flutter/material.dart';

class BadgeInfo {
  const BadgeInfo({
    required this.name,
    required this.earnedAtLabel,
  });

  final String name;
  final String earnedAtLabel;
}

class BadgePill extends StatelessWidget {
  const BadgePill({super.key, required this.info});

  final BadgeInfo info;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE0E7FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF6366F1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            info.name,
            style: const TextStyle(
              color: Color(0xFF1E3A8A),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            info.earnedAtLabel,
            style: const TextStyle(
              color: Color(0xFF4C51BF),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
