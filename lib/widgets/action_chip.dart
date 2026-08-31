import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class GameActionChip extends StatelessWidget {
  final String icon;
  final String label;
  final int badgeCount;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onInfoTap;

  const GameActionChip({
    super.key,
    required this.icon,
    required this.label,
    required this.badgeCount,
    required this.onTap,
    required this.onInfoTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Opacity(
        opacity: enabled ? 1.0 : 0.5,
        child: Material(
          color: AppColors.tubeGlass,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.tubeGlassBorder),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(icon, style: const TextStyle(fontSize: 20)),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    top: -6,
                    right: -2,
                    child: GestureDetector(
                      onTap: onInfoTap,
                      child: Container(
                        width: 18,
                        height: 18,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: AppColors.surface,
                          shape: BoxShape.circle,
                          border: Border.fromBorderSide(
                            BorderSide(color: AppColors.tubeGlassBorder),
                          ),
                        ),
                        child: const Text('i',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -4,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: badgeCount > 0
                              ? AppColors.success
                              : AppColors.surfaceBorder,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '×$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
