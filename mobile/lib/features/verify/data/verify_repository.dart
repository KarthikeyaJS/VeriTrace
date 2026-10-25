import '../../../core/api/api_client.dart';
import 'verification_result.dart';

class VerifyRepository {
  VerifyRepository({required this._api, required this._deviceId});

  final ApiClient _api;
  final String _deviceId;

  /// Public endpoint: no login needed. Pass a scanned [payload] or a typed [productId].
  Future<VerificationResult> verify({String? payload, String? productId}) async {
    final body = <String, dynamic>{'deviceId': _deviceId};
    if (payload != null && payload.isNotEmpty) body['payload'] = payload;
    if (productId != null && productId.isNotEmpty) body['productId'] = productId;
    final res = await _api.post('/verify', body: body);
    return VerificationResult.fromJson(res);
  }
}
