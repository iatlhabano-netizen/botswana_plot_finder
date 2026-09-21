import 'package:flutter/material.dart';

import 'area_calculator/area_calculator_screen.dart';
import 'license/license_screen.dart';
import 'pathfinder/pathfinder_screen.dart';
import 'plot_finder/plot_finder_screen.dart';
import 'theme.dart';
import 'widgets/brand_logo.dart';

class HomeHub extends StatelessWidget {
  final VoidCallback onToggleTheme;
  final bool isDark;

  const HomeHub({
    super.key,
    required this.onToggleTheme,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    PfSpace.lg, PfSpace.md, PfSpace.md, PfSpace.xs),
                child: Row(
                  children: [
                    const Expanded(
                      child: BrandHeader(
                        subtitle:
                            'Find your plot · walk a line · calculate area',
                        logoSize: 68,
                      ),
                    ),
                    IconButton(
                      tooltip: 'License',
                      icon: const Icon(Icons.verified_outlined),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const LicenseScreen()),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Theme',
                      icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
                      onPressed: onToggleTheme,
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  PfSpace.lg, PfSpace.md, PfSpace.lg, PfSpace.xl),
              sliver: SliverList.list(children: [
                Text(
                  'Outdoors',
                  style: tt.titleSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: PfSpace.sm),
                _HubCard(
                  icon: Icons.grid_on_rounded,
                  tint: PfColors.forest,
                  title: 'Find my plot',
                  subtitle:
                      'Enter or scan Land Board corners, then walk to any beacon. '
                      'Tap Locate this corner when you are in the field.',
                  cta: 'Open Find my plot',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const PlotFinderScreen()),
                  ),
                ),
                const SizedBox(height: PfSpace.md),
                _HubCard(
                  icon: Icons.explore_rounded,
                  tint: PfColors.sandGoldDeep,
                  title: 'Walk a line',
                  subtitle:
                      'Pick two points (or find one corner from where you stand). '
                      'Live left/right guidance across open bush.',
                  cta: 'Open Walk a line',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const PathfinderScreen()),
                  ),
                ),
                const SizedBox(height: PfSpace.md),
                _HubCard(
                  icon: Icons.square_foot_rounded,
                  tint: PfColors.sky,
                  title: 'Calculate area',
                  subtitle:
                      'Three or more corners → hectares, m², and fence lengths. '
                      'Compare calculated area to the certificate.',
                  cta: 'Open Calculate area',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AreaCalculatorScreen()),
                  ),
                ),
                const SizedBox(height: PfSpace.section),
                _TipsCard(),
                const SizedBox(height: PfSpace.lg),
                _AboutStrip(),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _HubCard extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
  final String cta;
  final VoidCallback onTap;

  const _HubCard({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.cta,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: PfRadius.lgAll,
        child: Ink(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: PfRadius.lgAll,
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.9)),
            boxShadow: PfElevation.card(brightness),
          ),
          child: Padding(
            padding: const EdgeInsets.all(PfSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: 0.12),
                        borderRadius: PfRadius.mdAll,
                      ),
                      child: Icon(icon, color: tint, size: 28),
                    ),
                    const SizedBox(width: PfSpace.sm),
                    Expanded(
                      child: Text(
                        title,
                        style: tt.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: cs.onSurfaceVariant),
                  ],
                ),
                const SizedBox(height: PfSpace.sm),
                Text(
                  subtitle,
                  style: tt.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: PfSpace.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: tint,
                      foregroundColor: tint == PfColors.sandGoldDeep ||
                              tint == PfColors.sandGold
                          ? PfColors.ink
                          : Colors.white,
                    ),
                    onPressed: onTap,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                    label: Text(cta),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TipsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(PfSpace.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: PfRadius.lgAll,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tips_and_updates_outlined,
                  size: 20, color: PfColors.sandGoldDeep),
              const SizedBox(width: PfSpace.xs),
              Text('Tips for the bush', style: tt.titleMedium),
            ],
          ),
          const SizedBox(height: PfSpace.sm),
          Text(
            '• Before you leave signal: open your plot map and tap Download map.\n'
            '• No Google Maps key? The offline basemap still works — tap the banner for details.\n'
            '• To find a beacon: Find my plot → Locate this corner (uses your GPS).\n'
            '• Advanced: Lo zone and datum live under each tool’s Country / zone section.',
            style: tt.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        const BrandLogo(size: 40),
        const SizedBox(width: PfSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pathfinder',
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text(
                'Field tools for SADC plot awards and bush navigation',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
