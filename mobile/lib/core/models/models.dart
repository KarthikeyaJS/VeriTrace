import 'package:equatable/equatable.dart';

typedef Json = Map<String, dynamic>;

DateTime? _date(Object? v) => v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;
String? _str(Object? v) => v?.toString();

enum UserRole {
  admin('Admin'),
  manufacturer('Manufacturer'),
  supplier('Supplier'),
  retailer('Retailer'),
  none('No role');

  const UserRole(this.label);
  final String label;

  static UserRole parse(Object? v) =>
      UserRole.values.firstWhere((r) => r.name == v?.toString().toLowerCase(), orElse: () => UserRole.none);

  static const business = [admin, manufacturer, supplier, retailer];
}

enum ProductStage {
  manufactured('Manufactured', 'At manufacturer'),
  atSupplier('AtSupplier', 'At supplier'),
  atRetailer('AtRetailer', 'At retailer'),
  sold('Sold', 'Sold'),
  unknown('None', 'Not on blockchain');

  const ProductStage(this.wire, this.label);
  final String wire;
  final String label;

  static ProductStage parse(Object? v) =>
      ProductStage.values.firstWhere((s) => s.wire == v?.toString(), orElse: () => ProductStage.unknown);
}

class UserProfile extends Equatable {
  const UserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    this.active = true,
    this.walletAddress,
    this.chainRole,
  });

  final String uid;
  final String email;
  final String displayName;
  final UserRole role;
  final bool active;
  final String? walletAddress;
  final UserRole? chainRole;

  bool get chainRoleInSync => chainRole == null || chainRole == (active ? role : UserRole.none);

  factory UserProfile.fromJson(Json j) => UserProfile(
        uid: j['uid'].toString(),
        email: _str(j['email']) ?? '',
        displayName: _str(j['displayName']) ?? '',
        role: UserRole.parse(j['role']),
        active: j['active'] != false,
        walletAddress: _str(j['walletAddress']),
        chainRole: j['chainRole'] == null ? null : UserRole.parse(j['chainRole']),
      );

  @override
  List<Object?> get props => [uid, email, displayName, role, active, walletAddress, chainRole];
}

/// A wallet on the journey, resolved to a business name where known.
class Party extends Equatable {
  const Party({required this.address, required this.name, this.uid, this.role});

  final String address;
  final String name;
  final String? uid;
  final UserRole? role;

  static Party? fromJson(Object? j) {
    if (j is! Map) return null;
    return Party(
      address: j['address'].toString(),
      name: _str(j['name']) ?? j['address'].toString(),
      uid: _str(j['uid']),
      role: j['role'] == null ? null : UserRole.parse(j['role']),
    );
  }

  @override
  List<Object?> get props => [address, name, uid, role];
}

class Product extends Equatable {
  const Product({
    required this.productId,
    this.name,
    this.brand,
    this.category,
    this.batchNumber,
    this.serialNumber,
    this.manufactureDate,
    this.expiryDate,
    this.mrp,
    this.countryOfOrigin,
    this.description,
    this.manufacturerName,
    this.registerTxHash,
    this.blockNumber,
    this.createdAt,
    this.stage = ProductStage.unknown,
    this.onChain = false,
    this.metadataMissing = false,
    this.productHash,
    this.registeredAt,
    this.manufacturer,
    this.currentHolder,
    this.pendingRecipient,
  });

  final String productId;
  final String? name;
  final String? brand;
  final String? category;
  final String? batchNumber;
  final String? serialNumber;
  final String? manufactureDate;
  final String? expiryDate;
  final num? mrp;
  final String? countryOfOrigin;
  final String? description;
  final String? manufacturerName;
  final String? registerTxHash;
  final int? blockNumber;
  final DateTime? createdAt;
  final ProductStage stage;
  final bool onChain;
  final bool metadataMissing;
  final String? productHash;
  final DateTime? registeredAt;
  final Party? manufacturer;
  final Party? currentHolder;
  final Party? pendingRecipient;

  String get displayName => name ?? productId;
  bool get hasPendingTransfer => pendingRecipient != null;
  bool get isExpired {
    final e = expiryDate;
    if (e == null) return false;
    final d = DateTime.tryParse(e);
    return d != null && d.isBefore(DateTime.now().subtract(const Duration(days: 1)));
  }

  factory Product.fromJson(Json j) {
    final chain = j['chain'] is Map ? Map<String, dynamic>.from(j['chain'] as Map) : null;
    return Product(
      productId: j['productId'].toString(),
      name: _str(j['name']),
      brand: _str(j['brand']),
      category: _str(j['category']),
      batchNumber: _str(j['batchNumber']),
      serialNumber: _str(j['serialNumber']),
      manufactureDate: _str(j['manufactureDate']),
      expiryDate: _str(j['expiryDate']),
      mrp: j['mrp'] is num ? j['mrp'] as num : null,
      countryOfOrigin: _str(j['countryOfOrigin']),
      description: _str(j['description']),
      manufacturerName: _str(j['manufacturerName']),
      registerTxHash: _str(j['registerTxHash']),
      blockNumber: j['blockNumber'] is int ? j['blockNumber'] as int : null,
      createdAt: _date(j['createdAt']),
      stage: ProductStage.parse(j['stage']),
      onChain: j['onChain'] == true,
      metadataMissing: j['metadataMissing'] == true,
      productHash: _str(chain?['productHash']) ?? _str(j['hash']),
      registeredAt: _date(chain?['registeredAt']),
      manufacturer: Party.fromJson(chain?['manufacturer']),
      currentHolder: Party.fromJson(chain?['currentHolder']),
      pendingRecipient: Party.fromJson(chain?['pendingRecipient']),
    );
  }

  @override
  List<Object?> get props => [productId, name, stage, currentHolder, pendingRecipient, productHash, expiryDate, metadataMissing];
}

class JourneyEvent extends Equatable {
  const JourneyEvent({
    required this.eventType,
    required this.label,
    required this.stageAfter,
    required this.timestamp,
    this.from,
    this.to,
    this.txHash,
    this.blockNumber,
  });

  final String eventType;
  final String label;
  final ProductStage stageAfter;
  final DateTime? timestamp;
  final Party? from;
  final Party? to;
  final String? txHash;
  final int? blockNumber;

  factory JourneyEvent.fromJson(Json j) => JourneyEvent(
        eventType: j['eventType'].toString(),
        label: _str(j['label']) ?? j['eventType'].toString(),
        stageAfter: ProductStage.parse(j['stageAfter']),
        timestamp: _date(j['timestamp']),
        from: Party.fromJson(j['from']),
        to: Party.fromJson(j['to']),
        txHash: _str(j['txHash']),
        blockNumber: j['blockNumber'] is int ? j['blockNumber'] as int : null,
      );

  @override
  List<Object?> get props => [eventType, stageAfter, timestamp, from, to, txHash, blockNumber];
}

List<JourneyEvent> parseJourney(Object? list) =>
    list is List ? list.whereType<Map>().map((e) => JourneyEvent.fromJson(Map<String, dynamic>.from(e))).toList() : const [];

List<Product> parseProducts(Object? list) =>
    list is List ? list.whereType<Map>().map((e) => Product.fromJson(Map<String, dynamic>.from(e))).toList() : const [];

/// Product detail screen payload.
class ProductDetail extends Equatable {
  const ProductDetail({required this.product, required this.journey, this.qrPayload, this.technical = const {}});

  final Product product;
  final List<JourneyEvent> journey;
  final String? qrPayload;
  final Json technical;

  factory ProductDetail.fromJson(Json j) => ProductDetail(
        product: Product.fromJson(Map<String, dynamic>.from(j['product'] as Map)),
        journey: parseJourney(j['journey']),
        qrPayload: _str(j['qrPayload']),
        technical: j['technical'] is Map ? Map<String, dynamic>.from(j['technical'] as Map) : const {},
      );

  @override
  List<Object?> get props => [product, journey, qrPayload, technical];
}

/// Result of a write action (transfer/confirm/sold) — the transaction reference.
class TxResult extends Equatable {
  const TxResult({this.txHash, this.blockNumber});
  final String? txHash;
  final int? blockNumber;

  factory TxResult.fromJson(Json j) =>
      TxResult(txHash: _str(j['txHash']), blockNumber: j['blockNumber'] is int ? j['blockNumber'] as int : null);

  @override
  List<Object?> get props => [txHash, blockNumber];
}
