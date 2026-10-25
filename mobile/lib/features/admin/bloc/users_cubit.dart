import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/bloc/load_state.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/models/models.dart';
import '../data/admin_repository.dart';

class UsersState extends Equatable {
  const UsersState({this.status = LoadStatus.loading, this.users, this.filter, this.error, this.busyUid, this.feedback});

  final LoadStatus status;
  final List<UserProfile>? users;
  final UserRole? filter;
  final String? error;
  final String? busyUid;
  final UiFeedback? feedback;

  @override
  List<Object?> get props => [status, users, filter, error, busyUid, feedback];
}

class UsersCubit extends Cubit<UsersState> {
  UsersCubit(this._repo) : super(const UsersState());
  final AdminRepository _repo;
  int _id = 0;

  Future<void> load({UserRole? filter, bool keepFilter = true}) async {
    final f = keepFilter && filter == null ? state.filter : filter;
    emit(UsersState(status: LoadStatus.loading, users: state.users, filter: f, feedback: state.feedback));
    try {
      emit(UsersState(status: LoadStatus.success, users: await _repo.users(role: f), filter: f, feedback: state.feedback));
    } catch (e) {
      emit(UsersState(status: LoadStatus.failure, users: state.users, filter: f, error: errorMessage(e), feedback: state.feedback));
    }
  }

  Future<void> setFilter(UserRole? role) => load(filter: role, keepFilter: false);

  Future<void> update(UserProfile user, {UserRole? role, bool? active}) async {
    if (state.busyUid != null) return;
    emit(UsersState(status: state.status, users: state.users, filter: state.filter, busyUid: user.uid, feedback: state.feedback));
    try {
      final updated = await _repo.updateUser(user.uid, role: role, active: active);
      final list = [for (final u in state.users ?? <UserProfile>[]) u.uid == updated.uid ? updated : u];
      final what = role != null ? 'role is now ${updated.role.label}' : (updated.active ? 'activated' : 'deactivated');
      emit(UsersState(
        status: LoadStatus.success,
        users: list,
        filter: state.filter,
        feedback: UiFeedback(++_id, '${updated.displayName}: $what (on-chain role: ${updated.chainRole?.label ?? '—'})'),
      ));
    } catch (e) {
      emit(UsersState(status: state.status, users: state.users, filter: state.filter, feedback: UiFeedback(++_id, errorMessage(e), isError: true)));
    }
  }
}
