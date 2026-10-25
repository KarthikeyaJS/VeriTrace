import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/bloc/load_state.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/product_widgets.dart';
import '../../../core/widgets/state_views.dart';

/// Product card used in every list (dashboards, queues, admin).
class ProductTile extends StatelessWidget {
  const ProductTile({super.key, required this.product, this.subtitle, this.trailing, this.actions = const []});
  final Product product;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await context.push('/products/${Uri.encodeComponent(product.productId)}');
          // The detail screen may have changed custody: refresh the list this tile belongs to.
          if (!context.mounted) return;
          try {
            BlocProvider.of<LoadCubit<List<Product>>>(context, listen: false).load();
          } catch (_) {
            // tile used outside a product list
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(product.displayName, style: theme.textTheme.titleMedium),
                  Text(product.productId, style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
                ]),
              ),
              ?trailing,
            ]),
            const SizedBox(height: 8),
            StageChip(stage: product.stage, pending: product.hasPendingTransfer),
            if (subtitle != null) ...[const SizedBox(height: 6), Text(subtitle!, style: theme.textTheme.bodySmall)],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          ]),
        ),
      ),
    );
  }
}

/// List of products backed by a [LoadCubit] with loading, empty, error and pull-to-refresh.
class ProductListView extends StatelessWidget {
  const ProductListView({super.key, required this.emptyTitle, this.emptyMessage, this.emptyIcon = Icons.inventory_2_outlined, this.tileBuilder});
  final String emptyTitle;
  final String? emptyMessage;
  final IconData emptyIcon;
  final Widget Function(BuildContext context, Product product)? tileBuilder;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<LoadCubit<List<Product>>>();
    return BlocBuilder<LoadCubit<List<Product>>, LoadState<List<Product>>>(
      builder: (context, state) {
        final products = state.data;
        if (products == null) {
          return state.status == LoadStatus.failure ? ErrorView(message: state.error!, onRetry: cubit.load) : const LoadingView();
        }
        return RefreshIndicator(
          onRefresh: cubit.load,
          child: products.isEmpty
              ? RefreshableCenter(child: EmptyView(icon: emptyIcon, title: emptyTitle, message: emptyMessage))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: products.length + (state.status == LoadStatus.failure ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    if (i == products.length) {
                      return Text('Refresh failed: ${state.error}', style: TextStyle(color: Theme.of(context).colorScheme.error));
                    }
                    return tileBuilder?.call(context, products[i]) ??
                        ProductTile(
                          product: products[i],
                          subtitle: products[i].currentHolder == null ? null : 'Held by ${products[i].currentHolder!.name}',
                        );
                  },
                ),
        );
      },
    );
  }
}

String productHolderLine(Product p) {
  if (p.pendingRecipient != null) return 'Awaiting ${p.pendingRecipient!.name}';
  if (p.currentHolder != null) return 'Held by ${p.currentHolder!.name}';
  return formatDateTime(p.createdAt);
}
