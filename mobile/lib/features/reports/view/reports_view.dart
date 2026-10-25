import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/bloc/load_state.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/status_style.dart';
import '../../../core/widgets/product_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../data/reports_repository.dart';

/// Admin reports: scan counts per status, product/user totals, recent Flagged/Suspect scans.
class ReportsView extends StatefulWidget {
  const ReportsView({super.key});

  @override
  State<ReportsView> createState() => _ReportsViewState();
}

class _ReportsViewState extends State<ReportsView> {
  late final LoadCubit<ReportSummary> _summary = LoadCubit<ReportSummary>(context.read<ReportsRepository>().summary)..load();

  @override
  void dispose() {
    _summary.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LoadCubit<ReportSummary>, LoadState<ReportSummary>>(
      bloc: _summary,
      builder: (context, state) {
        final s = state.data;
        if (s == null) {
          return state.status == LoadStatus.failure ? ErrorView(message: state.error!, onRetry: _summary.load) : const LoadingView();
        }
        final theme = Theme.of(context);
        return RefreshIndicator(
          onRefresh: _summary.load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Text('Scans by result', style: theme.textTheme.titleMedium),
              Text('${s.scanTotal} verifications in total. Tap a tile to see those scans.', style: theme.textTheme.bodySmall),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.7,
                children: [
                  for (final status in VerificationStatus.values)
                    _StatusTile(
                      status: status,
                      count: s.scansByStatus[status] ?? 0,
                      onTap: () => _openScans(context, title: '${status.label} scans', status: status),
                    ),
                ],
              ),
              if (s.ml != null) ...[
                const SizedBox(height: 20),
                Text('Anomaly detection (ML)', style: theme.textTheme.titleMedium),
                Text('Machine-learning check that runs on every verification', style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                _MlCard(ml: s.ml!, onOpenFlagged: () => _openScans(context, title: 'Flagged by ML', flag: 'ML_ANOMALY')),
              ],
              const SizedBox(height: 20),
              Text('Recent alerts', style: theme.textTheme.titleMedium),
              Text('Latest Flagged and Suspect scans', style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              if (s.recentAlerts.isEmpty)
                const Card(child: ListTile(leading: Icon(Icons.check_circle_outline), title: Text('No alerts — all recent scans were clean.')))
              else
                Card(child: Column(children: [for (final r in s.recentAlerts) _ScanTile(scan: r)])),
              const SizedBox(height: 20),
              Text('Products by stage', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Column(children: [
                  for (final stage in [ProductStage.manufactured, ProductStage.atSupplier, ProductStage.atRetailer, ProductStage.sold])
                    ListTile(
                      dense: true,
                      leading: Icon(stage.icon, color: stage.color),
                      title: Text(stage.label),
                      trailing: Text('${s.productsByStage[stage.wire] ?? 0}', style: theme.textTheme.titleMedium),
                    ),
                  ListTile(dense: true, title: const Text('Total products'), trailing: Text('${s.productTotal}', style: theme.textTheme.titleMedium)),
                ]),
              ),
              const SizedBox(height: 20),
              Text('Active accounts by role', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Column(children: [
                  for (final role in UserRole.business)
                    ListTile(dense: true, title: Text(role.label), trailing: Text('${s.usersByRole[role.name] ?? 0}', style: theme.textTheme.titleMedium)),
                ]),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  void _openScans(BuildContext context, {required String title, VerificationStatus? status, String? flag}) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _ScanListScreen(title: title, status: status, flag: flag, repo: context.read<ReportsRepository>()),
    ));
  }
}

/// Stat tile: number in text ink; the status carries colour + icon + label (never colour alone).
class _StatusTile extends StatelessWidget {
  const _StatusTile({required this.status, required this.count, required this.onTap});
  final VerificationStatus status;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(border: Border(left: BorderSide(color: status.color, width: 4))),
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              Icon(status.icon, color: status.color, size: 20),
              const SizedBox(width: 6),
              Text(status.label, style: theme.textTheme.labelLarge),
            ]),
            Text('$count', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

/// ML service status, how many scans it scored/flagged, and its (synthetic) accuracy.
class _MlCard extends StatelessWidget {
  const _MlCard({required this.ml, required this.onOpenFlagged});
  final MlSummary ml;
  final VoidCallback onOpenFlagged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (IconData icon, Color color, String label) = !ml.configured
        ? (Icons.block, const Color(0xFF616161), 'Disabled (ML_URL not set)')
        : ml.online
            ? (Icons.check_circle, const Color(0xFF2E7D32), 'Online')
            : (Icons.cloud_off, const Color(0xFF616161), 'Offline — verification continues without it');
    String pct(double? v) => v == null ? '—' : '${(v * 100).toStringAsFixed(1)}%';
    final model = ml.modelVersion == null
        ? 'IsolationForest anomaly model'
        : 'Model ${ml.modelVersion}${ml.threshold == null ? '' : ' · threshold ${ml.threshold!.toStringAsFixed(3)}'}';
    return Card(
      child: Column(children: [
        ListTile(
          leading: Icon(icon, color: color, semanticLabel: label),
          title: Text('Service: $label'),
          subtitle: Text(model),
        ),
        const Divider(height: 1),
        ListTile(
          dense: true,
          leading: const Icon(Icons.analytics_outlined),
          title: const Text('Verifications scored'),
          trailing: Text('${ml.scansScored}', style: theme.textTheme.titleMedium),
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.warning_amber_rounded, color: Color(0xFFB26A00)),
          title: const Text('Flagged as unusual by ML'),
          subtitle: const Text('Tap to see these scans'),
          trailing: Text('${ml.flaggedByMl}', style: theme.textTheme.titleMedium),
          onTap: onOpenFlagged,
        ),
        if (ml.overallRecall != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Text(
              'Test accuracy on synthetic data: catches ${pct(ml.overallRecall)} of injected anomalies, '
              '${pct(ml.falsePositiveRate)} false alarms. ML can raise a result to Flagged, never to Suspect.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
      ]),
    );
  }
}

class _ScanTile extends StatelessWidget {
  const _ScanTile({required this.scan});
  final ScanRecord scan;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(scan.status.icon, color: scan.status.color, semanticLabel: scan.status.label),
      title: Text(scan.productName ?? scan.productId ?? 'Unreadable QR'),
      subtitle: Text([
        if (scan.productId != null) scan.productId!,
        formatDateTime(scan.at),
        if (scan.flags.isNotEmpty) scan.flags.join(', '),
        if (scan.mlScore != null) 'ML ${scan.mlScore!.toStringAsFixed(2)}${scan.mlAnomaly == true ? ' (unusual)' : ''}',
      ].join(' · ')),
      trailing: StatusBadge(status: scan.status),
      onTap: scan.productId == null ? null : () => context.push('/products/${Uri.encodeComponent(scan.productId!)}'),
    );
  }
}

class _ScanListScreen extends StatelessWidget {
  const _ScanListScreen({required this.title, required this.repo, this.status, this.flag});
  final String title;
  final VerificationStatus? status;
  final String? flag;
  final ReportsRepository repo;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LoadCubit<List<ScanRecord>>(() => repo.scans(status: status, flag: flag))..load(),
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: BlocBuilder<LoadCubit<List<ScanRecord>>, LoadState<List<ScanRecord>>>(
          builder: (context, state) {
            final scans = state.data;
            if (scans == null) {
              return state.status == LoadStatus.failure
                  ? ErrorView(message: state.error!, onRetry: context.read<LoadCubit<List<ScanRecord>>>().load)
                  : const LoadingView();
            }
            if (scans.isEmpty) return EmptyView(icon: status?.icon ?? Icons.insights_outlined, title: 'No ${title.toLowerCase()} yet');
            return ListView.separated(
              itemCount: scans.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => _ScanTile(scan: scans[i]),
            );
          },
        ),
      ),
    );
  }
}
