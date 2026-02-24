import 'dart:convert';

enum DeviceType { phone, tablet, desktop, web, other }

class DeviceModel {
  const DeviceModel({
    required this.deviceId,
    required this.deviceName,
    required this.manufacturer,
    required this.platform,
    required this.ipAddress,
    required this.deviceType,
    required this.isOnline,
    required this.lastSeen,
  });

  final String deviceId;
  final String deviceName;
  final String manufacturer;
  final String platform;
  final String ipAddress;
  final DeviceType deviceType;
  final bool isOnline;
  final DateTime lastSeen;

  static String _canonicalPlatform(String raw) {
    final value = raw.trim();
    final lower = value.toLowerCase();
    if (lower.isEmpty) {
      return value;
    }
    if (lower == 'windows' || lower == 'wndows' || lower == 'window') {
      return 'Windows';
    }
    if (lower == 'macos' || lower == 'mac os' || lower == 'mac') {
      return 'macOS';
    }
    if (lower == 'ios') {
      return 'iOS';
    }
    if (lower == 'ipados') {
      return 'iPadOS';
    }
    if (lower == 'android') {
      return 'Android';
    }
    if (lower == 'linux') {
      return 'Linux';
    }
    if (lower == 'web') {
      return 'Web';
    }
    return value;
  }

  String get taggedName {
    final baseParts = deviceName
        .split('•')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    final parts = baseParts.isEmpty ? <String>[deviceName.trim()] : <String>[...baseParts];

    final normalizedPlatform = _canonicalPlatform(platform).toLowerCase();
    if (normalizedPlatform.isNotEmpty) {
      parts.removeWhere((part) => part.toLowerCase() == normalizedPlatform);
      if (parts.isEmpty) {
        parts.add(deviceName.trim());
      }
    }

    final normalizedManufacturer = manufacturer.trim();
    if (normalizedManufacturer.isNotEmpty) {
      final lowerManufacturer = normalizedManufacturer.toLowerCase();
      final hasManufacturer = parts.any((part) => part.toLowerCase() == lowerManufacturer);
      final manufacturerAsPlatform = _canonicalPlatform(normalizedManufacturer).toLowerCase();
      final sameAsPlatform = normalizedPlatform.isNotEmpty && manufacturerAsPlatform == normalizedPlatform;
      if (!hasManufacturer && !sameAsPlatform) {
        parts.add(normalizedManufacturer);
      }
    }

    return parts.where((part) => part.isNotEmpty).join(' • ');
  }

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'manufacturer': manufacturer,
        'platform': platform,
        'ipAddress': ipAddress,
        'deviceType': deviceType.name,
        'isOnline': isOnline,
        'lastSeen': lastSeen.toIso8601String(),
      };

  String toWire() => jsonEncode(toJson());

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    return DeviceModel(
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String,
      manufacturer: (json['manufacturer']?.toString() ?? '').trim(),
      platform: _canonicalPlatform((json['platform']?.toString() ?? '').trim()),
      ipAddress: json['ipAddress'] as String,
      deviceType: DeviceType.values.firstWhere(
        (value) => value.name == json['deviceType'],
        orElse: () => DeviceType.other,
      ),
      isOnline: json['isOnline'] as bool? ?? true,
      lastSeen: DateTime.tryParse(json['lastSeen']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  factory DeviceModel.fromWire(String wire) => DeviceModel.fromJson(jsonDecode(wire) as Map<String, dynamic>);

  DeviceModel copyWith({
    String? deviceId,
    String? deviceName,
    String? manufacturer,
    String? platform,
    String? ipAddress,
    DeviceType? deviceType,
    bool? isOnline,
    DateTime? lastSeen,
  }) {
    return DeviceModel(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      manufacturer: manufacturer ?? this.manufacturer,
      platform: platform ?? this.platform,
      ipAddress: ipAddress ?? this.ipAddress,
      deviceType: deviceType ?? this.deviceType,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}
