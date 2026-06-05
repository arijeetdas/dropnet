import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bonsoir/bonsoir.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/device_model.dart';
import '../security/local_tls_certificate_service.dart';

class DiscoveryService {
  DiscoveryService({
    String? deviceName,
    LocalTlsCertificateService? tlsCertificateService,
  }) : _deviceNumber = 0,
       _tlsCertificates = tlsCertificateService ?? LocalTlsCertificateService(),
       _deviceBaseName = _normalizeBaseName(deviceName) ?? _defaultBaseName();

  static const _discoveryPort = 45454;
  static const _broadcastAddress = '255.255.255.255';
  static const _presenceTransportBroadcast = 'broadcast';
  static const _presenceTransportReply = 'reply';
  static const _identityFileName = 'dropnet_identity.json';
  static const _tlsCertCommonName = 'DropNet Local';
  static const _tlsCertSans = <String>['localhost', '127.0.0.1'];
  static const Duration _presenceMaxClockSkew = Duration(seconds: 45);
  static const Duration _nonceRetentionWindow = Duration(minutes: 3);

  String _deviceBaseName;
  int _deviceNumber;
  String _manufacturerTag = '';
  String _cpuArchitectureTag = '';
  String _deviceId = '';
  bool _pairingModeEnabled = false;
  final LocalTlsCertificateService _tlsCertificates;
  String _tlsCertificateFingerprint = '';
  String _tlsCertificatePem = '';
  final _networkInfo = NetworkInfo();
  final _deviceInfo = DeviceInfoPlugin();
  final _devicesController = StreamController<List<DeviceModel>>.broadcast();
  final Map<String, DateTime> _recentPresenceNonces = {};
  BonsoirDiscovery? _mdnsDiscovery;
  BonsoirBroadcast? _mdnsBroadcast;
  StreamSubscription<BonsoirDiscoveryEvent>? _mdnsSub;

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _socketSub;
  bool _restartingSocket = false;
  Timer? _announceTimer;
  Timer? _pruneTimer;
  final Map<String, DeviceModel> _devices = {};
  bool _identityLoaded = false;
  String? _cachedLocalIp;
  DateTime? _lastIpCacheTime;

  Stream<List<DeviceModel>> get devicesStream => _devicesController.stream;
  String get deviceName => '$_deviceBaseName #$_deviceNumber';
  String get manufacturerTag => _manufacturerTag;
  String get cpuArchitectureTag => _cpuArchitectureTag;
  String get platformTag => _detectPlatformTag();
  String get deviceBaseName => _deviceBaseName;
  int get deviceNumber => _deviceNumber;
  String get deviceId => _deviceId;
  String get localTlsCertificateSha256 => _tlsCertificateFingerprint;
  String get taggedDeviceName => _manufacturerTag.trim().isEmpty
      ? deviceName
      : '$deviceName • ${_manufacturerTag.trim()}';

  Future<String> ensureLocalTlsCertificateSha256() async {
    await _refreshTlsFingerprintAndCertificate();
    return _tlsCertificateFingerprint;
  }

  Future<void> start() async {
    await _loadIdentity();
    if (_socket != null) {
      _normalizeCachedDevices();
      return;
    }

    await _bindSocket();
    if (_socket == null) {
      return;
    }

    _normalizeCachedDevices();

    if (!Platform.isWindows) {
      await _startMdns();
    }

    _announce();
    _announceTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _announce(),
    );
    _pruneTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _pruneOfflineDevices(),
    );
  }

  Future<void> updateDeviceName(String newName) async {
    final normalized = _normalizeBaseName(newName);
    if (normalized == null || normalized == _deviceBaseName) {
      return;
    }
    _deviceBaseName = normalized;
    await _saveIdentity();
    await _announce();
    if (!Platform.isWindows && _socket != null) {
      await _mdnsSub?.cancel();
      _mdnsSub = null;
      await _mdnsDiscovery?.stop();
      _mdnsDiscovery = null;
      await _mdnsBroadcast?.stop();
      _mdnsBroadcast = null;
      await _startMdns();
    }
  }

  Future<void> updateDeviceNumber(int newNumber) async {
    if (newNumber < 1000 || newNumber > 9999 || newNumber == _deviceNumber) {
      return;
    }
    _deviceNumber = newNumber;
    await _saveIdentity();
    await _announce();
    if (!Platform.isWindows && _socket != null) {
      await _mdnsSub?.cancel();
      _mdnsSub = null;
      await _mdnsDiscovery?.stop();
      _mdnsDiscovery = null;
      await _mdnsBroadcast?.stop();
      _mdnsBroadcast = null;
      await _startMdns();
    }
  }

  Future<void> updateManufacturerTag(String newTag) async {
    final normalized = _normalizeManufacturer(newTag);
    if (normalized == _manufacturerTag) {
      return;
    }
    _manufacturerTag = normalized;
    await _saveIdentity();
    await _announce();
    if (!Platform.isWindows && _socket != null) {
      await _mdnsSub?.cancel();
      _mdnsSub = null;
      await _mdnsDiscovery?.stop();
      _mdnsDiscovery = null;
      await _mdnsBroadcast?.stop();
      _mdnsBroadcast = null;
      await _startMdns();
    }
  }

  Future<void> updatePairingModeEnabled(bool enabled) async {
    if (_pairingModeEnabled == enabled) {
      return;
    }
    _pairingModeEnabled = enabled;

    if (_devices.isNotEmpty) {
      _devices.clear();
      _emitDevices();
    }

    if (_socket == null) {
      return;
    }

    await _announce();
    if (!Platform.isWindows) {
      await _mdnsSub?.cancel();
      _mdnsSub = null;
      await _mdnsDiscovery?.stop();
      _mdnsDiscovery = null;
      await _mdnsBroadcast?.stop();
      _mdnsBroadcast = null;
      await _startMdns();
    }
  }

  Future<void> resetManufacturerTagToAuto() async {
    final detected = await _detectManufacturerTag();
    final normalized = _normalizeManufacturer(detected);
    if (normalized == _manufacturerTag) {
      return;
    }
    _manufacturerTag = normalized;
    await _saveIdentity();
    await _announce();
    if (!Platform.isWindows && _socket != null) {
      await _mdnsSub?.cancel();
      _mdnsSub = null;
      await _mdnsDiscovery?.stop();
      _mdnsDiscovery = null;
      await _mdnsBroadcast?.stop();
      _mdnsBroadcast = null;
      await _startMdns();
    }
  }

  Future<void> refreshNow() async {
    _cachedLocalIp = null;
    _lastIpCacheTime = null;
    if (_socket == null) {
      await start();
      return;
    }
    _normalizeCachedDevices();
    await _announce();
    _pruneOfflineDevices();
  }

  Future<void> _bindSocket() async {
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      );
      _socket!.broadcastEnabled = true;
      _socketSub = _socket!.listen(
        _onSocketEvent,
        onError: (_) {
          unawaited(_restartSocket());
        },
        onDone: () {
          unawaited(_restartSocket());
        },
      );
    } catch (_) {
      _socket = null;
    }
  }

  Future<void> _restartSocket() async {
    if (_restartingSocket) {
      return;
    }
    _restartingSocket = true;
    try {
      await _socketSub?.cancel();
      _socketSub = null;
      _socket?.close();
      _socket = null;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _bindSocket();
      if (_socket != null) {
        await _announce();
      }
    } finally {
      _restartingSocket = false;
    }
  }

  void _onSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) {
      return;
    }
    while (true) {
      final datagram = _socket?.receive();
      if (datagram == null) {
        break;
      }

      try {
        final message = utf8.decode(datagram.data);
        final parsed = jsonDecode(message) as Map<String, dynamic>;
        if (parsed['kind'] != 'dropnet_presence') {
          continue;
        }

        final payloadMap = (parsed['payload'] as Map?)?.cast<String, dynamic>();
        if (payloadMap == null) {
          continue;
        }

        if (!_isPresenceSecurityValid(
          payload: payloadMap,
          parsedPacket: parsed,
        )) {
          continue;
        }

        if (_parseBoolish(payloadMap['pairingModeEnabled']) !=
            _pairingModeEnabled) {
          continue;
        }

        final incoming = DeviceModel.fromJson(payloadMap);
        final incomingId = incoming.deviceId.trim();
        if (incomingId.isNotEmpty && incomingId == _deviceId) {
          continue;
        }

        final seenAt = DateTime.now();
        final key = incomingId.isNotEmpty
            ? incomingId
            : datagram.address.address;
        final previous = _devices[key];
        _upsertDiscoveredDevice(
          key,
          incoming.copyWith(
            ipAddress: datagram.address.address,
            isOnline: true,
            lastSeen: seenAt,
          ),
        );
        if (_shouldReplyToPresence(
          packet: parsed,
          previous: previous,
          senderAddress: datagram.address.address,
          seenAt: seenAt,
        )) {
          unawaited(_replyToPresence(datagram.address));
        }
      } catch (_) {}
    }
  }

  Future<void> _announce() async {
    final packet = await _buildPresencePacket(
      transport: _presenceTransportBroadcast,
    );
    if (packet == null) {
      return;
    }

    final targets = await _collectBroadcastTargets();
    for (final target in targets) {
      _socket?.send(packet, target, _discoveryPort);
    }
  }

  Future<void> _replyToPresence(InternetAddress target) async {
    final packet = await _buildPresencePacket(
      transport: _presenceTransportReply,
      preferredPeerIp: target.address,
    );
    if (packet == null) {
      return;
    }
    _socket?.send(packet, target, _discoveryPort);
  }

  Future<void> _startMdns() async {
    final ipAddress = await getLocalIp();
    if (ipAddress.isEmpty) {
      return;
    }

    await _refreshTlsFingerprintAndCertificate();
    if (_tlsCertificateFingerprint.isEmpty) {
      return;
    }

    final service = BonsoirService(
      name: deviceName,
      type: '_dropnet._tcp',
      port: 45455,
      attributes: {
        'deviceId': _deviceId,
        'deviceType': _detectType().name,
        'manufacturer': _manufacturerTag,
        'platform': platformTag,
        'tlsCertificateSha256': _tlsCertificateFingerprint,
        'pairingModeEnabled': _pairingModeEnabled ? '1' : '0',
      },
    );

    _mdnsBroadcast = BonsoirBroadcast(service: service);
    await _mdnsBroadcast!.initialize();
    await _mdnsBroadcast!.start();

    _mdnsDiscovery = BonsoirDiscovery(type: '_dropnet._tcp');
    await _mdnsDiscovery!.initialize();
    _mdnsSub = _mdnsDiscovery!.eventStream?.listen(_onMdnsEvent);
    await _mdnsDiscovery!.start();
  }

  void _onMdnsEvent(BonsoirDiscoveryEvent event) {
    if (event is BonsoirDiscoveryServiceFoundEvent) {
      event.service.resolve(_mdnsDiscovery!.serviceResolver);
      return;
    }
    if (event is BonsoirDiscoveryServiceResolvedEvent) {
      final service = event.service;
      if (service.attributes['deviceId'] == _deviceId) {
        return;
      }
      final host = service.host;
      if (host == null || host.isEmpty) {
        return;
      }
      final type = service.attributes['deviceType'] ?? DeviceType.other.name;
      final manufacturer =
          (service.attributes['manufacturer']?.toString() ?? '').trim();
      final platform = _normalizePlatformLabel(
        (service.attributes['platform']?.toString() ?? '').trim(),
      );
      final tlsCertificateSha256 =
          (service.attributes['tlsCertificateSha256']?.toString() ?? '')
              .trim()
              .toLowerCase();
      if (tlsCertificateSha256.isEmpty) {
        return;
      }
      final incomingPairingMode = _parseBoolish(
        service.attributes['pairingModeEnabled'],
      );
      if (incomingPairingMode != _pairingModeEnabled) {
        return;
      }
      final rawId = (service.attributes['deviceId']?.toString() ?? '').trim();
      final resolvedId = rawId.isNotEmpty ? rawId : host;
      if (resolvedId == _deviceId) {
        return;
      }
      _upsertDiscoveredDevice(
        resolvedId,
        DeviceModel(
          deviceId: resolvedId,
          deviceName: service.name,
          manufacturer: manufacturer,
          platform: platform,
          ipAddress: host,
          deviceType: DeviceType.values.firstWhere(
            (value) => value.name == type,
            orElse: () => DeviceType.other,
          ),
          isOnline: true,
          lastSeen: DateTime.now(),
          tlsCertificateSha256: tlsCertificateSha256,
        ),
      );
      return;
    }
    if (event is BonsoirDiscoveryServiceLostEvent) {
      final service = event.service;
      final id = (service.attributes['deviceId']?.toString() ?? service.name)
          .trim();
      _devices.remove(id);
      _emitDevices();
    }
  }

  void _upsertDiscoveredDevice(String key, DeviceModel device) {
    final normalizedKey = key.trim().isEmpty ? device.ipAddress : key.trim();
    final duplicates = <String>[];
    for (final entry in _devices.entries) {
      if (entry.key == normalizedKey) {
        continue;
      }
      if (entry.value.ipAddress == device.ipAddress) {
        duplicates.add(entry.key);
      }
    }
    for (final duplicateKey in duplicates) {
      _devices.remove(duplicateKey);
    }
    _devices[normalizedKey] = device;
    _emitDevices();
  }

  Future<List<InternetAddress>> _collectBroadcastTargets() async {
    final targets = <String>{_broadcastAddress};
    final wifiBroadcast = (await _networkInfo.getWifiBroadcast())?.trim() ?? '';
    if (_isUsableIpv4(wifiBroadcast)) {
      targets.add(wifiBroadcast);
    }

    final wifiIp = (await _networkInfo.getWifiIP())?.trim() ?? '';
    if (_isUsableIpv4(wifiIp)) {
      targets.add(_fallbackBroadcastForIp(wifiIp));
    }

    final wifiGateway = (await _networkInfo.getWifiGatewayIP())?.trim() ?? '';
    if (_isUsableIpv4(wifiGateway)) {
      // Some Android hotspot/client combinations suppress L2 broadcast but still
      // pass unicast via the gateway/host.
      targets.add(wifiGateway);
    }

    final interfaces = await _listEligibleIpv4Addresses();
    for (final endpoint in interfaces) {
      targets.add(_fallbackBroadcastForIp(endpoint.address.address));
    }

    return targets.map(InternetAddress.new).toList(growable: false);
  }

  String _fallbackBroadcastForIp(String ipAddress) {
    final parts = ipAddress.split('.');
    if (parts.length != 4) {
      return _broadcastAddress;
    }
    return '${parts[0]}.${parts[1]}.${parts[2]}.255';
  }

  void _pruneOfflineDevices() {
    final now = DateTime.now();
    final remove = <String>[];
    for (final entry in _devices.entries) {
      if (now.difference(entry.value.lastSeen) > const Duration(seconds: 10)) {
        remove.add(entry.key);
      }
    }
    for (final id in remove) {
      _devices.remove(id);
    }
    if (remove.isNotEmpty) {
      _emitDevices();
    }
  }

  void _emitDevices() {
    _devicesController.add(
      _devices.values.toList()
        ..sort((a, b) => a.deviceName.compareTo(b.deviceName)),
    );
  }

  void _normalizeCachedDevices() {
    var changed = false;
    for (final entry in _devices.entries.toList()) {
      final device = entry.value;
      final normalizedPlatform = _normalizePlatformLabel(device.platform);
      if (normalizedPlatform != device.platform) {
        _devices[entry.key] = device.copyWith(platform: normalizedPlatform);
        changed = true;
      }
    }
    if (changed) {
      _emitDevices();
    }
  }

  Future<String> getLocalIp({String? preferredPeerIp}) async {
    final normalizedPeerIp = (preferredPeerIp ?? '').trim();
    if (normalizedPeerIp.isEmpty && _cachedLocalIp != null && _lastIpCacheTime != null) {
      if (DateTime.now().difference(_lastIpCacheTime!) < const Duration(seconds: 8)) {
        return _cachedLocalIp!;
      }
    }

    final wifiIp = (await _networkInfo.getWifiIP())?.trim() ?? '';
    final interfaces = await _listEligibleIpv4Addresses();

    String result = '';
    if (_isUsableIpv4(normalizedPeerIp)) {
      final sameSubnet = interfaces
          .where((endpoint) {
            return _same24Subnet(endpoint.address.address, normalizedPeerIp);
          })
          .toList(growable: false);
      if (sameSubnet.isNotEmpty) {
        sameSubnet.sort(_compareIpv4Endpoints);
        result = sameSubnet.first.address.address;
      }
    }

    if (result.isEmpty && _isUsableIpv4(wifiIp)) {
      bool found = false;
      for (final endpoint in interfaces) {
        if (endpoint.address.address == wifiIp) {
          result = endpoint.address.address;
          found = true;
          break;
        }
      }
      if (!found) {
        result = wifiIp;
      }
    }

    if (result.isEmpty) {
      if (interfaces.isEmpty) {
        result = '';
      } else {
        interfaces.sort(_compareIpv4Endpoints);
        result = interfaces.first.address.address;
      }
    }

    if (normalizedPeerIp.isEmpty) {
      _cachedLocalIp = result;
      _lastIpCacheTime = DateTime.now();
    }
    return result;
  }

  /// Returns all eligible local IPv4 addresses, sorted by preference
  /// (Wi-Fi > Ethernet > others). Useful for binding servers that should be
  /// reachable on every active network adapter.
  Future<List<String>> getAllLocalIps() async {
    final interfaces = await _listEligibleIpv4Addresses();
    if (interfaces.isEmpty) {
      return const <String>[];
    }
    interfaces.sort(_compareIpv4Endpoints);
    return interfaces.map((e) => e.address.address).toList(growable: false);
  }

  Future<void> randomizeBaseName() async {
    _deviceBaseName = _defaultBaseName();
    await _saveIdentity();
    await _announce();
    if (!Platform.isWindows && _socket != null) {
      await _mdnsSub?.cancel();
      _mdnsSub = null;
      await _mdnsDiscovery?.stop();
      _mdnsDiscovery = null;
      await _mdnsBroadcast?.stop();
      _mdnsBroadcast = null;
      await _startMdns();
    }
  }

  static String _defaultBaseName() {
    const first = [
      'Fine',
      'Swift',
      'Nova',
      'Bold',
      'Quick',
      'Bright',
      'Silent',
      'Turbo',
    ];
    const second = [
      'Grape',
      'Comet',
      'Falcon',
      'Wave',
      'Pine',
      'Orbit',
      'Pixel',
      'River',
    ];
    final random = Random.secure();
    final a = first[random.nextInt(first.length)];
    final b = second[random.nextInt(second.length)];
    return '$a $b';
  }

  static int _randomNumber() => Random.secure().nextInt(9000) + 1000;

  static String? _normalizeBaseName(String? raw) {
    if (raw == null) {
      return null;
    }
    final stripped = raw.trim().replaceAll(RegExp(r'\s+#\d+$'), '');
    if (stripped.isEmpty) {
      return null;
    }
    return stripped;
  }

  static String _normalizeManufacturer(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return '';
    }
    return text.length > 40 ? text.substring(0, 40) : text;
  }

  DeviceType _detectType() {
    if (kIsWeb) {
      return DeviceType.web;
    }
    if (Platform.isIOS) {
      if (_manufacturerTag.toLowerCase().contains('ipad')) {
        return DeviceType.tablet;
      }
      return DeviceType.phone;
    }
    if (Platform.isAndroid) {
      final lower = _manufacturerTag.toLowerCase();
      if (lower.contains('tablet') ||
          lower.contains('pad') ||
          lower.contains('tab')) {
        return DeviceType.tablet;
      }
      return DeviceType.phone;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      return DeviceType.phone;
    }
    return DeviceType.desktop;
  }

  String _detectPlatformTag() {
    if (kIsWeb) {
      return _normalizePlatformLabel('Web');
    }
    if (Platform.isAndroid) {
      return _normalizePlatformLabel('Android');
    }
    if (Platform.isIOS) {
      return _normalizePlatformLabel(
        _manufacturerTag.toLowerCase().contains('ipad') ? 'iPadOS' : 'iOS',
      );
    }
    if (Platform.isWindows) {
      return _normalizePlatformLabel('Windows');
    }
    if (Platform.isMacOS) {
      return _normalizePlatformLabel('macOS');
    }
    if (Platform.isLinux) {
      return _normalizePlatformLabel('Linux');
    }
    return _normalizePlatformLabel('PC');
  }

  String _normalizePlatformLabel(String raw) {
    final value = raw.trim();
    final lower = value.toLowerCase();
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

  Future<void> dispose() async {
    _announceTimer?.cancel();
    _pruneTimer?.cancel();
    await _socketSub?.cancel();
    await _mdnsSub?.cancel();
    await _mdnsDiscovery?.stop();
    await _mdnsBroadcast?.stop();
    _socket?.close();
    await _devicesController.close();
  }

  Future<void> _loadIdentity() async {
    if (_identityLoaded) {
      return;
    }
    _identityLoaded = true;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final file = File(
        '${docs.path}${Platform.pathSeparator}$_identityFileName',
      );
      if (!await file.exists()) {
        _deviceNumber = _randomNumber();
        _manufacturerTag = await _detectManufacturerTag();
        _cpuArchitectureTag = await _detectCpuArchitectureTag();
        _deviceId = const Uuid().v4();
        await _saveIdentity();
        return;
      }

      final payload =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final storedBase = _normalizeBaseName(payload['baseName']?.toString());
      final storedNumber = int.tryParse(payload['number']?.toString() ?? '');
      final storedManufacturer = _normalizeManufacturer(
        payload['manufacturer']?.toString() ?? '',
      );
      final storedDeviceId = (payload['deviceId']?.toString() ?? '').trim();
      if (storedBase != null) {
        _deviceBaseName = storedBase;
      }
      if (storedNumber != null &&
          storedNumber >= 1000 &&
          storedNumber <= 9999) {
        _deviceNumber = storedNumber;
      } else {
        _deviceNumber = _randomNumber();
      }
      _manufacturerTag = storedManufacturer;
      if (_manufacturerTag.isEmpty) {
        _manufacturerTag = await _detectManufacturerTag();
      }
      _cpuArchitectureTag = await _detectCpuArchitectureTag();
      _deviceId = storedDeviceId.isNotEmpty
          ? storedDeviceId
          : const Uuid().v4();
      await _saveIdentity();
    } catch (_) {
      _deviceNumber = _randomNumber();
      _manufacturerTag = await _detectManufacturerTag();
      _cpuArchitectureTag = await _detectCpuArchitectureTag();
      _deviceId = const Uuid().v4();
      await _saveIdentity();
    }
  }

  Future<void> _saveIdentity() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final file = File(
        '${docs.path}${Platform.pathSeparator}$_identityFileName',
      );
      await file.writeAsString(
        jsonEncode({
          'baseName': _deviceBaseName,
          'number': _deviceNumber,
          'manufacturer': _manufacturerTag,
          'deviceId': _deviceId,
        }),
      );
    } catch (_) {}
  }

  Future<String> _detectManufacturerTag() async {
    try {
      if (kIsWeb) {
        return 'Web';
      }
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        return _canonicalManufacturerTag([
          info.brand.trim(),
          info.manufacturer.trim(),
          info.model.trim(),
        ], fallback: 'Android');
      }
      if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        final model = info.model.trim().toLowerCase();
        if (model.contains('ipad')) {
          return 'iPad';
        }
        return 'iPhone';
      }
      if (Platform.isWindows) {
        return 'Windows';
      }
      if (Platform.isMacOS) {
        return 'Mac';
      }
      if (Platform.isLinux) {
        return 'Linux';
      }
      if (Platform.isFuchsia) {
        return 'PC';
      }
    } catch (_) {}
    return 'PC';
  }

  Future<String> _detectCpuArchitectureTag() async {
    try {
      if (kIsWeb || !Platform.isAndroid) {
        return '';
      }

      final info = await _deviceInfo.androidInfo;
      final abis = info.supportedAbis;
      if (abis.isNotEmpty) {
        return abis.join(', ');
      }

      // Fallback for older/limited metadata.
      final fallback = info.supported32BitAbis;
      if (fallback.isNotEmpty) {
        return fallback.join(', ');
      }
    } catch (_) {}
    return '';
  }

  Future<void> _refreshTlsFingerprintAndCertificate() async {
    if (_tlsCertificateFingerprint.isNotEmpty && _tlsCertificatePem.isNotEmpty) {
      return;
    }
    try {
      _tlsCertificatePem = await _tlsCertificates.readCertificatePem(
        commonName: _tlsCertCommonName,
        subjectAlternativeNames: _tlsCertSans,
      );
      _tlsCertificateFingerprint = _tlsCertificates
          .readCertificateSha256FingerprintFromPem(_tlsCertificatePem);
    } catch (_) {
      _tlsCertificateFingerprint = '';
      _tlsCertificatePem = '';
    }
  }

  Future<List<int>?> _buildPresencePacket({
    required String transport,
    String? preferredPeerIp,
  }) async {
    final ipAddress = await getLocalIp(preferredPeerIp: preferredPeerIp);
    if (ipAddress.isEmpty) {
      return null;
    }

    await _refreshTlsFingerprintAndCertificate();
    if (_tlsCertificateFingerprint.isEmpty) {
      return null;
    }

    final device = DeviceModel(
      deviceId: _deviceId,
      deviceName: deviceName,
      manufacturer: _manufacturerTag,
      platform: platformTag,
      ipAddress: ipAddress,
      deviceType: _detectType(),
      isOnline: true,
      lastSeen: DateTime.now(),
      tlsCertificateSha256: _tlsCertificateFingerprint,
    );

    final timestampMs = DateTime.now().millisecondsSinceEpoch;
    final nonce = const Uuid().v4();
    return utf8.encode(
      jsonEncode({
        'kind': 'dropnet_presence',
        'transport': transport,
        'payload': {
          ...device.toJson(),
          'pairingModeEnabled': _pairingModeEnabled,
        },
        'security': {'version': 1, 'timestampMs': timestampMs, 'nonce': nonce},
      }),
    );
  }

  Future<List<_Ipv4Endpoint>> _listEligibleIpv4Addresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    final results = <_Ipv4Endpoint>[];
    for (final iface in interfaces) {
      for (final address in iface.addresses) {
        final value = address.address.trim();
        if (!_isUsableIpv4(value) || address.isLoopback) {
          continue;
        }
        results.add(_Ipv4Endpoint(interfaceName: iface.name, address: address));
      }
    }
    return results;
  }

  bool _shouldReplyToPresence({
    required Map<String, dynamic> packet,
    required DeviceModel? previous,
    required String senderAddress,
    required DateTime seenAt,
  }) {
    final transport = (packet['transport']?.toString() ?? '').trim();
    if (transport == _presenceTransportReply) {
      return false;
    }
    if (!_isUsableIpv4(senderAddress)) {
      return false;
    }
    if (previous == null) {
      return true;
    }
    if (!previous.isOnline) {
      return true;
    }
    if (previous.ipAddress != senderAddress) {
      return true;
    }
    return seenAt.difference(previous.lastSeen) > const Duration(seconds: 6);
  }

  int _compareIpv4Endpoints(_Ipv4Endpoint left, _Ipv4Endpoint right) {
    return _scoreIpv4Endpoint(right).compareTo(_scoreIpv4Endpoint(left));
  }

  int _scoreIpv4Endpoint(_Ipv4Endpoint endpoint) {
    final lowerName = endpoint.interfaceName.toLowerCase();
    var score = 0;
    if (lowerName.contains('hotspot') || lowerName.contains('wi-fi direct')) {
      score += 500;
    }
    if (lowerName.contains('wi-fi') ||
        lowerName.contains('wifi') ||
        lowerName.contains('wireless') ||
        lowerName.contains('wlan')) {
      score += 300;
    }
    if (lowerName.contains('ethernet')) {
      score += 200;
    }
    if (_isPrivateIpv4(endpoint.address.address)) {
      score += 100;
    }
    return score;
  }

  bool _isUsableIpv4(String value) {
    if (value.isEmpty || value == '0.0.0.0') {
      return false;
    }
    final address = InternetAddress.tryParse(value);
    if (address == null || address.type != InternetAddressType.IPv4) {
      return false;
    }
    return !address.isLoopback && !_isLinkLocalIpv4(value);
  }

  bool _isPrivateIpv4(String value) {
    final octets = _parseIpv4Octets(value);
    if (octets == null) {
      return false;
    }
    return octets[0] == 10 ||
        (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) ||
        (octets[0] == 192 && octets[1] == 168);
  }

  bool _isLinkLocalIpv4(String value) {
    final octets = _parseIpv4Octets(value);
    if (octets == null) {
      return false;
    }
    return octets[0] == 169 && octets[1] == 254;
  }

  bool _same24Subnet(String left, String right) {
    final leftOctets = _parseIpv4Octets(left);
    final rightOctets = _parseIpv4Octets(right);
    if (leftOctets == null || rightOctets == null) {
      return false;
    }
    return leftOctets[0] == rightOctets[0] &&
        leftOctets[1] == rightOctets[1] &&
        leftOctets[2] == rightOctets[2];
  }

  List<int>? _parseIpv4Octets(String value) {
    final parts = value.split('.');
    if (parts.length != 4) {
      return null;
    }
    final octets = <int>[];
    for (final part in parts) {
      final octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255) {
        return null;
      }
      octets.add(octet);
    }
    return octets;
  }

  bool _parseBoolish(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    final text = (value?.toString() ?? '').trim().toLowerCase();
    return text == '1' || text == 'true' || text == 'yes' || text == 'on';
  }

  bool _isPresenceSecurityValid({
    required Map<String, dynamic> payload,
    required Map<String, dynamic> parsedPacket,
  }) {
    final security = (parsedPacket['security'] as Map?)
        ?.cast<String, dynamic>();
    if (security == null) {
      return false;
    }

    final timestampMs = (security['timestampMs'] as num?)?.toInt() ?? 0;
    final nonce = (security['nonce']?.toString() ?? '').trim();
    final certificatePem = (security['certificatePem']?.toString() ?? '')
        .trim();
    final signature = (security['signature']?.toString() ?? '').trim();
    if (timestampMs <= 0 || nonce.isEmpty) {
      return false;
    }

    final signedAt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final now = DateTime.now();
    final skew = now.difference(signedAt).abs();
    if (skew > _presenceMaxClockSkew) {
      return false;
    }

    final deviceId = (payload['deviceId']?.toString() ?? '').trim();
    final expectedFingerprint =
        (payload['tlsCertificateSha256']?.toString() ?? '')
            .trim()
            .toLowerCase();
    if (deviceId.isEmpty || expectedFingerprint.isEmpty) {
      return false;
    }

    final nonceKey = '$deviceId|$nonce';
    if (!_rememberPresenceNonce(nonceKey, now)) {
      return false;
    }

    if (certificatePem.isEmpty || signature.isEmpty) {
      // Compact presence packets omit certificate/signature to keep UDP payload
      // within common MTU limits for reliable LAN broadcast discovery.
      return true;
    }

    final actualFingerprint = _tlsCertificates
        .readCertificateSha256FingerprintFromPem(certificatePem)
        .trim()
        .toLowerCase();
    if (!_constantTimeEquals(actualFingerprint, expectedFingerprint)) {
      return false;
    }

    final signedPayload = _buildSignedPresencePayload(
      payload: payload,
      timestampMs: timestampMs,
      nonce: nonce,
    );
    return _tlsCertificates.verifyPayloadSha256SignatureFromCertificate(
      payload: signedPayload,
      signatureBase64Url: signature,
      certificatePem: certificatePem,
    );
  }

  String _buildSignedPresencePayload({
    required Map<String, dynamic> payload,
    required int timestampMs,
    required String nonce,
  }) {
    final canonicalPayload = <String, dynamic>{
      'deviceId': (payload['deviceId']?.toString() ?? '').trim(),
      'deviceName': (payload['deviceName']?.toString() ?? '').trim(),
      'manufacturer': (payload['manufacturer']?.toString() ?? '').trim(),
      'platform': (payload['platform']?.toString() ?? '').trim(),
      'ipAddress': (payload['ipAddress']?.toString() ?? '').trim(),
      'deviceType': (payload['deviceType']?.toString() ?? '').trim(),
      'pairingModeEnabled': _parseBoolish(payload['pairingModeEnabled']),
      'tlsCertificateSha256':
          (payload['tlsCertificateSha256']?.toString() ?? '')
              .trim()
              .toLowerCase(),
    };

    return jsonEncode({
      'payload': canonicalPayload,
      'timestampMs': timestampMs,
      'nonce': nonce.trim(),
    });
  }

  bool _rememberPresenceNonce(String nonceKey, DateTime now) {
    _recentPresenceNonces.removeWhere(
      (_, seenAt) => now.difference(seenAt) > _nonceRetentionWindow,
    );
    if (_recentPresenceNonces.containsKey(nonceKey)) {
      return false;
    }
    _recentPresenceNonces[nonceKey] = now;
    return true;
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) {
      return false;
    }

    var diff = 0;
    for (var index = 0; index < a.length; index++) {
      diff |= a.codeUnitAt(index) ^ b.codeUnitAt(index);
    }
    return diff == 0;
  }

  String _canonicalManufacturerTag(
    Iterable<String> values, {
    required String fallback,
  }) {
    final joined = values
        .where((value) => value.trim().isNotEmpty)
        .join(' ')
        .toLowerCase();
    if (joined.isEmpty) {
      return fallback;
    }

    if (joined.contains('samsung')) return 'Samsung';
    if (joined.contains('nothing')) return 'Nothing';
    if (joined.contains('iqoo')) return 'iQOO';
    if (joined.contains('vivo')) return 'vivo';
    if (joined.contains('oppo')) return 'OPPO';
    if (joined.contains('oneplus') || joined.contains('one plus')) {
      return 'OnePlus';
    }
    if (joined.contains('redmi')) return 'Redmi';
    if (joined.contains('poco')) return 'POCO';
    if (joined.contains('xiaomi') || joined.contains('mi ')) return 'Xiaomi';
    if (joined.contains('realme')) return 'realme';
    if (joined.contains('google') || joined.contains('pixel')) return 'Pixel';
    if (joined.contains('motorola') || joined.contains('moto')) {
      return 'Motorola';
    }
    if (joined.contains('huawei')) return 'Huawei';
    if (joined.contains('honor')) return 'Honor';
    if (joined.contains('sony')) return 'Sony';
    if (joined.contains('asus')) return 'ASUS';
    if (joined.contains('nokia')) return 'Nokia';
    if (joined.contains('lenovo')) return 'Lenovo';
    if (joined.contains('apple') || joined.contains('iphone')) return 'iPhone';
    if (joined.contains('ipad')) return 'iPad';

    final first = values
        .map((value) => value.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => fallback);
    return _normalizeManufacturer(first);
  }
}

class _Ipv4Endpoint {
  const _Ipv4Endpoint({required this.interfaceName, required this.address});

  final String interfaceName;
  final InternetAddress address;
}
