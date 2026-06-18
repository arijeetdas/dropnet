import 'dart:convert';
import 'package:crypto/crypto.dart';

class PrivateNetworkProfile {
  const PrivateNetworkProfile({
    required this.id,
    required this.name,
    required this.description,
    required this.discoveryPort,
    required this.listeningPort,
    this.webPortalPort,
    required this.createdAt,
    required this.updatedAt,
    this.schemaVersion = 1,
    this.networkKey,
    this.trustedDevices,
    required this.profileFingerprint,
  });

  final String id;
  final String name;
  final String description;
  final int discoveryPort;
  final int listeningPort;

  /// Optional: stored for future Web Mode integration.
  final int? webPortalPort;

  final DateTime createdAt;
  final DateTime updatedAt;

  // Future-proofing and duplication/authenticating fields
  final int schemaVersion;
  final String? networkKey;
  final List<String>? trustedDevices;
  final String profileFingerprint;

  // ── Fingerprint Calculation ──────────────────────────────────────────────────

  static String calculateFingerprint({
    required String name,
    required int discoveryPort,
    required int listeningPort,
    int? webPortalPort,
  }) {
    final input = '${name.trim()}|$discoveryPort|$listeningPort|${webPortalPort ?? ""}';
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // ── Validation helpers ──────────────────────────────────────────────────────

  static bool isValidPort(int port) => port >= 1024 && port <= 65535;

  String? validate() {
    if (name.trim().isEmpty) {
      return 'Profile name cannot be empty.';
    }
    if (!isValidPort(discoveryPort)) {
      return 'Discovery port must be between 1024 and 65535.';
    }
    if (!isValidPort(listeningPort)) {
      return 'Listening port must be between 1024 and 65535.';
    }
    if (discoveryPort == listeningPort) {
      return 'Discovery port and listening port must be different.';
    }
    if (webPortalPort != null && !isValidPort(webPortalPort!)) {
      return 'Web portal port must be between 1024 and 65535.';
    }
    return null;
  }

  // ── Serialization ───────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'discoveryPort': discoveryPort,
      'listeningPort': listeningPort,
      if (webPortalPort != null) 'webPortalPort': webPortalPort,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'schemaVersion': schemaVersion,
      if (networkKey != null) 'networkKey': networkKey,
      if (trustedDevices != null) 'trustedDevices': trustedDevices,
      'profileFingerprint': profileFingerprint,
    };
  }

  static PrivateNetworkProfile? fromJson(Map<String, dynamic> json) {
    try {
      final id = (json['id']?.toString() ?? '').trim();
      final name = (json['name']?.toString() ?? '').trim();
      if (id.isEmpty || name.isEmpty) return null;

      final discoveryPort = json['discoveryPort'] as int?;
      final listeningPort = json['listeningPort'] as int?;
      if (discoveryPort == null || listeningPort == null) return null;

      final createdAtRaw = (json['createdAt']?.toString() ?? '').trim();
      final updatedAtRaw = (json['updatedAt']?.toString() ?? '').trim();
      final createdAt = DateTime.tryParse(createdAtRaw);
      final updatedAt = DateTime.tryParse(updatedAtRaw);
      if (createdAt == null || updatedAt == null) return null;

      final schemaVersion = json['schemaVersion'] as int? ?? 1;
      final networkKey = json['networkKey'] as String?;
      final trustedDevices = (json['trustedDevices'] as List?)?.map((e) => e.toString()).toList();
      
      final fingerprint = (json['profileFingerprint']?.toString() ?? '').trim().isNotEmpty
          ? json['profileFingerprint'].toString()
          : calculateFingerprint(
              name: name,
              discoveryPort: discoveryPort,
              listeningPort: listeningPort,
              webPortalPort: json['webPortalPort'] as int?,
            );

      return PrivateNetworkProfile(
        id: id,
        name: name,
        description: (json['description']?.toString() ?? '').trim(),
        discoveryPort: discoveryPort,
        listeningPort: listeningPort,
        webPortalPort: json['webPortalPort'] as int?,
        createdAt: createdAt,
        updatedAt: updatedAt,
        schemaVersion: schemaVersion,
        networkKey: networkKey,
        trustedDevices: trustedDevices,
        profileFingerprint: fingerprint,
      );
    } catch (_) {
      return null;
    }
  }

  // ── copyWith ────────────────────────────────────────────────────────────────

  PrivateNetworkProfile copyWith({
    String? id,
    String? name,
    String? description,
    int? discoveryPort,
    int? listeningPort,
    int? webPortalPort,
    bool clearWebPortalPort = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? schemaVersion,
    String? networkKey,
    List<String>? trustedDevices,
  }) {
    final nextName = name ?? this.name;
    final nextDisc = discoveryPort ?? this.discoveryPort;
    final nextListen = listeningPort ?? this.listeningPort;
    final nextWeb = clearWebPortalPort ? null : (webPortalPort ?? this.webPortalPort);

    return PrivateNetworkProfile(
      id: id ?? this.id,
      name: nextName,
      description: description ?? this.description,
      discoveryPort: nextDisc,
      listeningPort: nextListen,
      webPortalPort: nextWeb,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      networkKey: networkKey ?? this.networkKey,
      trustedDevices: trustedDevices ?? this.trustedDevices,
      profileFingerprint: calculateFingerprint(
        name: nextName,
        discoveryPort: nextDisc,
        listeningPort: nextListen,
        webPortalPort: nextWeb,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrivateNetworkProfile &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          description == other.description &&
          discoveryPort == other.discoveryPort &&
          listeningPort == other.listeningPort &&
          webPortalPort == other.webPortalPort &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt &&
          schemaVersion == other.schemaVersion &&
          networkKey == other.networkKey &&
          const ListEquality().equals(trustedDevices, other.trustedDevices) &&
          profileFingerprint == other.profileFingerprint;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        description,
        discoveryPort,
        listeningPort,
        webPortalPort,
        createdAt,
        updatedAt,
        schemaVersion,
        networkKey,
        Object.hashAll(trustedDevices ?? const []),
        profileFingerprint,
      );
}

class ListEquality {
  const ListEquality();
  bool equals(List? a, List? b) {
    if (a == null) return b == null;
    if (b == null) return false;
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
