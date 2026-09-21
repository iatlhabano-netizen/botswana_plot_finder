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
                            'SADC Lo → GPS · plot awards · bush navigation',
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
                  'Field tools',
                  style: tt.titleSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: PfSpace.sm),
                _HubCard(
                  icon: Icons.grid_on_rounded,
                  tint: PfColors.forest,
                  title: 'Plot Finder',
                  subtitle:
                      'Convert Lo corners to WGS84, scan certificates, and map the plot. Tap any corner → Locate this corner.',
                  cta: 'Open Plot Finder',
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
                  title: 'Pathfinder',
                  subtitle:
                      'Two endpoints (GPS, WGS84, or Lo). Straight geodesic cutline with live left/right guidance — or locate one pole from GPS.',
                  cta: 'Open Pathfinder',
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
                  title: 'Area Calculator',
                  subtitle:
                      'Enter Lo corners (3+) for plot area in hectares and m², plus fence-line lengths. Includes certificate scan.',
                  cta: 'Open Area Calculator',
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
            '• First visit: open a map online so OSM tiles cache for remote areas.\n'
            '• Google Maps needs MAPS_API_KEY in local.properties (see README).\n'
            '• Without a key, use the coordinate list + Open in Maps / Locate guidance.\n'
            '• To find your plot: open Plot Finder → tap a corner → Locate this corner.',
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
                'Survey-grade Lo tools for SADC field work',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
