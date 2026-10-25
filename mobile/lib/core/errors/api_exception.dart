import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';

/// Error returned by the backend (`{ error: { code, message, details } }`) or the network.
class ApiException extends Equatable implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.onChain = false,
    this.chainReason,
  });

  final String code;
  final String message;
  final int? statusCode;

  /// True when the smart contract rejected the transaction.
  final bool onChain;
  final String? chainReason;

  bool get isNetwork => code == 'NETWORK';

  /// Message ready for a snackbar / error view.
  String get displayMessage => onChain ? 'Rejected by the smart contract: $message' : message;

  factory ApiException.fromDio(DioException e, {String? baseUrl}) {
    final data = e.response?.data;
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      final details = err['details'];
      return ApiException(
        code: (err['code'] ?? 'ERROR').toString(),
        message: (err['message'] ?? 'Request failed').toString(),
        statusCode: e.response?.statusCode,
        onChain: details is Map && details['onChain'] == true,
        chainReason: details is Map ? details['reason']?.toString() : null,
      );
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.sendTimeout:
        return ApiException(
          code: 'NETWORK',
          message: 'Cannot reach the VeriTrace server${baseUrl != null ? ' at $baseUrl' : ''}. '
              'Check that your phone and laptop are on the same Wi-Fi and the server is running.',
        );
      case DioExceptionType.receiveTimeout:
        return const ApiException(code: 'TIMEOUT', message: 'The server took too long to respond. Please try again.');
      default:
        final status = e.response?.statusCode;
        return ApiException(
          code: status != null ? 'HTTP_$status' : 'UNKNOWN',
          message: status != null ? 'Server error ($status).' : 'Unexpected error: ${e.message}',
          statusCode: status,
        );
    }
  }

  @override
  List<Object?> get props => [code, message, statusCode, onChain, chainReason];

  @override
  String toString() => 'ApiException($code, $message)';
}

/// Turns any error into user-facing text.
String errorMessage(Object error) {
  if (error is ApiException) return error.displayMessage;
  return error.toString().replaceFirst('Exception: ', '');
}
