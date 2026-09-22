import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../services/waypoint_store.dart';

enum WaypointPickAction { useAsStart, useAsEnd, useAsVia, none }

/// Bottom sheet: list / rename / delete / copy / pick saved waypoints.
class SavedWaypointsSheet extends StatefulWidget {
  final void Function(SavedWaypoint wp, WaypointPickAction action)? onPick;

  const SavedWaypointsSheet({super.key, this.onPick});

  static Future<void> show(
    BuildContext context, {
    void Function(SavedWaypoint wp, WaypointPickAction action)? onPick,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SavedWaypointsSheet(onPick: onPick),
    );
  }

  @override
  State<SavedWaypointsSheet> createState() => _SavedWaypointsSheetState();
}

class _SavedWaypointsSheetState extends State<SavedWaypointsSheet> {
  List<SavedWaypoint> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final all = await WaypointStore.loadAll();
    if (!mounted) return;
    setState(() {
      _items = all;
      _loading = false;
    });
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _copy(SavedWaypoint wp, {bool lo = false}) async {
    final text = lo ? (wp.loCopy ?? wp.wgs84Copy) : wp.wgs84Copy;
    await Clipboard.setData(ClipboardData(text: text));
    _toast(lo && wp.hasLo ? 'Lo coords copied' : 'WGS84 copied');
  }

  Future<void> _rename(SavedWaypoint wp) async {
    final ctrl = TextEditingController(text: wp.label);
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename waypoint'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Label',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (next == null || next.trim().isEmpty) return;
    await WaypointStore.rename(wp.id, next);
    await _reload();
  }

  Future<void> _delete(SavedWaypoint wp) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete waypoint?'),
        content: Text('Remove “${wp.label}”? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await WaypointStore.delete(wp.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height * 0.72;
    return SizedBox(
      height: h,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Saved points',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? _empty()
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) => _tile(_items[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_border,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'No saved points yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'From Walk a line, save your GPS, start, or end with a label. '
              'You can store as many as you need.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(SavedWaypoint wp) {
    final subtitle = StringBuffer(wp.wgs84Copy);
    if (wp.hasLo) subtitle.write('\n${wp.loCopy}');
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.place, size: 20)),
      title: Text(wp.label),
      subtitle: Text(subtitle.toString()),
      isThreeLine: wp.hasLo,
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          switch (v) {
            case 'start':
              widget.onPick?.call(wp, WaypointPickAction.useAsStart);
              if (mounted) Navigator.pop(context);
              break;
            case 'end':
              widget.onPick?.call(wp, WaypointPickAction.useAsEnd);
              if (mounted) Navigator.pop(context);
              break;
            case 'via':
              widget.onPick?.call(wp, WaypointPickAction.useAsVia);
              if (mounted) Navigator.pop(context);
              break;
            case 'copy':
              await _copy(wp);
              break;
            case 'copy_lo':
              await _copy(wp, lo: true);
              break;
            case 'rename':
              await _rename(wp);
              break;
            case 'delete':
              await _delete(wp);
              break;
          }
        },
        itemBuilder: (_) => [
          if (widget.onPick != null) ...[
            const PopupMenuItem(
                value: 'start', child: Text('Use as start')),
            const PopupMenuItem(value: 'end', child: Text('Use as end')),
            const PopupMenuItem(value: 'via', child: Text('Use as via / bend')),
            const PopupMenuDivider(),
          ],
          const PopupMenuItem(value: 'copy', child: Text('Copy WGS84')),
          if (wp.hasLo)
            const PopupMenuItem(value: 'copy_lo', child: Text('Copy Lo')),
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
      onTap: widget.onPick == null
          ? null
          : () {
              // Quick pick: show which endpoint
              showModalBottomSheet<void>(
                context: context,
                builder: (ctx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.flag, color: Colors.green),
                        title: const Text('Use as start'),
                        onTap: () {
                          Navigator.pop(ctx);
                          widget.onPick!(wp, WaypointPickAction.useAsStart);
                          Navigator.pop(context);
                        },
                      ),
                      ListTile(
                        leading: Icon(Icons.flag,
                            color: Theme.of(context).colorScheme.tertiary),
                        title: const Text('Use as end'),
                        onTap: () {
                          Navigator.pop(ctx);
                          widget.onPick!(wp, WaypointPickAction.useAsEnd);
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
    );
  }
}

/// Prompt for a label, then persist a new waypoint.
Future<SavedWaypoint?> promptAndSaveWaypoint(
  BuildContext context, {
  required double lat,
  required double lng,
  String? suggestedLabel,
  double? loY,
  double? loX,
  int? zone,
  String? datum,
}) async {
  final ctrl = TextEditingController(text: suggestedLabel ?? '');
  final label = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Save waypoint'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Label',
          hintText: 'e.g. Corner A, Gate, Camp',
          border: OutlineInputBorder(),
        ),
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (label == null || label.trim().isEmpty) return null;
  final wp = SavedWaypoint(
    id: 'wp_${DateTime.now().millisecondsSinceEpoch}',
    label: label.trim(),
    lat: lat,
    lng: lng,
    createdAt: DateTime.now(),
    loY: loY,
    loX: loX,
    zone: zone,
    datum: datum,
  );
  await WaypointStore.add(wp);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved “${wp.label}”')),
    );
  }
  return wp;
}
