import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Pathfinder brand mark from assets.
class BrandLogo extends StatelessWidget {
  final double size;
  final bool square;
  final BorderRadius? borderRadius;

  const BrandLogo({
    super.key,
    this.size = 72,
    this.square = true,
    this.borderRadius,
  });

  static const assetFull = 'assets/branding/app_logo.png';
  static const assetSquare = 'assets/branding/app_logo_square.png';

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(size * 0.22);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: PfElevation.soft(Theme.of(context).brightness),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Image.asset(
          square ? assetSquare : assetFull,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: PfColors.forest,
            alignment: Alignment.center,
            child: Icon(Icons.explore, color: PfColors.sandGold, size: size * 0.45),
          ),
        ),
      ),
    );
  }
}

/// Compact wordmark row: logo + Pathfinder title.
class BrandHeader extends StatelessWidget {
  final String subtitle;
  final double logoSize;

  const BrandHeader({
    super.key,
    this.subtitle = 'SADC Lo tools for plots & bush paths',
    this.logoSize = 64,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        BrandLogo(size: logoSize),
        const SizedBox(width: PfSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pathfinder',
                style: tt.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? PfColors.sandGoldSoft
                      : PfColors.forest,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
