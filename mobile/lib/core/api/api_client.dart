import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../errors/api_exception.dart';
import '../models/models.dart' show Json;

/// Returns the current Firebase ID token, or null when signed out.
typedef TokenProvider = Future<String?> Function();

/// Thin JSON client for the VeriTrace backend. Adds the Firebase ID token to every
/// request and converts failures into [ApiException].
class ApiClient {
  ApiClient({required this._config, required TokenProvider tokenProvider, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 45), // writes wait for the tx to be mined
              contentType: Headers.jsonContentType,
              responseType: ResponseType.json,
            )) {
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) async {
      options.baseUrl = _config.apiBaseUrl;
      try {
        final token = await tokenProvider();
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
      } catch (_) {
        // signed-out or token refresh failed: send without auth, backend decides
      }
      handler.next(options);
    }));
  }

  final AppConfig _config;
  final Dio _dio;

  String get baseUrl => _config.apiBaseUrl;

  Future<Json> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get<dynamic>(path, queryParameters: query));

  Future<Json> post(String path, {Object? body}) => _send(() => _dio.post<dynamic>(path, data: body ?? const {}));

  Future<Json> patch(String path, {Object? body}) => _send(() => _dio.patch<dynamic>(path, data: body ?? const {}));

  Future<Json> _send(Future<Response<dynamic>> Function() request) async {
    try {
      final res = await request();
      final data = res.data;
      if (data is Map<String, dynamic>) return data;
      throw const ApiException(code: 'BAD_RESPONSE', message: 'The server sent an unexpected response.');
    } on DioException catch (e) {
      throw ApiException.fromDio(e, baseUrl: _config.apiBaseUrl);
    }
  }
}
