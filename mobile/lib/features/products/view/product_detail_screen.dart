import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/bloc/load_state.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/product_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../transfers/data/transfers_repository.dart';
import '../../transfers/view/recipient_picker.dart';
import '../bloc/product_detail_cubit.dart';
import '../data/products_repository.dart';
import 'qr_actions.dart';

class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({super.key, required this.productId});
  final String productId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (ctx) => ProductDetailCubit(
        productId: productId,
        products: ctx.read<ProductsRepository>(),
        transfers: ctx.read<TransfersRepository>(),
      )..load(),
      child: Scaffold(
        appBar: AppBar(title: Text(productId)),
        body: BlocConsumer<ProductDetailCubit, ProductDetailState>(
          listenWhen: (a, b) => a.feedback != b.feedback && b.feedback != null,
          listener: (context, state) => showMessage(context, state.feedback!.message, error: state.feedback!.isError),
          builder: (context, state) {
            final detail = state.detail;
            if (detail == null) {
              return state.status == LoadStatus.failure
                  ? ErrorView(message: state.error ?? 'Could not load product', onRetry: context.read<ProductDetailCubit>().load)
                  : const LoadingView();
            }
            return RefreshIndicator(
              onRefresh: context.read<ProductDetailCubit>().load,
              child: _DetailBody(detail: detail, busyAction: state.busyAction),
            );
          },
        ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.detail, required this.busyAction});
  final ProductDetail detail;
  final String? busyAction;

  @override
  Widget build(BuildContext context) {
    final p = detail.product;
    final user = context.select((AuthBloc b) => b.state.user);
    final cubit = context.read<ProductDetailCubit>();
    final me = user?.uid;
    final isHolder = me != null && p.currentHolder?.uid == me;
    final isRecipient = me != null && p.pendingRecipient?.uid == me;
    final busy = busyAction != null;

    final actions = <Widget>[];
    if (isRecipient) {
      actions.add(_ActionButton(
        label: 'Confirm receipt',
        icon: Icons.move_to_inbox,
        busy: busyAction == 'confirm',
        onPressed: busy ? null : cubit.confirm,
      ));
    }
    if (isHolder && p.hasPendingTransfer) {
      actions.add(_ActionButton(
        label: 'Cancel transfer to ${p.pendingRecipient!.name}',
        icon: Icons.undo,
        outlined: true,
        busy: busyAction == 'cancel',
        onPressed: busy
            ? null
            : () async {
                if (await confirmDialog(context, title: 'Cancel transfer?', message: 'The product stays with you.', confirmLabel: 'Cancel transfer')) {
                  await cubit.cancel();
                }
              },
      ));
    }
    if (isHolder && !p.hasPendingTransfer && (p.stage == ProductStage.manufactured || p.stage == ProductStage.atSupplier)) {
      actions.add(_ActionButton(
        label: p.stage == ProductStage.manufactured ? 'Transfer to supplier' : 'Transfer to supplier / retailer',
        icon: Icons.local_shipping,
        busy: busyAction == 'initiate',
        onPressed: busy
            ? null
            : () async {
                final to = await pickRecipient(context, product: p);
                if (to != null) await cubit.initiate(to);
              },
      ));
    }
    if (isHolder && user?.role == UserRole.retailer && p.stage == ProductStage.atRetailer) {
      actions.add(_ActionButton(
        label: 'Mark as sold',
        icon: Icons.point_of_sale,
        busy: busyAction == 'sold',
        onPressed: busy
            ? null
            : () async {
                if (await confirmDialog(context,
                    title: 'Mark as sold?', message: 'This is final and recorded on the blockchain.', confirmLabel: 'Mark sold')) {
                  await cubit.markSold();
                }
              },
      ));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        ProductInfoCard(product: p),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...actions.expand((a) => [a, const SizedBox(height: 8)]),
        ],
        if (detail.qrPayload != null) ...[
          const SizedBox(height: 4),
          _QrCard(product: p, payload: detail.qrPayload!),
        ],
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.timeline),
            title: const Text('Product journey'),
            subtitle: Text('${detail.journey.length} blockchain events'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/products/${Uri.encodeComponent(p.productId)}/journey'),
          ),
        ),
        const SizedBox(height: 12),
        TechnicalDetails(technical: detail.technical, journey: detail.journey),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.icon, required this.onPressed, this.busy = false, this.outlined = false});
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
        : Icon(icon);
    return outlined
        ? OutlinedButton.icon(onPressed: onPressed, icon: child, label: Text(busy ? 'Waiting for blockchain…' : label))
        : FilledButton.icon(onPressed: onPressed, icon: child, label: Text(busy ? 'Waiting for blockchain…' : label));
  }
}

class _QrCard extends StatefulWidget {
  const _QrCard({required this.product, required this.payload});
  final Product product;
  final String payload;

  @override
  State<_QrCard> createState() => _QrCardState();
}

class _QrCardState extends State<_QrCard> {
  bool _sharing = false;
  bool _printing = false;

  QrLabel get _label => QrLabel(productId: widget.product.productId, payload: widget.payload, name: widget.product.name);

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      await shareQrPng(_label);
    } catch (e) {
      if (mounted) showMessage(context, 'Could not share: ${errorMessage(e)}', error: true);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _print() async {
    final copies = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Labels on the sheet'),
        children: [
          for (final n in [1, 6, 12, 21])
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, n), child: Text('$n label${n == 1 ? '' : 's'}')),
        ],
      ),
    );
    if (copies == null) return;
    setState(() => _printing = true);
    try {
      await printLabelSheet(List.filled(copies, _label), name: 'VeriTrace ${widget.product.productId}');
    } catch (e) {
      if (mounted) showMessage(context, 'Could not print: ${errorMessage(e)}', error: true);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Text('Product QR code', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(8),
            child: QrImageView(data: widget.payload, size: 200, errorCorrectionLevel: QrErrorCorrectLevel.M, semanticsLabel: 'QR code for ${widget.product.productId}'),
          ),
          const SizedBox(height: 4),
          Text(widget.product.productId, style: const TextStyle(fontFamily: 'monospace')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _sharing ? null : _share,
                icon: _sharing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.share),
                label: const Text('Share PNG'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _printing ? null : _print,
                icon: _printing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.print),
                label: const Text('Print labels'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
