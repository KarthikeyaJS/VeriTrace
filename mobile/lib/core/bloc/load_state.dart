import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../errors/api_exception.dart';

enum LoadStatus { loading, success, failure }

/// Generic loading/success/failure state for read-only screens.
class LoadState<T> extends Equatable {
  const LoadState({this.status = LoadStatus.loading, this.data, this.error});

  final LoadStatus status;
  final T? data;
  final String? error;

  @override
  List<Object?> get props => [status, data, error];
}

/// Loads a value with [loader]; call [load] again to refresh (keeps old data while refreshing).
class LoadCubit<T> extends Cubit<LoadState<T>> {
  LoadCubit(this._loader) : super(LoadState<T>());

  final Future<T> Function() _loader;

  Future<void> load() async {
    emit(LoadState<T>(status: LoadStatus.loading, data: state.data));
    try {
      emit(LoadState<T>(status: LoadStatus.success, data: await _loader()));
    } catch (e) {
      emit(LoadState<T>(status: LoadStatus.failure, data: state.data, error: errorMessage(e)));
    }
  }
}

/// One-shot user feedback (snackbar). [id] increases so listeners fire for repeated messages.
class UiFeedback extends Equatable {
  const UiFeedback(this.id, this.message, {this.isError = false});
  final int id;
  final String message;
  final bool isError;

  @override
  List<Object?> get props => [id, message, isError];
}
