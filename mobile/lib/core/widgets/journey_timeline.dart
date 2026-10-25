import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/status_style.dart';
import 'product_widgets.dart';

IconData _eventIcon(String type) => switch (type) {
      'Registered' => Icons.app_registration,
      'TransferInitiated' => Icons.outbox_outlined,
      'Received' => Icons.move_to_inbox_outlined,
      'TransferCancelled' => Icons.undo,
      'Sold' => Icons.shopping_bag_outlined,
      _ => Icons.circle_outlined,
    };

String _partyLine(Party? p) {
  if (p == null) return '—';
  return p.role != null ? '${p.name} · ${p.role!.label}' : p.name;
}

/// Vertical journey timeline: event, stage, party name + role, timestamp, tx hash.
class JourneyTimeline extends StatelessWidget {
  const JourneyTimeline({super.key, required this.events});
  final List<JourneyEvent> events;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('No custody events recorded.', style: theme.textTheme.bodyMedium),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < events.length; i++)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 40,
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: events[i].stageAfter.color.withValues(alpha: 0.12), shape: BoxShape.circle),
                    child: Icon(_eventIcon(events[i].eventType), size: 18, color: events[i].stageAfter.color),
                  ),
                  if (i < events.length - 1)
                    Expanded(child: Container(width: 2, color: theme.colorScheme.outlineVariant)),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: _EventBody(event: events[i]),
                ),
              ),
            ]),
          ),
      ],
    );
  }
}

class _EventBody extends StatelessWidget {
  const _EventBody({required this.event});
  final JourneyEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final e = event;
    final String parties = switch (e.eventType) {
      'Registered' => 'by ${_partyLine(e.from)}',
      'Sold' => 'by ${_partyLine(e.from)}',
      'Received' => '${_partyLine(e.to)} received from ${e.from?.name ?? '—'}',
      'TransferCancelled' => '${_partyLine(e.from)} cancelled transfer to ${e.to?.name ?? '—'}',
      _ => '${_partyLine(e.from)} → ${_partyLine(e.to)}',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(e.label, style: theme.textTheme.titleSmall)),
        Text(e.stageAfter.label, style: theme.textTheme.labelSmall?.copyWith(color: e.stageAfter.color)),
      ]),
      const SizedBox(height: 2),
      Text(parties, style: theme.textTheme.bodyMedium),
      const SizedBox(height: 2),
      Text(formatDateTime(e.timestamp), style: muted),
      if (e.txHash != null) Text('tx ${shortHash(e.txHash)} · block ${e.blockNumber ?? '—'}', style: muted?.copyWith(fontFamily: 'monospace')),
    ]);
  }
}
