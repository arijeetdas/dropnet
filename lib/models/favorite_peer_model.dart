class FavoritePeer {
  const FavoritePeer({
    required this.deviceId,
    required this.deviceName,
    required this.manufacturer,
    required this.platform,
    required this.lastKnownIp,
    required this.addedAt,
    required this.lastSeenAt,
  });

  final String deviceId;
  final String deviceName;
  final String manufacturer;
  final String platform;
  final String lastKnownIp;
  final DateTime addedAt;
  final DateTime lastSeenAt;

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'deviceName': deviceName,
    'manufacturer': manufacturer,
    'platform': platform,
    'lastKnownIp': lastKnownIp,
    'addedAt': addedAt.toIso8601String(),
    'lastSeenAt': lastSeenAt.toIso8601String(),
  };

  static FavoritePeer? fromJson(Map<String, dynamic> json) {
    final deviceId = (json['deviceId']?.toString() ?? '').trim();
    if (deviceId.isEmpty) {
      return null;
    }

    final addedAt = DateTime.tryParse(json['addedAt']?.toString() ?? '');
    final lastSeenAt = DateTime.tryParse(json['lastSeenAt']?.toString() ?? '');

    return FavoritePeer(
      deviceId: deviceId,
      deviceName: (json['deviceName']?.toString() ?? '').trim(),
      manufacturer: (json['manufacturer']?.toString() ?? '').trim(),
      platform: (json['platform']?.toString() ?? '').trim(),
      lastKnownIp: (json['lastKnownIp']?.toString() ?? '').trim(),
      addedAt: addedAt ?? DateTime.now(),
      lastSeenAt: lastSeenAt ?? (addedAt ?? DateTime.now()),
    );
  }

  FavoritePeer copyWith({
    String? deviceId,
    String? deviceName,
    String? manufacturer,
    String? platform,
    String? lastKnownIp,
    DateTime? addedAt,
    DateTime? lastSeenAt,
  }) {
    return FavoritePeer(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      manufacturer: manufacturer ?? this.manufacturer,
      platform: platform ?? this.platform,
      lastKnownIp: lastKnownIp ?? this.lastKnownIp,
      addedAt: addedAt ?? this.addedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }
}
