class TrustedPeer {
  const TrustedPeer({
    required this.deviceId,
    required this.deviceName,
    required this.tlsCertificateSha256,
    required this.pairedAt,
  });

  final String deviceId;
  final String deviceName;
  final String tlsCertificateSha256;
  final DateTime pairedAt;

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'tlsCertificateSha256': tlsCertificateSha256,
      'pairedAt': pairedAt.toIso8601String(),
    };
  }

  static TrustedPeer? fromJson(Map<String, dynamic> json) {
    final deviceId = (json['deviceId']?.toString() ?? '').trim();
    final deviceName = (json['deviceName']?.toString() ?? '').trim();
    final fingerprint = (json['tlsCertificateSha256']?.toString() ?? '')
        .trim()
        .toLowerCase();
    final pairedAtRaw = (json['pairedAt']?.toString() ?? '').trim();

    if (deviceId.isEmpty || fingerprint.isEmpty) {
      return null;
    }

    final parsedPairedAt = DateTime.tryParse(pairedAtRaw);
    if (parsedPairedAt == null) {
      return null;
    }

    return TrustedPeer(
      deviceId: deviceId,
      deviceName: deviceName,
      tlsCertificateSha256: fingerprint,
      pairedAt: parsedPairedAt,
    );
  }

  TrustedPeer copyWith({
    String? deviceId,
    String? deviceName,
    String? tlsCertificateSha256,
    DateTime? pairedAt,
  }) {
    return TrustedPeer(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      tlsCertificateSha256:
          tlsCertificateSha256 ?? this.tlsCertificateSha256,
      pairedAt: pairedAt ?? this.pairedAt,
    );
  }
}