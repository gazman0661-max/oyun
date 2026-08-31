import 'package:flutter/material.dart';

import '../services/localization.dart';
import '../theme/app_colors.dart';

Future<void> showActionInfoDialog(
  BuildContext context, {
  required String icon,
  required String title,
  required String description,
  required List<String> lines,
}) {
  return showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.surfaceBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 34)),
            const SizedBox(height: 10),
            Text(title,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 16)),
            const SizedBox(height: 6),
            Text(description,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12, height: 1.4),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ...lines.map((l) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(l,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 12)),
                )),
            const SizedBox(height: 14),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(t('profile_close'),
                  style: const TextStyle(color: AppColors.textSecondary)),
            ),
          ],
        ),
      ),
    ),
  );
}
