import 'package:flutter/services.dart';

class MediaStoreService {
  const MediaStoreService();

  static const MethodChannel _channel = MethodChannel('dropnet/media_store');

  Future<bool> saveToGallery(String path) async {
    try {
      final saved = await _channel.invokeMethod<bool>('saveToGallery', {'path': path});
      return saved == true;
    } catch (_) {
      return false;
    }
  }
}
