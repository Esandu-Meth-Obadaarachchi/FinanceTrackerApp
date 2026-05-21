import 'package:flutter/material.dart';

import '../data/categories.dart';
import '../theme/app_text.dart';
import '../theme/palette.dart';

/// Maps an account type to a Material icon.
IconData accountIcon(String type) {
  switch (type) {
    case 'cash':
      return Icons.payments_outlined;
    case 'fd':
      return Icons.savings_outlined;
    default:
      return Icons.account_balance_outlined;
  }
}

/// A rounded card surface matching the standalone design.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    required this.colors,
    this.padding = const EdgeInsets.fromLTRB(18, 16, 18, 16),
    this.radius = 20,
  });

  final Widget child;
  final Palette colors;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}

/// A small coloured dot keyed to a category.
class CategoryDot extends StatelessWidget {
  const CategoryDot({super.key, required this.category, this.size = 8});

  final String category;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: categoryColor(category),
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Rounded icon box for an account.
class AccountIconBox extends StatelessWidget {
  const AccountIconBox({
    super.key,
    required this.type,
    required this.color,
    this.size = 32,
  });

  final String type;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(accountIcon(type), color: color, size: size * 0.5),
    );
  }
}

/// A pill-shaped status badge (Received / Pending / Repaid…).
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final map = {
      'received': (const Color(0xFF3DEBA8), 'Received'),
      'pending': (const Color(0xFFFFB547), 'Pending'),
      'repaid': (const Color(0xFF60A5FA), 'Repaid'),
      'partial': (const Color(0xFFA78BFA), 'Partial'),
    };
    final entry = map[status] ?? (const Color(0xFF94A3B8), status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: entry.$1.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        entry.$2.toUpperCase(),
        style: sans(
          size: 10,
          weight: FontWeight.w700,
          color: entry.$1,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// A generic colour-tinted tag pill.
class TagPill extends StatelessWidget {
  const TagPill({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: sans(size: 9.5, weight: FontWeight.w700, color: color),
      ),
    );
  }
}

/// Centered empty-state placeholder.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.colors,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Palette colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 40, color: colors.muted),
          const SizedBox(height: 12),
          Text(title,
              style: sans(size: 15, weight: FontWeight.w600, color: colors.muted)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: sans(size: 13, color: colors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// A thin divider in the theme's border colour.
class ThinDivider extends StatelessWidget {
  const ThinDivider({super.key, required this.colors, this.indent = 0});
  final Palette colors;
  final double indent;

  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: EdgeInsets.symmetric(horizontal: indent),
        color: colors.border,
      );
}
