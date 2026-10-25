import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/bloc/load_state.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/product_widgets.dart';
import '../../products/data/products_repository.dart';
import '../data/transfers_repository.dart';

class TransferActionsState extends Equatable {
  const TransferActionsState({this.busy = const {}, this.feedback});

  /// Product IDs with an action in flight (their buttons are disabled).
  final Set<String> busy;
  final UiFeedback? feedback;

  @override
  List<Object?> get props => [busy, feedback];
}

/// Confirm / transfer / cancel / sell from the supplier & retailer queues.
class TransferActionsCubit extends Cubit<TransferActionsState> {
  TransferActionsCubit({required this._transfers, required this._products, required this.onChanged}) : super(const TransferActionsState());

  final TransfersRepository _transfers;
  final ProductsRepository _products;

  /// Called after every successful action (reloads the lists).
  final Future<void> Function() onChanged;
  int _id = 0;

  Future<void> _run(String productId, Future<TxResult> Function() call, String success) async {
    if (state.busy.contains(productId)) return;
    emit(TransferActionsState(busy: {...state.busy, productId}, feedback: state.feedback));
    try {
      final tx = await call();
      await onChanged();
      emit(TransferActionsState(
        busy: {...state.busy}..remove(productId),
        feedback: UiFeedback(++_id, '$success (tx ${shortHash(tx.txHash)})'),
      ));
    } catch (e) {
      emit(TransferActionsState(busy: {...state.busy}..remove(productId), feedback: UiFeedback(++_id, errorMessage(e), isError: true)));
    }
  }

  Future<void> confirm(Product p) => _run(p.productId, () => _transfers.confirm(p.productId), '${p.productId} received');
  Future<void> initiate(Product p, Recipient to) =>
      _run(p.productId, () => _transfers.initiate(p.productId, to.uid), '${p.productId} sent to ${to.displayName}');
  Future<void> cancel(Product p) => _run(p.productId, () => _transfers.cancel(p.productId), 'Transfer of ${p.productId} cancelled');
  Future<void> sell(Product p) => _run(p.productId, () => _products.markSold(p.productId), '${p.productId} marked as sold');
}
