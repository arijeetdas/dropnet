import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/private_network_profile.dart';

/// Manages creation, storage, migration, import, and export of
/// [PrivateNetworkProfile] instances.
///
/// Profiles are stored as a JSON list in SharedPreferences.
/// The active profile ID is stored separately for fast lookup.
class PrivateProfileManager {
  // ── SharedPreferences keys ──────────────────────────────────────────────────

  static const _profilesKey = 'private_profiles.list';
  static const _activeIdKey = 'private_profiles.activeId';
  static const _migratedKey = 'private_profiles.migrated';

  // ── Legacy SharedPreferences keys (for migration) ───────────────────────────

  static const _legacyFullPrivateModeKey = 'advanced.fullPrivateModeEnabled';
  static const _legacyDiscoveryPortKey = 'advanced.privateDiscoveryPort';
  static const _legacyListeningPortKey = 'advanced.privateListeningPort';

  // ── File extension ──────────────────────────────────────────────────────────

  static const profileFileExtension = '.dnetprofile';

  // ── Internal state ──────────────────────────────────────────────────────────

  List<PrivateNetworkProfile> _profiles = const [];
  String? _activeId;

  List<PrivateNetworkProfile> get profiles =>
      List.unmodifiable(_profiles);

  String? get activeProfileId => _activeId;

  PrivateNetworkProfile? get activeProfile {
    if (_activeId == null) return null;
    try {
      return _profiles.firstWhere((p) => p.id == _activeId);
    } catch (_) {
      return null;
    }
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  /// Load profiles from SharedPreferences. Runs migration on first launch.
  Future<void> load(SharedPreferences prefs) async {
    final migrated = prefs.getBool(_migratedKey) ?? false;
    if (!migrated) {
      await _migrateFromLegacy(prefs);
    }

    final encoded = prefs.getStringList(_profilesKey) ?? const <String>[];
    _profiles = _decode(encoded);
    _activeId = prefs.getString(_activeIdKey);

    // Ensure activeId references a real profile
    if (_activeId != null && !_profiles.any((p) => p.id == _activeId)) {
      _activeId = _profiles.isNotEmpty ? _profiles.first.id : null;
      await prefs.setString(_activeIdKey, _activeId ?? '');
    }
  }

  // ── CRUD ────────────────────────────────────────────────────────────────────

  /// Create a new profile. Returns the created profile on success or an error
  /// message string on validation failure.
  Future<({PrivateNetworkProfile? profile, String? error})> createProfile({
    required SharedPreferences prefs,
    required String name,
    required String description,
    required int discoveryPort,
    required int listeningPort,
    int? webPortalPort,
    bool activate = false,
  }) async {
    final now = DateTime.now();
    final fingerprint = PrivateNetworkProfile.calculateFingerprint(
      name: name.trim(),
      discoveryPort: discoveryPort,
      listeningPort: listeningPort,
      webPortalPort: webPortalPort,
    );

    final profile = PrivateNetworkProfile(
      id: _generateId(),
      name: name.trim(),
      description: description.trim(),
      discoveryPort: discoveryPort,
      listeningPort: listeningPort,
      webPortalPort: webPortalPort,
      createdAt: now,
      updatedAt: now,
      profileFingerprint: fingerprint,
    );

    final error = profile.validate();
    if (error != null) return (profile: null, error: error);

    _profiles = [..._profiles, profile];
    if (activate || _profiles.length == 1) {
      _activeId = profile.id;
    }
    await _persist(prefs);
    return (profile: _profiles.last, error: null);
  }

  /// Update an existing profile. Returns error message or null on success.
  Future<String?> updateProfile({
    required SharedPreferences prefs,
    required PrivateNetworkProfile updated,
  }) async {
    final error = updated.validate();
    if (error != null) return error;

    final idx = _profiles.indexWhere((p) => p.id == updated.id);
    if (idx < 0) return 'Profile not found.';

    final patched = updated.copyWith(updatedAt: DateTime.now());
    final next = List<PrivateNetworkProfile>.from(_profiles);
    next[idx] = patched;
    _profiles = next;
    await _persist(prefs);
    return null;
  }

  /// Delete a profile by id. Returns error message or null on success.
  Future<String?> deleteProfile({
    required SharedPreferences prefs,
    required String id,
  }) async {
    if (_profiles.length <= 1) {
      return 'You must keep at least one private network profile.';
    }
    _profiles = _profiles.where((p) => p.id != id).toList();
    if (_activeId == id) {
      _activeId = _profiles.isNotEmpty ? _profiles.first.id : null;
    }
    await _persist(prefs);
    return null;
  }

  /// Duplicate a profile (with "(Copy)" suffix). Returns the new profile or null.
  Future<PrivateNetworkProfile?> duplicateProfile({
    required SharedPreferences prefs,
    required String id,
  }) async {
    final source = _profiles.where((p) => p.id == id).firstOrNull;
    if (source == null) return null;

    final now = DateTime.now();
    final copyName = '${source.name} (Copy)';
    final copy = source.copyWith(
      id: _generateId(),
      name: copyName,
      createdAt: now,
      updatedAt: now,
    );
    _profiles = [..._profiles, copy];
    await _persist(prefs);
    return _profiles.last;
  }

  /// Activate a profile by id. Returns the activated profile or null.
  Future<PrivateNetworkProfile?> activateProfile({
    required SharedPreferences prefs,
    required String id,
  }) async {
    if (!_profiles.any((p) => p.id == id)) return null;
    _activeId = id;
    await _persist(prefs);
    return activeProfile;
  }

  // ── Duplicate check helper ──────────────────────────────────────────────────

  PrivateNetworkProfile? findDuplicateProfile({
    required String name,
    required int discoveryPort,
    required int listeningPort,
  }) {
    final cleanName = name.trim().toLowerCase();
    for (final p in _profiles) {
      if (p.name.trim().toLowerCase() == cleanName ||
          p.discoveryPort == discoveryPort ||
          p.listeningPort == listeningPort) {
        return p;
      }
    }
    return null;
  }

  // ── Import / Export ─────────────────────────────────────────────────────────

  /// Export a profile to a `.dnetprofile` file in the Downloads/DropNet
  /// directory.  Returns the file path on success or throws.
  Future<String> exportProfile({
    required String id,
  }) async {
    final profile = _profiles.where((p) => p.id == id).firstOrNull;
    if (profile == null) throw StateError('Profile not found.');

    final directory = await _resolveExportDirectory();
    final safeName = profile.name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .trim();
    final fileName = '${safeName.isEmpty ? id : safeName}$profileFileExtension';
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');

    final exportJson = {
      'schemaVersion': profile.schemaVersion,
      'profileType': 'privateNetwork',
      'profileFormatVersion': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'exportedFromVersion': 'DropNet 2.5.0',
      'name': profile.name,
      'description': profile.description,
      'discoveryPort': profile.discoveryPort,
      'listeningPort': profile.listeningPort,
      // ignore: use_null_aware_elements
      if (profile.webPortalPort != null) 'webPortalPort': profile.webPortalPort,
      // ignore: use_null_aware_elements
      if (profile.networkKey != null) 'networkKey': profile.networkKey,
      // ignore: use_null_aware_elements
      if (profile.trustedDevices != null) 'trustedDevices': profile.trustedDevices,
      'profileFingerprint': profile.profileFingerprint,
    };

    await file.writeAsString(jsonEncode(exportJson));
    return file.path;
  }

  /// Read profile data from a file for check/preview before actual import
  Future<({Map<String, dynamic>? data, String? error})> readProfileDataFromFile(String filePath) async {
    final file = File(filePath.trim());
    if (!await file.exists()) {
      return (data: null, error: 'File not found: $filePath');
    }
    try {
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        return (data: null, error: 'Invalid profile format.');
      }

      final format = decoded['format']?.toString();
      final profileType = decoded['profileType']?.toString();

      Map<String, dynamic> profileData;
      if (format == 'dropnet_private_profile') {
        final nested = decoded['profile'];
        if (nested is! Map<String, dynamic>) {
          return (data: null, error: 'Malformed nested profile data.');
        }
        profileData = Map<String, dynamic>.from(nested);
      } else if (profileType == 'privateNetwork') {
        profileData = decoded;
      } else {
        return (data: null, error: 'Unsupported profile type format.');
      }
      return (data: profileData, error: null);
    } catch (e) {
      return (data: null, error: 'Error reading profile: $e');
    }
  }

  /// Import a profile from a `.dnetprofile` file path.
  /// Returns the imported profile or an error message.
  Future<({PrivateNetworkProfile? profile, String? error})> importProfileFromFile({
    required SharedPreferences prefs,
    required String filePath,
    bool activate = false,
  }) async {
    final file = File(filePath.trim());
    if (!await file.exists()) {
      return (profile: null, error: 'File not found: $filePath');
    }

    String content;
    try {
      content = await file.readAsString();
    } catch (e) {
      return (profile: null, error: 'Could not read file: $e');
    }

    return importProfileFromJson(prefs: prefs, jsonContent: content, activate: activate);
  }

  /// Import a profile from a raw JSON string (e.g., from a transferred file).
  Future<({PrivateNetworkProfile? profile, String? error})> importProfileFromJson({
    required SharedPreferences prefs,
    required String jsonContent,
    bool activate = false,
  }) async {
    Map<String, dynamic> parsed;
    try {
      final decoded = jsonDecode(jsonContent);
      if (decoded is! Map<String, dynamic>) {
        return (profile: null, error: 'Invalid profile file format.');
      }
      parsed = decoded;
    } catch (_) {
      return (profile: null, error: 'File is not valid JSON.');
    }

    String name = '';
    String description = '';
    int? discoveryPort;
    int? listeningPort;
    int? webPortalPort;
    int schemaVersion = 1;
    String? networkKey;
    List<String>? trustedDevices;

    final format = parsed['format']?.toString();
    final profileType = parsed['profileType']?.toString();

    if (format == 'dropnet_private_profile') {
      // Legacy structure
      final profileData = parsed['profile'];
      if (profileData is! Map<String, dynamic>) {
        return (profile: null, error: 'Malformed profile data.');
      }
      name = (profileData['name']?.toString() ?? '').trim();
      description = (profileData['description']?.toString() ?? '').trim();
      discoveryPort = profileData['discoveryPort'] as int?;
      listeningPort = profileData['listeningPort'] as int?;
      webPortalPort = profileData['webPortalPort'] as int?;
      schemaVersion = parsed['version'] as int? ?? 1;
    } else if (profileType == 'privateNetwork') {
      // Flat new structure
      schemaVersion = parsed['schemaVersion'] as int? ?? 1;
      name = (parsed['name']?.toString() ?? '').trim();
      description = (parsed['description']?.toString() ?? '').trim();
      discoveryPort = parsed['discoveryPort'] as int?;
      listeningPort = parsed['listeningPort'] as int?;
      webPortalPort = parsed['webPortalPort'] as int?;
      networkKey = parsed['networkKey'] as String?;
      trustedDevices = (parsed['trustedDevices'] as List?)?.map((e) => e.toString()).toList();
    } else {
      return (profile: null, error: 'Unsupported profile format.');
    }

    // Validation
    if (name.isEmpty) {
      return (profile: null, error: 'Validation failed: Profile name is empty.');
    }
    if (discoveryPort == null || listeningPort == null) {
      return (profile: null, error: 'Validation failed: Missing discovery or listening port.');
    }
    if (!PrivateNetworkProfile.isValidPort(discoveryPort)) {
      return (profile: null, error: 'Validation failed: Discovery port out of range.');
    }
    if (!PrivateNetworkProfile.isValidPort(listeningPort)) {
      return (profile: null, error: 'Validation failed: Listening port out of range.');
    }
    if (discoveryPort == listeningPort) {
      return (profile: null, error: 'Validation failed: Discovery and listening ports must be different.');
    }
    if (webPortalPort != null && !PrivateNetworkProfile.isValidPort(webPortalPort)) {
      return (profile: null, error: 'Validation failed: Web portal port out of range.');
    }

    return importProfile(
      prefs: prefs,
      profileData: {
        'name': name,
        'description': description,
        'discoveryPort': discoveryPort,
        'listeningPort': listeningPort,
        // ignore: use_null_aware_elements
        if (webPortalPort != null) 'webPortalPort': webPortalPort,
        // ignore: use_null_aware_elements
        if (networkKey != null) 'networkKey': networkKey,
        // ignore: use_null_aware_elements
        if (trustedDevices != null) 'trustedDevices': trustedDevices,
        'schemaVersion': schemaVersion,
      },
      mode: 'normal',
      activate: activate,
    );
  }

  /// Import a profile with details and conflict resolution mode
  Future<({PrivateNetworkProfile? profile, String? error})> importProfile({
    required SharedPreferences prefs,
    required Map<String, dynamic> profileData,
    required String mode, // 'replace', 'copy', or 'normal'
    String? replaceProfileId,
    bool activate = false,
  }) async {
    final name = (profileData['name']?.toString() ?? '').trim();
    final description = (profileData['description']?.toString() ?? '').trim();
    final discoveryPort = profileData['discoveryPort'] as int?;
    final listeningPort = profileData['listeningPort'] as int?;
    final webPortalPort = profileData['webPortalPort'] as int?;
    final networkKey = profileData['networkKey'] as String?;
    final trustedDevices = (profileData['trustedDevices'] as List?)?.map((e) => e.toString()).toList();
    final schemaVersion = profileData['schemaVersion'] as int? ?? 1;

    if (name.isEmpty || discoveryPort == null || listeningPort == null) {
      return (profile: null, error: 'Validation failed: Missing required fields.');
    }

    if (mode == 'replace' && replaceProfileId != null) {
      final idx = _profiles.indexWhere((p) => p.id == replaceProfileId);
      if (idx >= 0) {
        final existing = _profiles[idx];
        final updated = existing.copyWith(
          name: name,
          description: description,
          discoveryPort: discoveryPort,
          listeningPort: listeningPort,
          webPortalPort: webPortalPort,
          networkKey: networkKey,
          trustedDevices: trustedDevices,
          schemaVersion: schemaVersion,
          updatedAt: DateTime.now(),
        );

        final err = updated.validate();
        if (err != null) return (profile: null, error: err);

        final next = List<PrivateNetworkProfile>.from(_profiles);
        next[idx] = updated;
        _profiles = next;
        if (activate) {
          _activeId = updated.id;
        }
        await _persist(prefs);
        return (profile: updated, error: null);
      }
    }

    String finalName = name;
    if (mode == 'copy') {
      finalName = '$name Copy';
    }

    final now = DateTime.now();
    final fingerprint = PrivateNetworkProfile.calculateFingerprint(
      name: finalName,
      discoveryPort: discoveryPort,
      listeningPort: listeningPort,
      webPortalPort: webPortalPort,
    );

    final profile = PrivateNetworkProfile(
      id: _generateId(),
      name: finalName,
      description: description,
      discoveryPort: discoveryPort,
      listeningPort: listeningPort,
      webPortalPort: webPortalPort,
      createdAt: now,
      updatedAt: now,
      schemaVersion: schemaVersion,
      networkKey: networkKey,
      trustedDevices: trustedDevices,
      profileFingerprint: fingerprint,
    );

    final error = profile.validate();
    if (error != null) return (profile: null, error: error);

    _profiles = [..._profiles, profile];
    if (activate) {
      _activeId = profile.id;
    }
    await _persist(prefs);
    return (profile: profile, error: null);
  }

  // ── Preview (for smart transfer detection) ──────────────────────────────────

  static Future<Map<String, dynamic>?> previewProfileFile(String filePath) async {
    try {
      final file = File(filePath.trim());
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      final parsed = jsonDecode(content);
      if (parsed is! Map<String, dynamic>) return null;

      final format = parsed['format']?.toString();
      final profileType = parsed['profileType']?.toString();

      if (format == 'dropnet_private_profile') {
        final profileData = parsed['profile'];
        if (profileData is! Map<String, dynamic>) return null;
        return Map<String, dynamic>.from(profileData);
      } else if (profileType == 'privateNetwork') {
        return Map<String, dynamic>.from(parsed);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Persistence ─────────────────────────────────────────────────────────────

  Future<void> _persist(SharedPreferences prefs) async {
    final encoded = _encode(_profiles);
    await prefs.setStringList(_profilesKey, encoded);
    await prefs.setString(_activeIdKey, _activeId ?? '');
  }

  // ── Migration ───────────────────────────────────────────────────────────────

  Future<void> _migrateFromLegacy(SharedPreferences prefs) async {
    final wasFullPrivate = prefs.getBool(_legacyFullPrivateModeKey) ?? false;
    final discoveryPort = prefs.getInt(_legacyDiscoveryPortKey) ?? 45454;
    final listeningPort = prefs.getInt(_legacyListeningPortKey) ?? 45455;

    final now = DateTime.now();
    final defaultFingerprint = PrivateNetworkProfile.calculateFingerprint(
      name: 'Default Private Network',
      discoveryPort: discoveryPort,
      listeningPort: listeningPort,
    );

    final defaultProfile = PrivateNetworkProfile(
      id: _generateId(),
      name: 'Default Private Network',
      description: 'Migrated from previous settings.',
      discoveryPort: discoveryPort,
      listeningPort: listeningPort,
      createdAt: now,
      updatedAt: now,
      profileFingerprint: defaultFingerprint,
    );

    _profiles = [defaultProfile];
    _activeId = wasFullPrivate ? defaultProfile.id : null;

    await _persist(prefs);
    await prefs.setBool(_migratedKey, true);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  static String _generateId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static List<PrivateNetworkProfile> _decode(List<String> encoded) {
    final result = <PrivateNetworkProfile>[];
    for (final item in encoded) {
      try {
        final json = jsonDecode(item);
        if (json is Map<String, dynamic>) {
          final profile = PrivateNetworkProfile.fromJson(json);
          if (profile != null) result.add(profile);
        }
      } catch (_) {}
    }
    return result;
  }

  static List<String> _encode(List<PrivateNetworkProfile> profiles) {
    return profiles.map((p) => jsonEncode(p.toJson())).toList();
  }

  static Future<Directory> _resolveExportDirectory() async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      try {
        final dir = await getDownloadsDirectory();
        if (dir != null) {
          final target = Directory('${dir.path}${Platform.pathSeparator}DropNet');
          await target.create(recursive: true);
          return target;
        }
      } catch (_) {}
    }

    if (Platform.isAndroid) {
      const sharedDownloadRoot = '/storage/emulated/0/Download/DropNet';
      try {
        final dir = Directory(sharedDownloadRoot);
        await dir.create(recursive: true);
        return dir;
      } catch (_) {}
    }

    final fallback = await getApplicationDocumentsDirectory();
    final target = Directory('${fallback.path}${Platform.pathSeparator}DropNet');
    await target.create(recursive: true);
    return target;
  }
}
