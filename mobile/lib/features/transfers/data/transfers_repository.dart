import 'package:equatable/equatable.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/models.dart';

class Recipient extends Equatable {
  const Recipient({required this.uid, required this.displayName, required this.role});
  final String uid;
  final String displayName;
  final UserRole role;

  @override
  List<Object?> get props => [uid, displayName, role];
}

class TransfersRepository {
  TransfersRepository(this._api);
  final ApiClient _api;

  String _id(String productId) => Uri.encodeComponent(productId);

  /// Products waiting for me to confirm receipt.
  Future<List<Product>> incoming() async => parseProducts((await _api.get('/transfers/incoming'))['products']);

  /// Products I currently hold (not sold).
  Future<List<Product>> custody() async => parseProducts((await _api.get('/transfers/custody'))['products']);

  Future<List<Recipient>> recipients(UserRole role) async {
    final res = await _api.get('/users/recipients', query: {'role': role.name});
    return (res['recipients'] as List? ?? const [])
        .whereType<Map>()
        .map((r) => Recipient(uid: r['uid'].toString(), displayName: r['displayName'].toString(), role: UserRole.parse(r['role'])))
        .toList();
  }

  Future<TxResult> initiate(String productId, String toUid) async =>
      TxResult.fromJson(await _api.post('/transfers/${_id(productId)}/initiate', body: {'toUid': toUid}));

  Future<TxResult> confirm(String productId) async => TxResult.fromJson(await _api.post('/transfers/${_id(productId)}/confirm'));

  Future<TxResult> cancel(String productId) async => TxResult.fromJson(await _api.post('/transfers/${_id(productId)}/cancel'));
}
