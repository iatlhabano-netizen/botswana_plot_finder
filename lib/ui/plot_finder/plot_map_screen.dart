import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/lo_converter.dart';
import '../../core/path_guidance.dart';
import '../../services/area_audit.dart';
import '../../services/external_maps.dart';
import '../../services/plot_calculator.dart';
import '../../services/gps_service.dart';
import '../../services/plot_exporter.dart';
import '../pathfinder/guidance_screen.dart';
import '../pathfinder/pathfinder_screen.dart';
import '../theme.dart';
import '../widgets/hybrid_map.dart';

class PlotMapScreen extends StatefulWidget {
  final List<ll.LatLng> points;
  final List<Map<String, double>> loCorners;
  final int zone;
  final String datumKey;
  final double? declaredHa;
  final String? projectName;
  final int? focusIndex;

  const PlotMapScreen({
    super.key,
    required this.points,
    required this.loCorners,
    required this.zone,
    required this.datumKey,
    this.declaredHa,
    this.projectName,
    this.focusIndex,
  });

  @override
  State<PlotMapScreen> createState() => _PlotMapScreenState();
}

class _PlotMapScreenState extends State<PlotMapScreen> {
  int? _selected;
  int? _routeStart;
  int? _routeEnd;

  @override
  void initState() {
    super.initState();
    _selected = widget.focusIndex;
  }

  ll.LatLng get _center {
    if (_selected != null && _selected! < widget.points.length) {
      return widget.points[_selected!];
    }
    return widget.points.isNotEmpty
        ? widget.points.first
        : const ll.LatLng(-23.58, 25.72);
  }

  void _cornerSheet(int idx) {
    final pt = widget.points[idx];
    final lo = LoConverter.fromWgs84(pt,
        zone: widget.zone, datumKey: widget.datumKey);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Corner ${idx + 1}',
                style: Theme.of(context).textTheme.titleLarge),
            Text('Lat ${pt.latitude.toStringAsFixed(7)}'),
            Text('Lon ${pt.longitude.toStringAsFixed(7)}'),
            Text(
                'Lo Y ${lo.westing.toStringAsFixed(3)}  X ${lo.southing.toStringAsFixed(3)}'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                // Use current GPS as start (same as Plot Finder); never start==end.
                final nav = Navigator.of(this.context);
                final gps = await GpsService.currentLatLng(this.context);
                if (!mounted) return;
                final start = gps ?? pt;
                nav.push(
                  MaterialPageRoute(
                    builder: (_) => GuidanceScreen(
                      start: start,
                      end: pt,
                      startLabel: 'You',
                      endLabel: 'C${idx + 1}',
                      locateMode: true,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.my_location),
              label: const Text('Locate this corner'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                ExternalMaps.openNavigation(pt);
              },
              icon: const Icon(Icons.navigation),
              label: const Text('Open in Google Maps / nav'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PathfinderScreen(
                      initialEnd: pt,
                      endLabel: 'C${idx + 1}',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.explore),
              label: const Text('Pathfinder setup…'),
            ),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(
                  text:
                      '${pt.latitude.toStringAsFixed(7)}, ${pt.longitude.toStringAsFixed(7)}',
                ));
                Navigator.pop(ctx);
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy WGS84'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = PlotCalculator.calculateFromLo(widget.loCorners);
    final markers = widget.points.asMap().entries.map((e) {
      final selected = _selected == e.key;
      return MapMarkerData(
        point: e.value,
        label: 'C${e.key + 1}',
        color: selected ? PathfinderTheme.accent : Colors.red,
        onTap: () {
          setState(() => _selected = e.key);
          _cornerSheet(e.key);
        },
      );
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.projectName ?? 'Plot map'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.share),
            onSelected: (c) {
              if (c == 'kml') {
                PlotExporter.shareFile(
                  content: PlotExporter.generateKml(widget.points),
                  fileName: 'plot_boundary.kml',
                  mimeType: 'application/vnd.google-earth.kml+xml',
                );
              } else if (c == 'gpx') {
                PlotExporter.shareFile(
                  content: PlotExporter.generateGpx(widget.points),
                  fileName: 'plot_boundary.gpx',
                  mimeType: 'application/gpx+xml',
                );
              } else if (c == 'csv') {
                PlotExporter.shareFile(
                  content: PlotExporter.generateCsv(
                    westings:
                        widget.loCorners.map((c) => c['Y']!).toList(),
                    southings:
                        widget.loCorners.map((c) => c['X']!).toList(),
                    latitudes:
                        widget.points.map((p) => p.latitude).toList(),
                    longitudes:
                        widget.points.map((p) => p.longitude).toList(),
                    areaHectares: summary.areaHectares,
                  ),
                  fileName: 'plot_data.csv',
                  mimeType: 'text/csv',
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'kml', child: Text('Export KML')),
              PopupMenuItem(value: 'gpx', child: Text('Export GPX')),
              PopupMenuItem(value: 'csv', child: Text('Export CSV')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: HybridMap(
              center: _center,
              polygon: widget.points,
              markers: markers,
            ),
          ),
          Material(
            elevation: 8,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${summary.areaHectares.toStringAsFixed(2)} Ha · ${summary.perimeterMeters.toStringAsFixed(0)} m perimeter',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    if (widget.declaredHa != null) ...[
                      const SizedBox(height: 6),
                      Builder(builder: (_) {
                        final audit = AreaAuditor.auditArea(
                          computedHectares: summary.areaHectares,
                          statedHectares: widget.declaredHa!,
                        );
                        return Text(
                          audit.message,
                          style: TextStyle(
                            fontSize: 12,
                            color: audit.isMismatch
                                ? Colors.orange.shade900
                                : Colors.green.shade800,
                          ),
                        );
                      }),
                    ],
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 44,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: widget.points.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => ChoiceChip(
                          label: Text('C${i + 1}'),
                          selected: _selected == i,
                          onSelected: (_) {
                            setState(() => _selected = i);
                            _cornerSheet(i);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _routeStart,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'From',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            items: List.generate(
                              widget.points.length,
                              (i) => DropdownMenuItem(
                                  value: i, child: Text('C${i + 1}')),
                            ),
                            onChanged: (v) => setState(() => _routeStart = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _routeEnd,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'To',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            items: List.generate(
                              widget.points.length,
                              (i) => DropdownMenuItem(
                                  value: i, child: Text('C${i + 1}')),
                            ),
                            onChanged: (v) => setState(() => _routeEnd = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: PathfinderTheme.seed,
                            minimumSize: const Size(56, 48),
                          ),
                          onPressed: () {
                            if (_routeStart == null ||
                                _routeEnd == null ||
                                _routeStart == _routeEnd) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('Pick two different corners')),
                              );
                              return;
                            }
                            final dist = PathGuidance.distanceM(
                              widget.points[_routeStart!],
                              widget.points[_routeEnd!],
                            );
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => GuidanceScreen(
                                  start: widget.points[_routeStart!],
                                  end: widget.points[_routeEnd!],
                                  startLabel: 'C${_routeStart! + 1}',
                                  endLabel: 'C${_routeEnd! + 1}',
                                  pathLengthM: dist,
                                ),
                              ),
                            );
                          },
                          child: const Icon(Icons.explore),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
