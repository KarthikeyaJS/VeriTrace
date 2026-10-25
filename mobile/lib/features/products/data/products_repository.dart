import '../../../core/api/api_client.dart';
import '../../../core/models/models.dart';

const productCategories = [
  'Electronics',
  'Pharmaceuticals',
  'Apparel',
  'Cosmetics',
  'Food & Beverage',
  'Automotive Parts',
  'Luxury Goods',
  'Other',
];

/// Builds the QR payload from an on-chain hash (same format as the backend).
String buildQrPayload(String productId, String hash) =>
    'veritrace://verify?id=${Uri.encodeQueryComponent(productId)}&h=${hash.toLowerCase().replaceFirst('0x', '')}';

class ProductsRepository {
  ProductsRepository(this._api);
  final ApiClient _api;

  Future<List<Product>> mine() async => parseProducts((await _api.get('/products/mine'))['products']);

  Future<List<Product>> all() async => parseProducts((await _api.get('/products'))['products']);

  Future<ProductDetail> detail(String productId) async =>
      ProductDetail.fromJson(await _api.get('/products/${Uri.encodeComponent(productId)}'));

  /// Registers a product on-chain + in the database. Returns the new product ID.
  Future<String> register(Map<String, dynamic> input) async {
    final res = await _api.post('/products', body: input);
    return (res['product'] as Map)['productId'].toString();
  }

  Future<TxResult> markSold(String productId) async =>
      TxResult.fromJson(await _api.post('/products/${Uri.encodeComponent(productId)}/sold'));
}
