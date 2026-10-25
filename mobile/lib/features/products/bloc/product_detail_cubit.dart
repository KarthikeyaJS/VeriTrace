import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/bloc/load_state.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/product_widgets.dart';
import '../../transfers/data/transfers_repository.dart';
import '../data/products_repository.dart';

class ProductDetailState extends Equatable {
  const ProductDetailState({this.status = LoadStatus.loading, this.detail, this.error, this.busyAction, this.feedback});

  final LoadStatus status;
  final ProductDetail? detail;
  final String? error;

  /// Name of the action in flight (buttons are disabled while non-null).
  final String? busyAction;
  final UiFeedback? feedback;

  ProductDetailState copyWith({LoadStatus? status, ProductDetail? detail, String? error, String? busyAction, bool clearBusy = false, UiFeedback? feedback}) =>
      ProductDetailState(
        status: status ?? this.status,
        detail: detail ?? this.detail,
        error: error,
        busyAction: clearBusy ? null : (busyAction ?? this.busyAction),
        feedback: feedback ?? this.feedback,
      );

  @override
  List<Object?> get props => [status, detail, error, busyAction, feedback];
}

/// Product detail + custody actions (transfer, cancel, confirm, mark sold).
class ProductDetailCubit extends Cubit<ProductDetailState> {
  ProductDetailCubit({required this.productId, required this._products, required this._transfers}) : super(const ProductDetailState());

  final String productId;
  final ProductsRepository _products;
  final TransfersRepository _transfers;
  int _feedbackId = 0;

  Future<void> load() async {
    emit(state.copyWith(status: LoadStatus.loading));
    try {
      emit(state.copyWith(status: LoadStatus.success, detail: await _products.detail(productId)));
    } catch (e) {
      emit(state.copyWith(status: LoadStatus.failure, error: errorMessage(e)));
    }
  }

  Future<void> _run(String action, Future<TxResult> Function() call, String success) async {
    if (state.busyAction != null) return;
    emit(state.copyWith(busyAction: action));
    final TxResult tx;
    try {
      tx = await call();
    } catch (e) {
      emit(state.copyWith(clearBusy: true, feedback: UiFeedback(++_feedbackId, errorMessage(e), isError: true)));
      return;
    }
    ProductDetail? refreshed;
    try {
      refreshed = await _products.detail(productId);
    } catch (_) {
      refreshed = null; // the transaction succeeded; a failed refresh only means stale data until pull-to-refresh
    }
    emit(state.copyWith(
      status: LoadStatus.success,
      detail: refreshed,
      clearBusy: true,
      feedback: UiFeedback(++_feedbackId, '$success (tx ${shortHash(tx.txHash)})'),
    ));
  }

  Future<void> initiate(Recipient to) =>
      _run('initiate', () => _transfers.initiate(productId, to.uid), 'Transfer to ${to.displayName} started');
  Future<void> cancel() => _run('cancel', () => _transfers.cancel(productId), 'Transfer cancelled');
  Future<void> confirm() => _run('confirm', () => _transfers.confirm(productId), 'Receipt confirmed');
  Future<void> markSold() => _run('sold', () => _products.markSold(productId), 'Marked as sold');
}
