import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/status_style.dart';
import '../../../core/widgets/journey_timeline.dart';
import '../../../core/widgets/product_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../bloc/verify_bloc.dart';
import '../data/verification_result.dart';
import '../data/verify_repository.dart';

/// Verification result: status badge, reasons, product, journey, technical details.
class VerifyScreen extends StatelessWidget {
  const VerifyScreen({super.key, this.payload, this.productId});
  final String? payload;
  final String? productId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (ctx) => VerifyBloc(repository: ctx.read<VerifyRepository>())..add(VerifyRequested(payload: payload, productId: productId)),
      child: Scaffold(
        appBar: AppBar(title: const Text('Verification result')),
        body: BlocBuilder<VerifyBloc, VerifyState>(
          builder: (context, state) => switch (state) {
            VerifyInitial() || VerifyLoading() => const LoadingView(message: 'Checking the blockchain…'),
            VerifyFailure(:final message) => ErrorView(message: message, onRetry: () => context.read<VerifyBloc>().add(const VerifyRetried())),
            VerifySuccess(:final result) => _ResultBody(result: result),
          },
        ),
      ),
    );
  }
}

class _ResultBody extends StatelessWidget {
  const _ResultBody({required this.result});
  final VerificationResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = result.product;
    final hasDetails = product != null && (product.name != null || product.onChain);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        StatusBadge(status: result.status, large: true),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Why', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              for (final r in result.reasons)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(r.severity.icon, color: r.severity.color, size: 20, semanticLabel: r.severity.name),
                    const SizedBox(width: 10),
                    Expanded(child: Text(r.message, style: theme.textTheme.bodyMedium)),
                  ]),
                ),
            ]),
          ),
        ),
        if (hasDetails) ...[
          const SizedBox(height: 12),
          ProductInfoCard(product: product),
        ] else if (product != null) ...[
          const SizedBox(height: 12),
          Card(child: ListTile(leading: const Icon(Icons.qr_code_2), title: const Text('Product ID'), subtitle: Text(product.productId))),
        ],
        if (result.journey.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Journey', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                JourneyTimeline(events: result.journey),
              ]),
            ),
          ),
        ],
        if (result.technical.isNotEmpty) ...[
          const SizedBox(height: 12),
          TechnicalDetails(technical: result.technical, journey: result.journey),
        ],
        const SizedBox(height: 16),
        if (result.status == VerificationStatus.suspect)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Do not use this product. Keep the packaging and report it to the seller or brand.',
              style: theme.textTheme.bodyMedium?.copyWith(color: VerificationStatus.suspect.color, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
        FilledButton.icon(
          onPressed: () => context.pushReplacement('/scan'),
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scan another product'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () => context.go('/'), child: const Text('Home')),
        const SizedBox(height: 24),
      ],
    );
  }
}
