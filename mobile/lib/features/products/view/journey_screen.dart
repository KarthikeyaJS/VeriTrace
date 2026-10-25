import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/bloc/load_state.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/journey_timeline.dart';
import '../../../core/widgets/product_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../data/products_repository.dart';

/// Full custody journey of a product, read from the blockchain.
class JourneyScreen extends StatelessWidget {
  const JourneyScreen({super.key, required this.productId});
  final String productId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (ctx) => LoadCubit<ProductDetail>(() => ctx.read<ProductsRepository>().detail(productId))..load(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Product journey')),
        body: BlocBuilder<LoadCubit<ProductDetail>, LoadState<ProductDetail>>(
          builder: (context, state) {
            final detail = state.data;
            if (detail == null) {
              return state.status == LoadStatus.failure
                  ? ErrorView(message: state.error!, onRetry: context.read<LoadCubit<ProductDetail>>().load)
                  : const LoadingView();
            }
            final theme = Theme.of(context);
            return RefreshIndicator(
              onRefresh: context.read<LoadCubit<ProductDetail>>().load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(detail.product.displayName, style: theme.textTheme.titleLarge),
                  Text(detail.product.productId, style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
                  const SizedBox(height: 8),
                  StageChip(stage: detail.product.stage, pending: detail.product.hasPendingTransfer),
                  const SizedBox(height: 20),
                  JourneyTimeline(events: detail.journey),
                  TechnicalDetails(technical: detail.technical, journey: detail.journey),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
