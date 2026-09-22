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

  int _discoveryPort = 45454;
  int _listeningPort = 45455;
  bool _broadcastingEnabled = true;
  static const _broadcastAddress = '255.255.255.255';
  static const _presenceTransportBroadcast = 'broadcast';
  static const _presenceTransportReply = 'reply';
  static const _identityFileName = 'dropnet_identity.json';
  static const _tlsCertCommonName = 'DropNet Local';
  static const _tlsCertSans = <String>['localhost', '127.0.0.1'];
  static const Duration _presenceMaxClockSkew = Duration(seconds: 45);
  static const Duration _nonceRetentionWindow = Duration(minutes: 3);
  static const Duration _announceInterval = Duration(milliseconds: 1500);
  static const Duration _staleDeviceThreshold = Duration(milliseconds: 4500);

  String _deviceBaseName;
  int _deviceNumber;
  String _manufacturerTag = '';
  String _cpuArchitectureTag = '';
  String _deviceId = '';
  bool _pairingModeEnabled = false;
  DeviceType? _customDeviceType;
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
  bool _fullPrivateMode = false;
  bool _running = false;
  Timer? _announceTimer;
  Timer? _pruneTimer;
  final Map<String, DeviceModel> _devices = {};
  final Set<String> _manualDeviceIds = {};
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

  // start() has real async work (socket bind, mDNS setup) between the
  // "already running?" check and actually setting _socket/starting timers.
  // Two overlapping calls — e.g. the periodic background refresh landing
  // while a settings-triggered restart is still in flight — could otherwise
  // both race past that check and each bind a socket, register a duplicate
  // mDNS broadcast (surfacing as "Name (2)" once the OS's own Bonjour
  // conflict resolution renames the second one), and leave one set of
  // announce/prune timers orphaned forever. Memoizing the in-flight call
  // makes every concurrent caller await the same single run instead.
  Future<void>? _startFuture;

  Future<void> start() {
    return _startFuture ??= _startInternal().whenComplete(() {
      _startFuture = null;
    });
  }

  Future<void> _startInternal() async {
    if (kDebugMode) {
      print('[DiscoveryService] Starting service (running state: $_running, port: $_discoveryPort)');
    }
    _running = true;
    try {
      await _loadIdentity();
    } catch (e) {
      if (kDebugMode) {
        print('[DiscoveryService] Error loading identity: $e');
      }
    }

    if (_socket != null) {
      _normalizeCachedDevices();
      return;
    }

    try {
      await _bindSocket();
    } catch (e) {
      if (kDebugMode) {
        print('[DiscoveryService] Error binding socket: $e');
      }
    }

    _normalizeCachedDevices();

    if (!Platform.isWindows && _socket != null) {
      // Fire-and-forget: mDNS setup can take several real seconds (network
      // lookups, TLS cert refresh, native Bonjour startup), and it must not
      // delay the fast, simple UDP announce below, which doesn't need it.
      unawaited(
        _startMdns().catchError((e) {
          if (kDebugMode) {
            print('[DiscoveryService] Error starting mDNS: $e');
          }
        }),
      );
    }

    if (_socket != null && _running) {
      _announce();
      // Rapid announcements on startup to ensure instant detection
      unawaited(Future.delayed(const Duration(milliseconds: 500), () {
        if (_running) _announce();
      }));
      unawaited(Future.delayed(const Duration(milliseconds: 1500), () {
        if (_running) _announce();
      }));

      _announceTimer = Timer.periodic(
        _announceInterval,
        (_) {
          if (_running) _announce();
        },
      );
      _pruneTimer = Timer.periodic(
        _announceInterval,
        (_) {
          if (_running) _pruneOfflineDevices();
        },
      );
    }
  }

  void configure({int? discoveryPort, int? listeningPort, bool? broadcastingEnabled, bool? fullPrivateMode}) {
    if (discoveryPort != null) {
      _discoveryPort = discoveryPort;
    }
    if (listeningPort != null) {
      _listeningPort = listeningPort;
    }
    if (broadcastingEnabled != null) {
      _broadcastingEnabled = broadcastingEnabled;
    }
    if (fullPrivateMode != null) {
      _fullPrivateMode = fullPrivateMode;
    }
    if (kDebugMode) {
      print('[DiscoveryService] Configured: Port=$_discoveryPort, Listening=$_listeningPort, Broad=$broadcastingEnabled, Private=$_fullPrivateMode');
    }
  }

  Future<void> stop() async {
    if (kDebugMode) {
      print('[DiscoveryService] Stopping service');
    }
    _running = false;
    // Broadcast offline presence packet to let peers know we are offline immediately
    try {
      if (_socket != null && _broadcastingEnabled) {
        final packet = await _buildPresencePacket(
          transport: _presenceTransportBroadcast,
          isOnline: false,
        ).timeout(const Duration(seconds: 1));
        if (packet != null) {
          final targets = await _collectBroadcastTargets().timeout(const Duration(seconds: 1));
          for (final target in targets) {
            _socket?.send(packet, target, _discoveryPort);
          }
        }
      }
    } catch (_) {}

    _announceTimer?.cancel();
    _announceTimer = null;
    _pruneTimer?.cancel();
    _pruneTimer = null;
    await _socketSub?.cancel();
    _socketSub = null;
    await _mdnsSub?.cancel();
    _mdnsSub = null;
    if (kDebugMode) {
      if (_mdnsDiscovery != null) {
        print('[DiscoveryService] Stopping mDNS Discovery browser');
      }
    }
    try {
      await _mdnsDiscovery?.stop().timeout(const Duration(seconds: 2));
    } catch (_) {}
    _mdnsDiscovery = null;
    if (kDebugMode) {
      if (_mdnsBroadcast != null) {
        print('[DiscoveryService] Stopping mDNS Advertiser');
      }
    }
    try {
      await _mdnsBroadcast?.stop().timeout(const Duration(seconds: 2));
    } catch (_) {}
    _mdnsBroadcast = null;
    _resolvingServiceNames.clear();
    _socket?.close();
    _socket = null;
  }

  void addManualDevice(DeviceModel device) {
    final key = device.deviceId.trim().isEmpty ? device.ipAddress : device.deviceId.trim();
    _manualDeviceIds.add(key);
    _upsertDiscoveredDevice(key, device);
  }

  bool isManualDevice(DeviceModel device) {
    final key = device.deviceId.trim().isEmpty ? device.ipAddress : device.deviceId.trim();
    return _manualDeviceIds.contains(key);
  }

  void removeManualDevice(DeviceModel device) {
    final key = device.deviceId.trim().isEmpty ? device.ipAddress : device.deviceId.trim();
    _manualDeviceIds.remove(key);
    _devices.remove(key);
    _emitDevices();
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

  Future<void> updateCustomDeviceType(DeviceType? type) async {
    if (_customDeviceType == type) {
      return;
    }
    _customDeviceType = type;

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
    try {
      if (_socket == null) {
        await start().timeout(const Duration(seconds: 2));
        return;
      }
      _normalizeCachedDevices();
      await _announce().timeout(const Duration(seconds: 1));

      // Refresh Bonsoir discovery by stopping and starting it again.
      // Skipped on iOS: tearing down NWBrowser while a DNSServiceResolve
      // callback is in flight races with bonsoir_darwin's native resolver
      // teardown and can wedge the app. The periodic mDNS browser and the
      // UDP re-announce below are enough to surface devices on refresh.
      if (!Platform.isWindows && !Platform.isIOS && _mdnsDiscovery != null) {
        try {
          await _mdnsSub?.cancel();
          _mdnsSub = null;
          await _mdnsDiscovery?.stop().timeout(const Duration(seconds: 1));
          _mdnsDiscovery = null;

          // Restart discovery
          _mdnsDiscovery = BonsoirDiscovery(type: '_dropnet._tcp');
          await _mdnsDiscovery!.initialize().timeout(const Duration(seconds: 1));
          _mdnsSub = _mdnsDiscovery!.eventStream?.listen(_onMdnsEvent);
          await _mdnsDiscovery!.start().timeout(const Duration(seconds: 1));
        } catch (_) {}
      }
    } catch (_) {}
    _pruneOfflineDevices();
  }

  Future<void> _bindSocket() async {
    if (!_running) {
      if (kDebugMode) {
        print('[DiscoveryService] Aborting socket bind: service not running');
      }
      return;
    }
    if (kDebugMode) {
      print('[DiscoveryService] Binding UDP socket on port $_discoveryPort');
    }
    try {
      RawDatagramSocket? boundSocket;
      int attempts = 0;
      while (attempts < 5 && _running) {
        try {
          boundSocket = await RawDatagramSocket.bind(
            InternetAddress.anyIPv4,
            _discoveryPort,
            reuseAddress: true,
            reusePort: !Platform.isWindows,
          );
          break;
        } catch (e) {
          attempts++;
          if (attempts >= 5) {
            rethrow;
          }
          await Future<void>.delayed(Duration(milliseconds: 200 * attempts));
        }
      }

      if (!_running) {
        boundSocket?.close();
        return;
      }

      _socket = boundSocket;
      _socket!.broadcastEnabled = true;
      _socketSub = _socket!.listen(
        _onSocketEvent,
        onError: (err) {
          if (kDebugMode) {
            print('[DiscoveryService] UDP Socket error: $err');
          }
          unawaited(_restartSocket());
        },
        onDone: () {
          if (kDebugMode) {
            print('[DiscoveryService] UDP Socket done/closed');
          }
          unawaited(_restartSocket());
        },
      );
      if (kDebugMode) {
        print('[DiscoveryService] UDP Socket bound on port $_discoveryPort (actual bound: ${_socket?.port})');
      }
    } catch (e) {
      _socket = null;
      if (kDebugMode) {
        print('[DiscoveryService] Error binding UDP socket on port $_discoveryPort: $e');
      }
    }
  }

  Future<void> _restartSocket() async {
    if (_restartingSocket || !_running) {
      if (kDebugMode) {
        print('[DiscoveryService] Aborting socket restart: restarting=$_restartingSocket, running=$_running');
      }
      return;
    }
    _restartingSocket = true;
    if (kDebugMode) {
      print('[DiscoveryService] Restarting UDP socket');
    }
    try {
      await _socketSub?.cancel();
      _socketSub = null;
      _socket?.close();
      _socket = null;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!_running) {
        if (kDebugMode) {
          print('[DiscoveryService] Aborting socket restart post-delay: service stopped');
        }
        return;
      }
      await _bindSocket();
      if (_socket != null && _running) {
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

      // Validate socket port matches configured port to filter out stale loops
      final localBoundPort = _socket?.port;
      if (_fullPrivateMode) {
        if (localBoundPort != _discoveryPort) {
          if (kDebugMode) {
            print('[DiscoveryService] UDP Ignoring packet on stale/wrong bound port: $localBoundPort (expected $_discoveryPort)');
          }
          continue;
        }
      } else {
        if (localBoundPort != 45454) {
          if (kDebugMode) {
            print('[DiscoveryService] UDP Ignoring packet on non-default port in default mode: $localBoundPort');
          }
          continue;
        }
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

        // Validate private mode status and ports
        final peerPrivateMode = _parseBoolish(payloadMap['fullPrivateModeEnabled']);
        final peerDiscoveryPort = (payloadMap['discoveryPort'] as num?)?.toInt();
        final peerListeningPort = (payloadMap['port'] as num?)?.toInt();

        if (peerPrivateMode != _fullPrivateMode) {
          if (kDebugMode) {
            print('[DiscoveryService] UDP Ignoring packet due to private mode mismatch. Peer: $peerPrivateMode, Local: $_fullPrivateMode');
          }
          continue;
        }

        if (_fullPrivateMode) {
          if (peerDiscoveryPort != _discoveryPort || peerListeningPort != _listeningPort) {
            if (kDebugMode) {
              print('[DiscoveryService] UDP Ignoring packet in Private Mode due to port mismatch. '
                  'Peer Discovery: $peerDiscoveryPort (expected $_discoveryPort), '
                  'Peer Listening: $peerListeningPort (expected $_listeningPort)');
            }
            continue;
          }
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

        if (!incoming.isOnline) {
          if (_devices.containsKey(key)) {
            _devices.remove(key);
            _emitDevices();
          }
          continue;
        }

        final previous = _devices[key];
        _upsertDiscoveredDevice(
          key,
          incoming.copyWith(
            ipAddress: datagram.address.address,
            isOnline: true,
            lastSeen: seenAt,
          ),
        );

        final replyPort = peerDiscoveryPort ?? datagram.port;

        if (_shouldReplyToPresence(
          packet: parsed,
          previous: previous,
          senderAddress: datagram.address.address,
          seenAt: seenAt,
        )) {
          unawaited(_replyToPresence(datagram.address, replyPort));
        }
      } catch (_) {}
    }
  }

  Future<void> _announce() async {
    if (!_broadcastingEnabled) {
      return;
    }
    final packet = await _buildPresencePacket(
      transport: _presenceTransportBroadcast,
    );
    if (packet == null) {
      return;
    }

    final targets = await _collectBroadcastTargets();
    for (final target in targets) {
      if (kDebugMode) {
        print('[DiscoveryService] Broadcasting presence packet to ${target.address}:$_discoveryPort');
      }
      _socket?.send(packet, target, _discoveryPort);
    }
  }

  Future<void> _replyToPresence(InternetAddress target, int targetPort) async {
    if (!_broadcastingEnabled) {
      return;
    }
    final packet = await _buildPresencePacket(
      transport: _presenceTransportReply,
      preferredPeerIp: target.address,
    );
    if (packet == null) {
      return;
    }
    if (kDebugMode) {
      print('[DiscoveryService] Replying to presence at ${target.address}:$targetPort');
    }
    _socket?.send(packet, target, targetPort);
  }

  Future<void> _startMdns() async {
    if (!_broadcastingEnabled || _fullPrivateMode) {
      if (kDebugMode) {
        print('[DiscoveryService] Skipping mDNS startup (broadcastingEnabled: $_broadcastingEnabled, fullPrivateMode: $_fullPrivateMode)');
      }
      return;
    }
    if (kDebugMode) {
      print('[DiscoveryService] Starting mDNS Advertiser & Discovery on port $_listeningPort');
    }
    try {
      final ipAddress = await getLocalIp().timeout(const Duration(seconds: 3));
      if (ipAddress.isEmpty) {
        return;
      }

      await _refreshTlsFingerprintAndCertificate().timeout(const Duration(seconds: 5));
      if (_tlsCertificateFingerprint.isEmpty) {
        return;
      }

      final service = BonsoirService(
        name: deviceName,
        type: '_dropnet._tcp',
        port: _listeningPort,
        attributes: {
          'deviceId': _deviceId,
          'deviceType': _detectType().name,
          'manufacturer': _manufacturerTag,
          'platform': platformTag,
          'tlsCertificateSha256': _tlsCertificateFingerprint,
          'pairingModeEnabled': _pairingModeEnabled ? '1' : '0',
          'fullPrivateModeEnabled': _fullPrivateMode ? '1' : '0',
          'discoveryPort': _discoveryPort.toString(),
        },
      );

      _mdnsBroadcast = BonsoirBroadcast(service: service);
      await _mdnsBroadcast!.initialize().timeout(const Duration(seconds: 3));
      await _mdnsBroadcast!.start().timeout(const Duration(seconds: 3));
      if (kDebugMode) {
        print('[DiscoveryService] mDNS Advertiser started for $deviceName (_dropnet._tcp)');
      }

      _mdnsDiscovery = BonsoirDiscovery(type: '_dropnet._tcp');
      await _mdnsDiscovery!.initialize().timeout(const Duration(seconds: 3));
      _mdnsSub = _mdnsDiscovery!.eventStream?.listen(_onMdnsEvent);
      await _mdnsDiscovery!.start().timeout(const Duration(seconds: 3));
      if (kDebugMode) {
        print('[DiscoveryService] mDNS Discovery browser started');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[DiscoveryService] Error starting mDNS: $e');
      }
    }
  }

  // mDNS re-announces a service periodically at the protocol level, so
  // "found" events keep refiring for services we've already seen — not just
  // once. Calling resolve() again while a previous resolve for that same
  // service is still in flight can wedge bonsoir_darwin's shared native
  // resolver on iOS/macOS (the same class of race already documented above
  // for tearing it down mid-resolve), after which it silently stops
  // delivering ResolvedEvents entirely — the device list goes empty and
  // never recovers on its own. Tracking in-flight resolves by service name
  // and skipping a redundant resolve() call avoids ever triggering it.
  final Set<String> _resolvingServiceNames = {};

  void _onMdnsEvent(BonsoirDiscoveryEvent event) {
    if (event is BonsoirDiscoveryServiceFoundEvent) {
      final name = event.service.name;
      if (!_resolvingServiceNames.add(name)) {
        return;
      }
      // Safety net: if a resolve never fires a Resolved or Lost event at all
      // (silent native failure, not just a slow one), don't block that
      // service from ever being retried again.
      unawaited(
        Future<void>.delayed(const Duration(seconds: 10), () {
          _resolvingServiceNames.remove(name);
        }),
      );
      event.service.resolve(_mdnsDiscovery!.serviceResolver);
      return;
    }
    if (event is BonsoirDiscoveryServiceResolvedEvent) {
      final service = event.service;
      _resolvingServiceNames.remove(service.name);
      if (service.attributes['deviceId'] == _deviceId) {
        return;
      }
      _handleResolvedServiceAsync(service);
      return;
    }
    if (event is BonsoirDiscoveryServiceLostEvent) {
      final service = event.service;
      _resolvingServiceNames.remove(service.name);
      final id = (service.attributes['deviceId']?.toString() ?? service.name)
          .trim();
      _devices.remove(id);
      _emitDevices();
    }
  }

  Future<void> _handleResolvedServiceAsync(dynamic service) async {
    String host = service.host ?? '';
    try {
      final dynamic dynService = service;
      final List<dynamic>? addresses = dynService.hostAddresses;
      if (addresses != null && addresses.isNotEmpty) {
        final ip = addresses.firstWhere(
          (addr) => !addr.toString().contains(':'),
          orElse: () => addresses.first,
        ).toString().trim();
        if (ip.isNotEmpty) {
          host = ip;
        }
      } else {
        final hostAddr = dynService.hostAddress?.toString().trim();
        if (hostAddr != null && hostAddr.isNotEmpty) {
          host = hostAddr;
        }
      }
    } catch (_) {}

    if (host.isEmpty) {
      return;
    }

    if (host.contains('.local') || RegExp(r'[a-zA-Z]').hasMatch(host)) {
      try {
        final cleanHost = host.replaceAll(RegExp(r'\.+$'), '');
        final addresses = await InternetAddress.lookup(cleanHost).timeout(
          const Duration(milliseconds: 1500),
        );
        for (final addr in addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            host = addr.address;
            break;
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('[DiscoveryService] DNS lookup failed for $host: $e');
        }
      }
    }

    // Validate private mode and custom ports on resolved mDNS service
    final incomingPrivate = _parseBoolish(service.attributes['fullPrivateModeEnabled']);
    final incomingDiscoveryPort = int.tryParse(service.attributes['discoveryPort']?.toString() ?? '');
    
    if (incomingPrivate != _fullPrivateMode) {
      if (kDebugMode) {
        print('[DiscoveryService] Ignoring resolved mDNS service due to private mode mismatch. Peer: $incomingPrivate, Local: $_fullPrivateMode');
      }
      return;
    }
    
    if (_fullPrivateMode) {
      if (incomingDiscoveryPort != _discoveryPort || service.port != _listeningPort) {
        if (kDebugMode) {
          print('[DiscoveryService] Ignoring resolved mDNS service in Private Mode due to port mismatch. '
              'Peer Discovery: $incomingDiscoveryPort (expected $_discoveryPort), '
              'Peer Listening: ${service.port} (expected $_listeningPort)');
        }
        return;
      }
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
        port: service.port,
      ),
    );
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

    final results = await Future.wait<Object?>([
      _networkInfo.getWifiBroadcast().catchError((_) => null),
      _networkInfo.getWifiIP().catchError((_) => null),
      _networkInfo.getWifiGatewayIP().catchError((_) => null),
      _listEligibleIpv4Addresses(),
    ]);

    final wifiBroadcast = (results[0] as String?)?.trim() ?? '';
    if (_isUsableIpv4(wifiBroadcast)) {
      targets.add(wifiBroadcast);
    }

    final wifiIp = (results[1] as String?)?.trim() ?? '';
    if (_isUsableIpv4(wifiIp)) {
      targets.add(_fallbackBroadcastForIp(wifiIp));
    }

    final wifiGateway = (results[2] as String?)?.trim() ?? '';
    if (_isUsableIpv4(wifiGateway)) {
      // Some Android hotspot/client combinations suppress L2 broadcast but still
      // pass unicast via the gateway/host.
      targets.add(wifiGateway);
    }

    final interfaces = results[3] as List<_Ipv4Endpoint>;
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
      // Never prune manually-added devices — they persist until app restart
      // or they are discovered via normal UDP/mDNS (which keeps lastSeen fresh)
      if (_manualDeviceIds.contains(entry.key)) {
        continue;
      }
      if (now.difference(entry.value.lastSeen) > _staleDeviceThreshold) {
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

    String wifiIp = '';
    try {
      wifiIp = (await _networkInfo.getWifiIP())?.trim() ?? '';
    } catch (_) {}
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
    if (_customDeviceType != null) {
      return _customDeviceType!;
    }
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
    if (Platform.isLinux) {
      return DeviceType.laptop;
    }
    if (Platform.isMacOS) {
      final model = _manufacturerTag.toLowerCase();
      if (model.contains('macbook')) {
        return DeviceType.laptop;
      }
      return DeviceType.desktop;
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
    _running = false;
    _announceTimer?.cancel();
    _announceTimer = null;
    _pruneTimer?.cancel();
    _pruneTimer = null;
    await _socketSub?.cancel();
    _socketSub = null;
    await _mdnsSub?.cancel();
    _mdnsSub = null;
    await _mdnsDiscovery?.stop();
    _mdnsDiscovery = null;
    await _mdnsBroadcast?.stop();
    _mdnsBroadcast = null;
    _socket?.close();
    _socket = null;
    await _devicesController.close();
  }

  Future<void> _loadIdentity() async {
    if (_identityLoaded) {
      return;
    }
    _identityLoaded = true;
    try {
      final file = await _identityFile();
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

  /// Resolves the identity file, migrating it out of the app's Documents
  /// directory if found there from an older version. On iOS/macOS,
  /// Documents is what UIFileSharingEnabled/"Open With" expose to the user
  /// (intentionally, for received files) — internal identity data doesn't
  /// belong alongside that, so it now lives in Application Support instead,
  /// which is inside the sandbox but never user-browsable.
  Future<File> _identityFile() async {
    final support = await getApplicationSupportDirectory();
    await support.create(recursive: true);
    final target = File(
      '${support.path}${Platform.pathSeparator}$_identityFileName',
    );
    if (await target.exists()) {
      return target;
    }
    try {
      final docs = await getApplicationDocumentsDirectory();
      final legacy = File(
        '${docs.path}${Platform.pathSeparator}$_identityFileName',
      );
      if (await legacy.exists()) {
        await legacy.copy(target.path);
        await legacy.delete();
      }
    } catch (_) {
      // No legacy file, or migration failed — target simply won't exist yet
      // and a fresh identity will be generated, same as a first launch.
    }
    return target;
  }

  Future<void> _saveIdentity() async {
    try {
      final file = await _identityFile();
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
        return 'Apple';
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
    bool isOnline = true,
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
      isOnline: isOnline,
      lastSeen: DateTime.now(),
      tlsCertificateSha256: _tlsCertificateFingerprint,
      port: _listeningPort,
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
          'fullPrivateModeEnabled': _fullPrivateMode,
          'discoveryPort': _discoveryPort,
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
    return seenAt.difference(previous.lastSeen) > _staleDeviceThreshold;
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
