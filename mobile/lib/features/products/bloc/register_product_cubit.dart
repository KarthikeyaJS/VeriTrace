import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/errors/api_exception.dart';
import '../data/products_repository.dart';

class RegisterProductState extends Equatable {
  const RegisterProductState({this.submitting = false, this.error, this.createdId});
  final bool submitting;
  final String? error;
  final String? createdId;

  @override
  List<Object?> get props => [submitting, error, createdId];
}

class RegisterProductCubit extends Cubit<RegisterProductState> {
  RegisterProductCubit(this._repo) : super(const RegisterProductState());
  final ProductsRepository _repo;

  Future<void> submit(Map<String, dynamic> input) async {
    if (state.submitting) return;
    emit(const RegisterProductState(submitting: true));
    try {
      emit(RegisterProductState(createdId: await _repo.register(input)));
    } catch (e) {
      emit(RegisterProductState(error: errorMessage(e)));
    }
  }
}
