// ignore_for_file: avoid_print
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

  Future<bool> openFileExternally(String path) async {
    try {
      final opened = await _channel.invokeMethod<bool>(
        'openFileExternally',
        {'path': path},
      );
      return opened == true;
    } catch (_) {
      return false;
    }
  }

  Future<List<String>?> pickMedia() async {
    try {
      print("[DropNet] MediaStoreService: Invoking pickGalleryMedia channel...");
      final List<dynamic>? paths = await _channel.invokeMethod<List<dynamic>>('pickGalleryMedia');
      print("[DropNet] MediaStoreService: pickGalleryMedia response paths: \$paths");
      return paths?.cast<String>();
    } catch (e) {
      print("[DropNet] MediaStoreService ERROR picking media: \$e");
      return null;
    }
  }

  Future<List<String>?> pickAudio() async {
    try {
      print("[DropNet] MediaStoreService: Invoking pickAudio channel...");
      final List<dynamic>? paths = await _channel.invokeMethod<List<dynamic>>('pickAudio');
      print("[DropNet] MediaStoreService: pickAudio response paths: \$paths");
      return paths?.cast<String>();
    } catch (e) {
      print("[DropNet] MediaStoreService ERROR picking audio: \$e");
      return null;
    }
  }
}
