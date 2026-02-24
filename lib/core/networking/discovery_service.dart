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

class DiscoveryService {
  DiscoveryService({String? deviceName})
      : _deviceNumber = 0,
        _deviceBaseName = _normalizeBaseName(deviceName) ?? _defaultBaseName();

  static const _discoveryPort = 45454;
  static const _broadcastAddress = '255.255.255.255';
  static const _identityFileName = 'dropnet_identity.json';

  String _deviceBaseName;
  int _deviceNumber;
  String _manufacturerTag = '';
  String _deviceId = '';
  final _networkInfo = NetworkInfo();
  final _deviceInfo = DeviceInfoPlugin();
  final _devicesController = StreamController<List<DeviceModel>>.broadcast();
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

  Stream<List<DeviceModel>> get devicesStream => _devicesController.stream;
  String get deviceName => '$_deviceBaseName #$_deviceNumber';
  String get manufacturerTag => _manufacturerTag;
  String get platformTag => _detectPlatformTag();
  String get deviceBaseName => _deviceBaseName;
  int get deviceNumber => _deviceNumber;
  String get deviceId => _deviceId;
  String get taggedDeviceName => _manufacturerTag.trim().isEmpty ? deviceName : '$deviceName • ${_manufacturerTag.trim()}';

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
    _announceTimer = Timer.periodic(const Duration(seconds: 3), (_) => _announce());
    _pruneTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pruneOfflineDevices());
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
    final datagram = _socket?.receive();
    if (datagram == null) {
      return;
    }

    try {
      final message = utf8.decode(datagram.data);
      final parsed = jsonDecode(message) as Map<String, dynamic>;
      if (parsed['kind'] != 'dropnet_presence') {
        return;
      }

      final incoming = DeviceModel.fromJson(parsed['payload'] as Map<String, dynamic>);
      final incomingId = incoming.deviceId.trim();
      if (incomingId.isNotEmpty && incomingId == _deviceId) {
        return;
      }

      final key = incomingId.isNotEmpty ? incomingId : datagram.address.address;
      _upsertDiscoveredDevice(
        key,
        incoming.copyWith(
        ipAddress: datagram.address.address,
        isOnline: true,
        lastSeen: DateTime.now(),
        ),
      );
    } catch (_) {}
  }

  Future<void> _announce() async {
    final ipAddress = await getLocalIp();
    if (ipAddress.isEmpty) {
      return;
    }

    final payload = {
      'kind': 'dropnet_presence',
      'payload': DeviceModel(
        deviceId: _deviceId,
        deviceName: deviceName,
        manufacturer: _manufacturerTag,
        platform: platformTag,
        ipAddress: ipAddress,
        deviceType: _detectType(),
        isOnline: true,
        lastSeen: DateTime.now(),
      ).toJson(),
    };

    final bytes = utf8.encode(jsonEncode(payload));
    final targets = await _collectBroadcastTargets();
    for (final target in targets) {
      _socket?.send(bytes, target, _discoveryPort);
    }
  }

  Future<void> _startMdns() async {
    final ipAddress = await getLocalIp();
    if (ipAddress.isEmpty) {
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
      final manufacturer = (service.attributes['manufacturer']?.toString() ?? '').trim();
      final platform = _normalizePlatformLabel((service.attributes['platform']?.toString() ?? '').trim());
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
        deviceType: DeviceType.values.firstWhere((value) => value.name == type, orElse: () => DeviceType.other),
        isOnline: true,
        lastSeen: DateTime.now(),
        ),
      );
      return;
    }
    if (event is BonsoirDiscoveryServiceLostEvent) {
      final service = event.service;
      final id = (service.attributes['deviceId']?.toString() ?? service.name).trim();
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
    final wifiIp = await _networkInfo.getWifiIP();
    if (wifiIp != null && wifiIp.isNotEmpty) {
      targets.add(_fallbackBroadcastForIp(wifiIp));
    }

    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    for (final iface in interfaces) {
      for (final address in iface.addresses) {
        if (address.isLoopback || address.type != InternetAddressType.IPv4) {
          continue;
        }
        targets.add(_fallbackBroadcastForIp(address.address));
      }
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
    _devicesController.add(_devices.values.toList()..sort((a, b) => a.deviceName.compareTo(b.deviceName)));
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

  Future<String> getLocalIp() async {
    final wifiIp = await _networkInfo.getWifiIP();
    if (wifiIp != null && wifiIp.isNotEmpty) {
      return wifiIp;
    }

    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    for (final iface in interfaces) {
      for (final address in iface.addresses) {
        if (!address.isLoopback && address.type == InternetAddressType.IPv4) {
          return address.address;
        }
      }
    }
    return '';
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
    const first = ['Fine', 'Swift', 'Nova', 'Bold', 'Quick', 'Bright', 'Silent', 'Turbo'];
    const second = ['Grape', 'Comet', 'Falcon', 'Wave', 'Pine', 'Orbit', 'Pixel', 'River'];
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
      if (lower.contains('tablet') || lower.contains('pad') || lower.contains('tab')) {
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
      return _normalizePlatformLabel(_manufacturerTag.toLowerCase().contains('ipad') ? 'iPadOS' : 'iOS');
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
      final file = File('${docs.path}${Platform.pathSeparator}$_identityFileName');
      if (!await file.exists()) {
        _deviceNumber = _randomNumber();
        _manufacturerTag = await _detectManufacturerTag();
        _deviceId = const Uuid().v4();
        await _saveIdentity();
        return;
      }

      final payload = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final storedBase = _normalizeBaseName(payload['baseName']?.toString());
      final storedNumber = int.tryParse(payload['number']?.toString() ?? '');
      final storedManufacturer = _normalizeManufacturer(payload['manufacturer']?.toString() ?? '');
      final storedDeviceId = (payload['deviceId']?.toString() ?? '').trim();
      if (storedBase != null) {
        _deviceBaseName = storedBase;
      }
      if (storedNumber != null && storedNumber >= 1000 && storedNumber <= 9999) {
        _deviceNumber = storedNumber;
      } else {
        _deviceNumber = _randomNumber();
      }
      _manufacturerTag = storedManufacturer;
      if (_manufacturerTag.isEmpty) {
        _manufacturerTag = await _detectManufacturerTag();
      }
      _deviceId = storedDeviceId.isNotEmpty ? storedDeviceId : const Uuid().v4();
      await _saveIdentity();
    } catch (_) {
      _deviceNumber = _randomNumber();
      _manufacturerTag = await _detectManufacturerTag();
      _deviceId = const Uuid().v4();
      await _saveIdentity();
    }
  }

  Future<void> _saveIdentity() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final file = File('${docs.path}${Platform.pathSeparator}$_identityFileName');
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
        return _canonicalManufacturerTag(
          [
            info.brand.trim(),
            info.manufacturer.trim(),
            info.model.trim(),
          ],
          fallback: 'Android',
        );
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

  String _canonicalManufacturerTag(Iterable<String> values, {required String fallback}) {
    final joined = values.where((value) => value.trim().isNotEmpty).join(' ').toLowerCase();
    if (joined.isEmpty) {
      return fallback;
    }

    if (joined.contains('samsung')) return 'Samsung';
    if (joined.contains('nothing')) return 'Nothing';
    if (joined.contains('iqoo')) return 'iQOO';
    if (joined.contains('vivo')) return 'vivo';
    if (joined.contains('oppo')) return 'OPPO';
    if (joined.contains('oneplus') || joined.contains('one plus')) return 'OnePlus';
    if (joined.contains('redmi')) return 'Redmi';
    if (joined.contains('poco')) return 'POCO';
    if (joined.contains('xiaomi') || joined.contains('mi ')) return 'Xiaomi';
    if (joined.contains('realme')) return 'realme';
    if (joined.contains('google') || joined.contains('pixel')) return 'Pixel';
    if (joined.contains('motorola') || joined.contains('moto')) return 'Motorola';
    if (joined.contains('huawei')) return 'Huawei';
    if (joined.contains('honor')) return 'Honor';
    if (joined.contains('sony')) return 'Sony';
    if (joined.contains('asus')) return 'ASUS';
    if (joined.contains('nokia')) return 'Nokia';
    if (joined.contains('lenovo')) return 'Lenovo';
    if (joined.contains('apple') || joined.contains('iphone')) return 'iPhone';
    if (joined.contains('ipad')) return 'iPad';

    final first = values.map((value) => value.trim()).firstWhere((value) => value.isNotEmpty, orElse: () => fallback);
    return _normalizeManufacturer(first);
  }
}
