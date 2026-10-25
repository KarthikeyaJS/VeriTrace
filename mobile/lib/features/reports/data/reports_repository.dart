import 'package:equatable/equatable.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/status_style.dart';

class ScanRecord extends Equatable {
  const ScanRecord({required this.status, this.productId, this.productName, this.at, this.deviceId, this.flags = const []});
  final VerificationStatus status;
  final String? productId;
  final String? productName;
  final DateTime? at;
  final String? deviceId;
  final List<String> flags;

  factory ScanRecord.fromJson(Json j) => ScanRecord(
        status: VerificationStatus.parse(j['status']),
        productId: j['productId']?.toString(),
        productName: j['productName']?.toString(),
        at: j['at'] is String ? DateTime.tryParse(j['at'] as String)?.toLocal() : null,
        deviceId: j['deviceId']?.toString(),
        flags: (j['flags'] as List? ?? const []).map((e) => e.toString()).toList(),
      );

  @override
  List<Object?> get props => [status, productId, at, deviceId, flags];
}

class ReportSummary extends Equatable {
  const ReportSummary({
    required this.scanTotal,
    required this.scansByStatus,
    required this.productTotal,
    required this.productsByStage,
    required this.usersByRole,
    required this.recentAlerts,
  });

  final int scanTotal;
  final Map<VerificationStatus, int> scansByStatus;
  final int productTotal;
  final Map<String, int> productsByStage;
  final Map<String, int> usersByRole;
  final List<ScanRecord> recentAlerts;

  static Map<String, int> _ints(Object? m) =>
      m is Map ? m.map((k, v) => MapEntry(k.toString(), v is num ? v.toInt() : 0)) : const {};

  factory ReportSummary.fromJson(Json j) {
    final scans = j['scans'] as Map? ?? const {};
    final byStatus = _ints(scans['byStatus']);
    final products = j['products'] as Map? ?? const {};
    return ReportSummary(
      scanTotal: (scans['total'] as num?)?.toInt() ?? 0,
      scansByStatus: {for (final s in VerificationStatus.values) s: byStatus[s.label] ?? 0},
      productTotal: (products['total'] as num?)?.toInt() ?? 0,
      productsByStage: _ints(products['byStage']),
      usersByRole: _ints((j['users'] as Map?)?['byRole']),
      recentAlerts: (j['recentAlerts'] as List? ?? const []).whereType<Map>().map((e) => ScanRecord.fromJson(Map<String, dynamic>.from(e))).toList(),
    );
  }

  @override
  List<Object?> get props => [scanTotal, scansByStatus, productTotal, productsByStage, usersByRole, recentAlerts];
}

class ReportsRepository {
  ReportsRepository(this._api);
  final ApiClient _api;

  Future<ReportSummary> summary() async => ReportSummary.fromJson(await _api.get('/reports/summary'));

  Future<List<ScanRecord>> scans({VerificationStatus? status}) async {
    final res = await _api.get('/reports/scans', query: {'status': status?.label ?? 'all', 'limit': 100});
    return (res['scans'] as List? ?? const []).whereType<Map>().map((e) => ScanRecord.fromJson(Map<String, dynamic>.from(e))).toList();
  }
}
