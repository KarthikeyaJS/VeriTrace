import 'package:equatable/equatable.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/status_style.dart';

class ScanRecord extends Equatable {
  const ScanRecord({required this.status, this.productId, this.productName, this.at, this.deviceId, this.flags = const [], this.mlScore, this.mlAnomaly});
  final VerificationStatus status;
  final String? productId;
  final String? productName;
  final DateTime? at;
  final String? deviceId;
  final List<String> flags;

  /// Anomaly score from the ML service, null when the scan was not scored (service offline).
  final double? mlScore;
  final bool? mlAnomaly;

  factory ScanRecord.fromJson(Json j) {
    final ml = j['ml'];
    return ScanRecord(
      status: VerificationStatus.parse(j['status']),
      productId: j['productId']?.toString(),
      productName: j['productName']?.toString(),
      at: j['at'] is String ? DateTime.tryParse(j['at'] as String)?.toLocal() : null,
      deviceId: j['deviceId']?.toString(),
      flags: (j['flags'] as List? ?? const []).map((e) => e.toString()).toList(),
      mlScore: ml is Map && ml['anomalyScore'] is num ? (ml['anomalyScore'] as num).toDouble() : null,
      mlAnomaly: ml is Map ? ml['isAnomaly'] == true : null,
    );
  }

  @override
  List<Object?> get props => [status, productId, at, deviceId, flags, mlScore, mlAnomaly];
}

/// State of the ML anomaly service and what it has done so far.
class MlSummary extends Equatable {
  const MlSummary({
    required this.configured,
    required this.online,
    required this.scansScored,
    required this.flaggedByMl,
    this.modelVersion,
    this.threshold,
    this.falsePositiveRate,
    this.overallRecall,
  });

  final bool configured;
  final bool online;
  final int scansScored;
  final int flaggedByMl;
  final String? modelVersion;
  final double? threshold;

  /// Measured on SYNTHETIC hold-out data at training time.
  final double? falsePositiveRate;
  final double? overallRecall;

  static double? _d(Object? v) => v is num ? v.toDouble() : null;

  factory MlSummary.fromJson(Json j) {
    final metrics = j['metrics'] is Map ? j['metrics'] as Map : const {};
    return MlSummary(
      configured: j['configured'] == true,
      online: j['ok'] == true,
      scansScored: (j['scansScored'] as num?)?.toInt() ?? 0,
      flaggedByMl: (j['flaggedByMl'] as num?)?.toInt() ?? 0,
      modelVersion: j['modelVersion']?.toString(),
      threshold: _d(j['threshold']),
      falsePositiveRate: _d(metrics['holdoutFalsePositiveRate']),
      overallRecall: _d(metrics['overallRecall']),
    );
  }

  @override
  List<Object?> get props => [configured, online, scansScored, flaggedByMl, modelVersion, threshold, falsePositiveRate, overallRecall];
}

class ReportSummary extends Equatable {
  const ReportSummary({
    required this.scanTotal,
    required this.scansByStatus,
    required this.productTotal,
    required this.productsByStage,
    required this.usersByRole,
    required this.recentAlerts,
    this.ml,
  });

  final int scanTotal;
  final Map<VerificationStatus, int> scansByStatus;
  final int productTotal;
  final Map<String, int> productsByStage;
  final Map<String, int> usersByRole;
  final List<ScanRecord> recentAlerts;
  final MlSummary? ml;

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
      ml: j['ml'] is Map ? MlSummary.fromJson(Map<String, dynamic>.from(j['ml'] as Map)) : null,
    );
  }

  @override
  List<Object?> get props => [scanTotal, scansByStatus, productTotal, productsByStage, usersByRole, recentAlerts, ml];
}

class ReportsRepository {
  ReportsRepository(this._api);
  final ApiClient _api;

  Future<ReportSummary> summary() async => ReportSummary.fromJson(await _api.get('/reports/summary'));

  /// Recent scans filtered by result [status] and/or a reason [flag] (e.g. `ML_ANOMALY`).
  Future<List<ScanRecord>> scans({VerificationStatus? status, String? flag}) async {
    final res = await _api.get('/reports/scans', query: {'status': status?.label ?? 'all', 'flag': ?flag, 'limit': 100});
    return (res['scans'] as List? ?? const []).whereType<Map>().map((e) => ScanRecord.fromJson(Map<String, dynamic>.from(e))).toList();
  }
}
