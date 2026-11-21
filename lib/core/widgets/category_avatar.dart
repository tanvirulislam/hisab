import 'package:flutter/material.dart';

import '../constants/app_icons.dart';

/// Round colored icon used for categories and accounts.
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({
    super.key,
    required this.iconKey,
    required this.color,
    this.size = 40,
  });

  final String iconKey;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.28 : 0.14),
        shape: BoxShape.circle,
      ),
      child: Icon(
        AppIcons.of(iconKey),
        size: size * 0.55,
        color: dark ? Color.lerp(color, Colors.white, 0.45) : color,
      ),
    );
  }
}
