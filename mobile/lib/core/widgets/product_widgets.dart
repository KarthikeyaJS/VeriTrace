import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../theme/status_style.dart';

final _dateTime = DateFormat('d MMM yyyy, HH:mm:ss');
String formatDateTime(DateTime? d) => d == null ? '—' : _dateTime.format(d);

String shortHash(String? h, {int head = 10, int tail = 6}) {
  if (h == null || h.isEmpty) return '—';
  return h.length <= head + tail + 1 ? h : '${h.substring(0, head)}…${h.substring(h.length - tail)}';
}

class StageChip extends StatelessWidget {
  const StageChip({super.key, required this.stage, this.pending = false});
  final ProductStage stage;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final color = stage.color;
    return Wrap(spacing: 6, runSpacing: 4, children: [
      _Pill(icon: stage.icon, label: stage.label, color: color),
      if (pending) const _Pill(icon: Icons.schedule, label: 'Transfer pending', color: Color(0xFFB26A00)),
    ]);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status, this.large = false});
  final VerificationStatus status;
  final bool large;

  @override
  Widget build(BuildContext context) {
    if (!large) {
      return _Pill(icon: status.icon, label: status.label, color: status.color);
    }
    final theme = Theme.of(context);
    return Semantics(
      label: 'Verification result: ${status.label}. ${status.description}',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: status.background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: status.color.withValues(alpha: 0.5), width: 1.5),
        ),
        child: Column(children: [
          Icon(status.icon, size: 72, color: status.color),
          const SizedBox(height: 8),
          Text(status.label.toUpperCase(),
              style: theme.textTheme.headlineMedium?.copyWith(color: status.color, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
          const SizedBox(height: 4),
          Text(status.description, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
        ]),
      ),
    );
  }
}

/// Label/value row used in detail cards.
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.copyable = false, this.mono = false});
  final String label;
  final String? value;
  final bool copyable;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = (value == null || value!.isEmpty) ? '—' : value!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 120,
          child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        Expanded(
          child: SelectableText(v, style: mono ? const TextStyle(fontFamily: 'monospace', fontSize: 12) : theme.textTheme.bodyMedium),
        ),
        if (copyable && value != null)
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: value!));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied')));
            },
            child: const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.copy, size: 16)),
          ),
      ]),
    );
  }
}

/// Card listing a product's descriptive fields.
class ProductInfoCard extends StatelessWidget {
  const ProductInfoCard({super.key, required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.displayName, style: theme.textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(p.productId, style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
          const SizedBox(height: 10),
          StageChip(stage: p.stage, pending: p.hasPendingTransfer),
          if (p.metadataMissing)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('Product details are missing from the database.', style: TextStyle(color: theme.colorScheme.error)),
            ),
          const Divider(height: 24),
          InfoRow('Brand', p.brand),
          InfoRow('Category', p.category),
          InfoRow('Manufacturer', p.manufacturerName ?? p.manufacturer?.name),
          InfoRow('Batch', p.batchNumber),
          if (p.serialNumber != null) InfoRow('Serial no.', p.serialNumber),
          InfoRow('Manufactured', p.manufactureDate),
          if (p.expiryDate != null) InfoRow('Expires', '${p.expiryDate}${p.isExpired ? '  (expired)' : ''}'),
          if (p.mrp != null) InfoRow('MRP', NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(p.mrp)),
          InfoRow('Origin', p.countryOfOrigin),
          if (p.currentHolder != null)
            InfoRow('Current holder', '${p.currentHolder!.name}${p.currentHolder!.role != null ? ' (${p.currentHolder!.role!.label})' : ''}'),
          if (p.pendingRecipient != null) InfoRow('Sent to', '${p.pendingRecipient!.name} — awaiting confirmation'),
          if (p.description != null) ...[const SizedBox(height: 8), Text(p.description!, style: theme.textTheme.bodyMedium)],
        ]),
      ),
    );
  }
}

/// One-line summary of the ML anomaly check for the technical details.
String _mlLine(Object? ml) {
  if (ml is! Map) return 'Not run: ML service offline (the result is based on the other checks)';
  final score = (ml['anomalyScore'] as num?)?.toStringAsFixed(3) ?? '—';
  final threshold = (ml['threshold'] as num?)?.toStringAsFixed(3);
  final verdict = ml['isAnomaly'] == true ? 'UNUSUAL' : 'normal';
  final model = ml['modelVersion'] == null ? '' : '\nmodel ${ml['modelVersion']}';
  return 'score $score${threshold == null ? '' : ' (threshold $threshold)'}: $verdict$model';
}

/// Collapsed "Technical details" expander (tx hashes, block numbers, contract address, product hash).
class TechnicalDetails extends StatelessWidget {
  const TechnicalDetails({super.key, required this.technical, this.journey = const []});
  final Map<String, dynamic> technical;
  final List<JourneyEvent> journey;

  @override
  Widget build(BuildContext context) {
    String? s(String k) => technical[k]?.toString();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: const Icon(Icons.code),
        title: const Text('Technical details'),
        subtitle: const Text('Blockchain references'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          InfoRow('Network', '${s('network') ?? '—'} (chain ID ${s('chainId') ?? '—'})'),
          InfoRow('Contract', s('contractAddress'), copyable: true, mono: true),
          InfoRow('Product hash', s('productHash'), copyable: true, mono: true),
          if (technical['qrHash'] != null) InfoRow('QR hash', s('qrHash'), copyable: true, mono: true),
          if (technical['recomputedHash'] != null) InfoRow('Recomputed hash', s('recomputedHash'), copyable: true, mono: true),
          InfoRow('Register tx', s('registerTxHash'), copyable: true, mono: true),
          InfoRow('Register block', s('registerBlock')),
          if (technical['scanCount'] != null) InfoRow('Scans', '${s('scanCount')} from ${s('distinctDevices')} device(s)'),
          if (technical.containsKey('ml')) InfoRow('ML anomaly check', _mlLine(technical['ml'])),
          if (journey.isNotEmpty) ...[
            const Divider(height: 24),
            for (final e in journey)
              InfoRow('${e.label}\nblock ${e.blockNumber ?? '—'}', e.txHash, copyable: true, mono: true),
          ],
        ],
      ),
    );
  }
}
