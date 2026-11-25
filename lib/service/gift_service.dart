import 'package:uuid/uuid.dart';

import '../model/gift_model.dart';
import 'api_service.dart';

class GiftService {
  // Sends flowers to the host or to a guest on stage.
  //
  // Every new gift gets a new request id. If the SAME gift is retried (for
  // example after a network error), pass the same [requestId] again so the
  // backend charges it only once. The flower animation arrives through
  // LiveStreamService.onFlower().
  //
  // Returns the gift, whether it was a duplicate, and the flowers you have left.
  static Future<({GiftModel gift, bool duplicate, int flowersLeft})>
      sendFlowerGift({
    required int streamId,
    required int recipientId,
    required int quantity,
    String? requestId,
  }) async {
    if (quantity < 1 || quantity > 1000) {
      throw ApiException('Quantity must be between 1 and 1000.',
          statusCode: 400);
    }

    final response = await ApiService.post('/gifts/flowers', body: {
      'stream_id': streamId,
      'recipient_id': recipientId,
      'quantity': quantity,
      'request_id': requestId ?? const Uuid().v4(),
    });
    final data = response['data'] as Map<String, dynamic>;

    final bool duplicate = (data['duplicate'] as bool?) ?? false;
    final int flowersLeft = (data['flowers_left'] as num).toInt();
    final gift =
        GiftModel.fromJson(data['gift'] as Map<String, dynamic>);

    return (
      gift: gift,
      duplicate: duplicate,
      flowersLeft: flowersLeft,
    );
  }
}