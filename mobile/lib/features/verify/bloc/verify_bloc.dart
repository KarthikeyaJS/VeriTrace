import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/errors/api_exception.dart';
import '../data/verification_result.dart';
import '../data/verify_repository.dart';

// ------------------------------------------------------------------ events
sealed class VerifyEvent extends Equatable {
  const VerifyEvent();
  @override
  List<Object?> get props => [];
}

/// Verify a scanned QR [payload] or a manually typed [productId].
class VerifyRequested extends VerifyEvent {
  const VerifyRequested({this.payload, this.productId});
  final String? payload;
  final String? productId;
  @override
  List<Object?> get props => [payload, productId];
}

/// Re-run the last request (e.g. after a network error).
class VerifyRetried extends VerifyEvent {
  const VerifyRetried();
}

// ------------------------------------------------------------------ states
sealed class VerifyState extends Equatable {
  const VerifyState();
  @override
  List<Object?> get props => [];
}

class VerifyInitial extends VerifyState {
  const VerifyInitial();
}

class VerifyLoading extends VerifyState {
  const VerifyLoading();
}

class VerifySuccess extends VerifyState {
  const VerifySuccess(this.result);
  final VerificationResult result;
  @override
  List<Object?> get props => [result];
}

class VerifyFailure extends VerifyState {
  const VerifyFailure(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}

// -------------------------------------------------------------------- bloc
class VerifyBloc extends Bloc<VerifyEvent, VerifyState> {
  VerifyBloc({required VerifyRepository repository})
      : _repo = repository,
        super(const VerifyInitial()) {
    on<VerifyRequested>(_onRequested);
    on<VerifyRetried>(_onRetried);
  }

  final VerifyRepository _repo;
  VerifyRequested? _last;

  Future<void> _onRequested(VerifyRequested event, Emitter<VerifyState> emit) async {
    final payload = event.payload?.trim();
    final productId = event.productId?.trim();
    if ((payload == null || payload.isEmpty) && (productId == null || productId.isEmpty)) {
      emit(const VerifyFailure('Scan a QR code or enter a product ID.'));
      return;
    }
    _last = event;
    emit(const VerifyLoading());
    try {
      emit(VerifySuccess(await _repo.verify(payload: payload, productId: productId)));
    } catch (e) {
      emit(VerifyFailure(errorMessage(e)));
    }
  }

  Future<void> _onRetried(VerifyRetried event, Emitter<VerifyState> emit) async {
    final last = _last;
    if (last != null) await _onRequested(last, emit);
  }
}
