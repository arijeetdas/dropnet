import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/device_model.dart';
import '../../models/transfer_model.dart';
import '../platform/media_store_service.dart';
import '../platform/share_intent_service.dart';
import '../platform/android_saf_service.dart';
import '../networking/discovery_service.dart';
import '../networking/ftp_service.dart';
import '../networking/temporary_link_share_service.dart';
import '../networking/tcp_transfer_service.dart';
import '../networking/web_server_service.dart';

class AppState {
  const AppState({
    required this.devices,
    required this.activeTransfers,
    required this.history,
    required this.ftpState,
    required this.webState,
    required this.downloadDirectory,
    required this.pendingIncomingRequests,
    required this.themeMode,
    required this.themeSeed,
    required this.useSystemAccent,
    required this.localDeviceName,
    required this.localDeviceManufacturer,
    required this.localDevicePlatform,
    required this.localDeviceBaseName,
    required this.localDeviceNumber,
    required this.localIp,
    required this.pendingWebPeerRequests,
    required this.connectedWebPeers,
    required this.pendingWebIncomingUploads,
    required this.tempLinkShare,
    required this.transferSessionItems,
    required this.transferSessionActive,
    required this.pendingSharedFilePaths,
    required this.saveMediaToGallery,
    required this.ftpAutoRandomizeCredentials,
    required this.ftpSavedUsername,
    required this.ftpSavedPassword,
    required this.ftpPreferredStorageRoot,
    required this.ftpSafTreeUris,
  });

  final List<DeviceModel> devices;
  final List<TransferModel> activeTransfers;
  final List<TransferHistoryEntry> history;
  final FtpServerState ftpState;
  final WebShareState webState;
  final String downloadDirectory;
  final List<IncomingTransferRequest> pendingIncomingRequests;
  final ThemeMode themeMode;
  final Color themeSeed;
  final bool useSystemAccent;
  final String localDeviceName;
  final String localDeviceManufacturer;
  final String localDevicePlatform;
  final String localDeviceBaseName;
  final int localDeviceNumber;
  final String localIp;
  final List<WebPeerConnectRequest> pendingWebPeerRequests;
  final List<WebPeer> connectedWebPeers;
  final List<WebIncomingUploadRequest> pendingWebIncomingUploads;
  final TemporaryLinkShareState tempLinkShare;
  final List<TransferModel> transferSessionItems;
  final bool transferSessionActive;
  final List<String> pendingSharedFilePaths;
  final bool saveMediaToGallery;
  final bool ftpAutoRandomizeCredentials;
  final String ftpSavedUsername;
  final String ftpSavedPassword;
  final String ftpPreferredStorageRoot;
  final List<String> ftpSafTreeUris;

  static AppState initial() => AppState(
        devices: const [],
        activeTransfers: const [],
        history: const [],
        ftpState: FtpServerState.initial(),
        webState: WebShareState.initial(),
        downloadDirectory: '',
        pendingIncomingRequests: const [],
        themeMode: ThemeMode.system,
        themeSeed: Colors.indigo,
        useSystemAccent: true,
        localDeviceName: '',
        localDeviceManufacturer: '',
        localDevicePlatform: '',
        localDeviceBaseName: '',
        localDeviceNumber: 0,
        localIp: '',
        pendingWebPeerRequests: const [],
        connectedWebPeers: const [],
        pendingWebIncomingUploads: const [],
        tempLinkShare: TemporaryLinkShareState.initial(),
        transferSessionItems: const [],
        transferSessionActive: false,
        pendingSharedFilePaths: const [],
        saveMediaToGallery: true,
        ftpAutoRandomizeCredentials: false,
        ftpSavedUsername: 'dropnet',
        ftpSavedPassword: 'dropnet123',
        ftpPreferredStorageRoot: '',
        ftpSafTreeUris: const <String>[],
      );

  AppState copyWith({
    List<DeviceModel>? devices,
    List<TransferModel>? activeTransfers,
    List<TransferHistoryEntry>? history,
    FtpServerState? ftpState,
    WebShareState? webState,
    String? downloadDirectory,
    List<IncomingTransferRequest>? pendingIncomingRequests,
    ThemeMode? themeMode,
    Color? themeSeed,
    bool? useSystemAccent,
    String? localDeviceName,
    String? localDeviceManufacturer,
    String? localDevicePlatform,
    String? localDeviceBaseName,
    int? localDeviceNumber,
    String? localIp,
    List<WebPeerConnectRequest>? pendingWebPeerRequests,
    List<WebPeer>? connectedWebPeers,
    List<WebIncomingUploadRequest>? pendingWebIncomingUploads,
    TemporaryLinkShareState? tempLinkShare,
    List<TransferModel>? transferSessionItems,
    bool? transferSessionActive,
    List<String>? pendingSharedFilePaths,
    bool? saveMediaToGallery,
    bool? ftpAutoRandomizeCredentials,
    String? ftpSavedUsername,
    String? ftpSavedPassword,
    String? ftpPreferredStorageRoot,
    List<String>? ftpSafTreeUris,
  }) {
    return AppState(
      devices: devices ?? this.devices,
      activeTransfers: activeTransfers ?? this.activeTransfers,
      history: history ?? this.history,
      ftpState: ftpState ?? this.ftpState,
      webState: webState ?? this.webState,
      downloadDirectory: downloadDirectory ?? this.downloadDirectory,
      pendingIncomingRequests: pendingIncomingRequests ?? this.pendingIncomingRequests,
      themeMode: themeMode ?? this.themeMode,
      themeSeed: themeSeed ?? this.themeSeed,
      useSystemAccent: useSystemAccent ?? this.useSystemAccent,
      localDeviceName: localDeviceName ?? this.localDeviceName,
      localDeviceManufacturer: localDeviceManufacturer ?? this.localDeviceManufacturer,
      localDevicePlatform: localDevicePlatform ?? this.localDevicePlatform,
      localDeviceBaseName: localDeviceBaseName ?? this.localDeviceBaseName,
      localDeviceNumber: localDeviceNumber ?? this.localDeviceNumber,
      localIp: localIp ?? this.localIp,
      pendingWebPeerRequests: pendingWebPeerRequests ?? this.pendingWebPeerRequests,
      connectedWebPeers: connectedWebPeers ?? this.connectedWebPeers,
      pendingWebIncomingUploads: pendingWebIncomingUploads ?? this.pendingWebIncomingUploads,
      tempLinkShare: tempLinkShare ?? this.tempLinkShare,
      transferSessionItems: transferSessionItems ?? this.transferSessionItems,
      transferSessionActive: transferSessionActive ?? this.transferSessionActive,
      pendingSharedFilePaths: pendingSharedFilePaths ?? this.pendingSharedFilePaths,
      saveMediaToGallery: saveMediaToGallery ?? this.saveMediaToGallery,
      ftpAutoRandomizeCredentials: ftpAutoRandomizeCredentials ?? this.ftpAutoRandomizeCredentials,
      ftpSavedUsername: ftpSavedUsername ?? this.ftpSavedUsername,
      ftpSavedPassword: ftpSavedPassword ?? this.ftpSavedPassword,
      ftpPreferredStorageRoot: ftpPreferredStorageRoot ?? this.ftpPreferredStorageRoot,
      ftpSafTreeUris: ftpSafTreeUris ?? this.ftpSafTreeUris,
    );
  }
}

final discoveryServiceProvider = Provider<DiscoveryService>((ref) {
  final service = DiscoveryService();
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

final tcpTransferServiceProvider = Provider<TcpTransferService>((ref) {
  final service = TcpTransferService();
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

final ftpServiceProvider = Provider<FtpService>((ref) {
  final service = FtpService(safService: ref.watch(androidSafServiceProvider));
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

final androidSafServiceProvider = Provider<AndroidSafService>((ref) {
  return AndroidSafService();
});

final webServerServiceProvider = Provider<WebServerService>((ref) {
  final service = WebServerService();
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

final temporaryLinkShareServiceProvider = Provider<TemporaryLinkShareService>((ref) {
  final service = TemporaryLinkShareService();
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

final shareIntentServiceProvider = Provider<ShareIntentService>((ref) {
  final service = ShareIntentService();
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

final mediaStoreServiceProvider = Provider<MediaStoreService>((ref) {
  return const MediaStoreService();
});

final appControllerProvider = StateNotifierProvider<AppController, AppState>((ref) {
  return AppController(
    discovery: ref.watch(discoveryServiceProvider),
    transfer: ref.watch(tcpTransferServiceProvider),
    ftp: ref.watch(ftpServiceProvider),
    web: ref.watch(webServerServiceProvider),
    tempShare: ref.watch(temporaryLinkShareServiceProvider),
    shareIntent: ref.watch(shareIntentServiceProvider),
    mediaStore: ref.watch(mediaStoreServiceProvider),
  );
});

class AppController extends StateNotifier<AppState> {
  AppController({
    required DiscoveryService discovery,
    required TcpTransferService transfer,
    required FtpService ftp,
    required WebServerService web,
    required TemporaryLinkShareService tempShare,
    required ShareIntentService shareIntent,
    required MediaStoreService mediaStore,
  })  : _discovery = discovery,
        _transfer = transfer,
        _ftp = ftp,
        _web = web,
        _tempShare = tempShare,
      _shareIntent = shareIntent,
      _mediaStore = mediaStore,
        super(AppState.initial());

  final DiscoveryService _discovery;
  final TcpTransferService _transfer;
  final FtpService _ftp;
  final WebServerService _web;
  final TemporaryLinkShareService _tempShare;
  final ShareIntentService _shareIntent;
  final MediaStoreService _mediaStore;
  SharedPreferences? _prefs;

  static const _themeModeKey = 'settings.themeMode';
  static const _themeSeedKey = 'settings.themeSeed';
  static const _useSystemAccentKey = 'settings.useSystemAccent';
  static const _downloadDirectoryKey = 'settings.downloadDirectory';
  static const _saveMediaToGalleryKey = 'settings.saveMediaToGallery';
  static const _ftpAutoRandomizeCredentialsKey = 'settings.ftpAutoRandomizeCredentials';
  static const _ftpSavedUsernameKey = 'settings.ftpSavedUsername';
  static const _ftpSavedPasswordKey = 'settings.ftpSavedPassword';
  static const _ftpPreferredStorageRootKey = 'settings.ftpPreferredStorageRoot';
  static const _ftpSafTreeUrisKey = 'settings.ftpSafTreeUris';
  static const _historyKey = 'history.entries';

  StreamSubscription<List<DeviceModel>>? _devicesSub;
  StreamSubscription<List<TransferModel>>? _activeSub;
  StreamSubscription<TransferModel>? _completedTransferSub;
  StreamSubscription<List<TransferHistoryEntry>>? _historySub;
  StreamSubscription<List<IncomingTransferRequest>>? _incomingSub;
  StreamSubscription<FtpServerState>? _ftpSub;
  StreamSubscription<WebShareState>? _webSub;
  StreamSubscription<List<WebPeerConnectRequest>>? _webPeerReqSub;
  StreamSubscription<List<WebPeer>>? _webPeerSub;
  StreamSubscription<List<WebIncomingUploadRequest>>? _webIncomingUploadSub;
  StreamSubscription<List<TransferHistoryEntry>>? _webHistorySub;
  StreamSubscription<TemporaryLinkShareState>? _tempShareSub;
  StreamSubscription<List<String>>? _sharedFilesSub;

  List<TransferHistoryEntry> _tcpHistory = const [];
  List<TransferHistoryEntry> _webHistory = const [];
  List<TransferHistoryEntry> _persistedHistory = const [];
  final Map<String, TransferModel> _transferSessionMap = <String, TransferModel>{};

  Future<void> bootstrap() async {
    await ensureStoragePermission();
    _prefs ??= await SharedPreferences.getInstance();
    final defaultDownloadDir = await _resolveDownloadDirectory();
    final restoredDownloadDir = _prefs!.getString(_downloadDirectoryKey);
    final downloadDir = await _resolveDownloadDirectory(preferred: restoredDownloadDir ?? defaultDownloadDir);
    final restoredThemeMode = _themeModeFromName(_prefs!.getString(_themeModeKey)) ?? ThemeMode.system;
    final restoredUseSystemAccent = _prefs!.getBool(_useSystemAccentKey) ?? true;
    final restoredThemeSeedValue = _prefs!.getInt(_themeSeedKey) ?? Colors.indigo.toARGB32();
    final restoredSaveMediaToGallery = _prefs!.getBool(_saveMediaToGalleryKey) ?? true;
    final restoredFtpAutoRandomizeCredentials = _prefs!.getBool(_ftpAutoRandomizeCredentialsKey) ?? false;
    final restoredFtpSavedUsername = (_prefs!.getString(_ftpSavedUsernameKey) ?? 'dropnet').trim();
    final restoredFtpSavedPassword = (_prefs!.getString(_ftpSavedPasswordKey) ?? 'dropnet123').trim();
    final restoredFtpPreferredStorageRoot = (_prefs!.getString(_ftpPreferredStorageRootKey) ?? '').trim();
    final restoredFtpSafTreeUris = (_prefs!.getStringList(_ftpSafTreeUrisKey) ?? const <String>[])
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
    _persistedHistory = _restoreHistory(_prefs!.getStringList(_historyKey) ?? const <String>[]);
    final localIp = await _discovery.getLocalIp();
    await _shareIntent.initialize();
    final initialShared = await _shareIntent.consumePendingSharedFiles();
    state = state.copyWith(
      downloadDirectory: downloadDir,
      themeMode: restoredThemeMode,
      useSystemAccent: restoredUseSystemAccent,
      themeSeed: Color(restoredThemeSeedValue),
      localDeviceName: _discovery.deviceName,
      localDeviceManufacturer: _discovery.manufacturerTag,
      localDevicePlatform: _discovery.platformTag,
      localDeviceBaseName: _discovery.deviceBaseName,
      localDeviceNumber: _discovery.deviceNumber,
      localIp: localIp,
      history: _persistedHistory,
      saveMediaToGallery: restoredSaveMediaToGallery,
      pendingSharedFilePaths: initialShared,
      ftpAutoRandomizeCredentials: restoredFtpAutoRandomizeCredentials,
      ftpSavedUsername: restoredFtpSavedUsername.isEmpty ? 'dropnet' : restoredFtpSavedUsername,
      ftpSavedPassword: restoredFtpSavedPassword.isEmpty ? 'dropnet123' : restoredFtpSavedPassword,
      ftpPreferredStorageRoot: restoredFtpPreferredStorageRoot,
      ftpSafTreeUris: restoredFtpSafTreeUris,
    );

    await _discovery.start();
    await _discovery.updateDeviceNumber(1000 + Random().nextInt(9000));
    state = state.copyWith(
      localDeviceName: _discovery.deviceName,
      localDeviceManufacturer: _discovery.manufacturerTag,
      localDevicePlatform: _discovery.platformTag,
      localDeviceBaseName: _discovery.deviceBaseName,
      localDeviceNumber: _discovery.deviceNumber,
    );
    await _transfer.startReceiver(saveDirectory: downloadDir);

    _devicesSub ??= _discovery.devicesStream.listen((devices) {
      state = state.copyWith(devices: devices);
    });

    _activeSub ??= _transfer.activeTransfersStream.listen((activeTransfers) {
      if (activeTransfers.isNotEmpty && !state.transferSessionActive) {
        _transferSessionMap.clear();
        for (final transfer in activeTransfers) {
          _transferSessionMap[transfer.id] = transfer;
        }
        state = state.copyWith(
          activeTransfers: activeTransfers,
          transferSessionActive: true,
          transferSessionItems: _sortedTransferSessionItems(),
        );
        return;
      }

      if (state.transferSessionActive) {
        for (final transfer in activeTransfers) {
          _transferSessionMap[transfer.id] = transfer;
        }
      }

      state = state.copyWith(
        activeTransfers: activeTransfers,
        transferSessionItems: state.transferSessionActive ? _sortedTransferSessionItems() : state.transferSessionItems,
      );
    });

    _completedTransferSub ??= _transfer.completedTransfersStream.listen((completedTransfer) {
      if (!state.transferSessionActive && state.activeTransfers.isEmpty) {
        _transferSessionMap.clear();
        state = state.copyWith(transferSessionActive: true);
      }
      _transferSessionMap[completedTransfer.id] = completedTransfer;
      state = state.copyWith(transferSessionItems: _sortedTransferSessionItems());
      if (completedTransfer.direction == TransferDirection.received &&
          completedTransfer.status == TransferStatus.completed &&
          state.saveMediaToGallery) {
        final localPath = completedTransfer.localPath;
        if (localPath != null && localPath.trim().isNotEmpty) {
          unawaited(_mediaStore.saveToGallery(localPath));
        }
      }
    });

    _historySub ??= _transfer.historyStream.listen((history) {
      _tcpHistory = history;
      _emitCombinedHistory();
    });

    _incomingSub ??= _transfer.incomingRequestsStream.listen((requests) {
      state = state.copyWith(pendingIncomingRequests: requests);
    });

    _ftpSub ??= _ftp.stateStream.listen((ftpState) {
      state = state.copyWith(ftpState: ftpState);
    });

    _webSub ??= _web.stateStream.listen((webState) {
      state = state.copyWith(webState: webState);
    });

    _webPeerReqSub ??= _web.pendingPeerRequestsStream.listen((requests) {
      state = state.copyWith(pendingWebPeerRequests: requests);
    });

    _webPeerSub ??= _web.connectedPeersStream.listen((peers) {
      state = state.copyWith(connectedWebPeers: peers);
    });

    _webIncomingUploadSub ??= _web.incomingUploadRequestsStream.listen((requests) {
      state = state.copyWith(pendingWebIncomingUploads: requests);
    });

    _webHistorySub ??= _web.historyStream.listen((history) {
      _webHistory = history;
      _emitCombinedHistory();
    });

    _tempShareSub ??= _tempShare.stateStream.listen((tempShareState) {
      state = state.copyWith(tempLinkShare: tempShareState);
    });

    _sharedFilesSub ??= _shareIntent.sharedFilesStream.listen((paths) {
      if (paths.isEmpty) {
        return;
      }
      final merged = <String>{...state.pendingSharedFilePaths, ...paths}.toList(growable: false);
      state = state.copyWith(pendingSharedFilePaths: merged);
    });
  }

  Future<void> sendFiles(DeviceModel target, List<String> filePaths) {
    return _transfer.sendFiles(target: target, filePaths: filePaths, senderDeviceName: _taggedLocalName());
  }

  Future<bool> ensureStoragePermission({
    bool openSettingsIfDenied = false,
    String? targetPath,
  }) async {
    if (kIsWeb) {
      return true;
    }

    if (Platform.isAndroid) {
      final normalizedTarget = (targetPath ?? '').trim();
      final needsSharedStorageAccess = normalizedTarget.startsWith('/storage/');

      var manageStatus = await Permission.manageExternalStorage.status;
      if (!manageStatus.isGranted) {
        manageStatus = await Permission.manageExternalStorage.request();
      }
      if (manageStatus.isGranted) {
        return true;
      }

      if (needsSharedStorageAccess) {
        if (openSettingsIfDenied &&
            (manageStatus.isPermanentlyDenied || manageStatus.isRestricted || manageStatus.isDenied)) {
          await openAppSettings();
        }
        return false;
      }

      var storageStatus = await Permission.storage.status;
      if (!storageStatus.isGranted) {
        storageStatus = await Permission.storage.request();
      }
      if (storageStatus.isGranted) {
        return true;
      }

      if (openSettingsIfDenied &&
          (manageStatus.isPermanentlyDenied ||
              storageStatus.isPermanentlyDenied ||
              manageStatus.isRestricted ||
              storageStatus.isRestricted)) {
        await openAppSettings();
      }
      return false;
    }

    if (Platform.isIOS) {
      var photosStatus = await Permission.photos.status;
      if (!photosStatus.isGranted && !photosStatus.isLimited) {
        photosStatus = await Permission.photos.request();
      }
      final granted = photosStatus.isGranted || photosStatus.isLimited;
      if (!granted && openSettingsIfDenied && photosStatus.isPermanentlyDenied) {
        await openAppSettings();
      }
      return granted;
    }

    return true;
  }

  Future<void> refreshNearbyDevices() => _discovery.refreshNow();

  Future<int> stageFilesForWebPeers({required List<String> filePaths, required List<String> peerIds}) {
    return _web.offerFilesToPeers(filePaths: filePaths, peerIds: peerIds);
  }

  void cancelTransfer(String id) {
    _transfer.cancelTransfer(id);
  }

  void approveIncomingRequest(String id) {
    _transfer.approveIncomingRequest(id);
  }

  void rejectIncomingRequest(String id) {
    _transfer.rejectIncomingRequest(id);
  }

  Future<void> startFtp({
    required List<String> sharedRoots,
    required bool anonymous,
    required bool readOnly,
    required String username,
    required String password,
    int port = 2121,
  }) async {
    final resolvedIp = await _discovery.getLocalIp();
    final preferredHost = resolvedIp.isEmpty ? state.localIp : resolvedIp;
    await _ftp.start(
      sharedDirectories: sharedRoots,
      anonymous: anonymous,
      readOnly: readOnly,
      username: username,
      password: password,
      port: port,
      preferredHost: preferredHost,
    );
    state = state.copyWith(ftpState: _ftp.currentState);
  }

  Future<void> stopFtp() async {
    await _ftp.stop();
    state = state.copyWith(ftpState: _ftp.currentState);
  }

  RandomCredentials generateRandomFtpCredentials() {
    return _ftp.generateRandomCredentials();
  }

  Future<void> startWebShare({int port = 8080}) {
    return _web.start(
      rootDirectory: state.downloadDirectory,
      hostDeviceName: _taggedLocalName(),
      port: port,
    );
  }

  Future<void> stopWebShare() => _web.stop();

  Future<void> startTemporaryLinkShare({
    required List<String> filePaths,
    Duration? ttl,
  }) async {
    final resolvedIp = await _discovery.getLocalIp();
    final hostIp = resolvedIp.isEmpty ? state.localIp : resolvedIp;
    if (hostIp.isEmpty) {
      throw StateError('Local IP is unavailable. Connect to a LAN/Wi-Fi network and try again.');
    }
    await _tempShare.start(
      filePaths: filePaths,
      host: hostIp,
      deviceName: _taggedLocalName(),
      platformLabel: state.localDevicePlatform.isEmpty ? 'Unknown' : state.localDevicePlatform,
      idSuffix: '#${state.localDeviceNumber}',
      ttl: ttl,
    );
    state = state.copyWith(
      localIp: hostIp,
      tempLinkShare: _tempShare.currentState,
    );
  }

  Future<void> stopTemporaryLinkShare() async {
    await _tempShare.stop();
    state = state.copyWith(tempLinkShare: _tempShare.currentState);
  }

  void approveWebPeerRequest(String id) {
    _web.approvePeerRequest(id);
  }

  void rejectWebPeerRequest(String id) {
    _web.rejectPeerRequest(id);
  }

  void approveWebIncomingUpload(String id) {
    _web.approveIncomingUploadRequest(id);
  }

  void rejectWebIncomingUpload(String id) {
    _web.rejectIncomingUploadRequest(id);
  }

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    unawaited(_saveThemeMode(mode));
  }

  void setThemeSeed(Color color) {
    state = state.copyWith(themeSeed: color, useSystemAccent: false);
    unawaited(_saveThemeSeed(color));
    unawaited(_saveUseSystemAccent(false));
  }

  void setUseSystemAccent(bool value) {
    state = state.copyWith(useSystemAccent: value);
    unawaited(_saveUseSystemAccent(value));
  }

  Future<void> setDownloadDirectory(String path) async {
    final target = Directory(path);
    await target.create(recursive: true);
    _transfer.updateSaveDirectory(target.path);
    state = state.copyWith(downloadDirectory: target.path);
    await _saveDownloadDirectory(target.path);
  }

  void setSaveMediaToGallery(bool value) {
    state = state.copyWith(saveMediaToGallery: value);
    unawaited(_saveSaveMediaToGallery(value));
  }

  void setFtpAutoRandomizeCredentials(bool value) {
    state = state.copyWith(ftpAutoRandomizeCredentials: value);
    unawaited(_saveFtpAutoRandomizeCredentials(value));
  }

  void setFtpSavedCredentials({required String username, required String password}) {
    final normalizedUsername = username.trim().isEmpty ? 'dropnet' : username.trim();
    final normalizedPassword = password.trim().isEmpty ? 'dropnet123' : password.trim();
    state = state.copyWith(
      ftpSavedUsername: normalizedUsername,
      ftpSavedPassword: normalizedPassword,
    );
    unawaited(_saveFtpSavedCredentials(username: normalizedUsername, password: normalizedPassword));
  }

  void setFtpPreferredStorageRoot(String path) {
    final normalized = path.trim();
    state = state.copyWith(ftpPreferredStorageRoot: normalized);
    unawaited(_saveFtpPreferredStorageRoot(normalized));
  }

  void setFtpSafTreeUris(List<String> uris) {
    final normalized = uris.map((uri) => uri.trim()).where((uri) => uri.isNotEmpty).toList(growable: false);
    state = state.copyWith(ftpSafTreeUris: normalized);
    unawaited(_saveFtpSafTreeUris(normalized));
  }

  List<String> consumePendingSharedFiles() {
    final pending = state.pendingSharedFilePaths;
    if (pending.isEmpty) {
      return const <String>[];
    }
    state = state.copyWith(pendingSharedFilePaths: const <String>[]);
    return pending;
  }

  Future<void> setDeviceName(String name) async {
    await _discovery.updateDeviceName(name);
    state = state.copyWith(
      localDeviceName: _discovery.deviceName,
      localDeviceManufacturer: _discovery.manufacturerTag,
      localDevicePlatform: _discovery.platformTag,
      localDeviceBaseName: _discovery.deviceBaseName,
      localDeviceNumber: _discovery.deviceNumber,
    );
  }

  Future<void> setDeviceManufacturer(String value) async {
    await _discovery.updateManufacturerTag(value);
    state = state.copyWith(
      localDeviceName: _discovery.deviceName,
      localDeviceManufacturer: _discovery.manufacturerTag,
      localDevicePlatform: _discovery.platformTag,
      localDeviceBaseName: _discovery.deviceBaseName,
      localDeviceNumber: _discovery.deviceNumber,
    );
  }

  Future<void> resetDeviceManufacturerToAuto() async {
    await _discovery.resetManufacturerTagToAuto();
    state = state.copyWith(
      localDeviceName: _discovery.deviceName,
      localDeviceManufacturer: _discovery.manufacturerTag,
      localDevicePlatform: _discovery.platformTag,
      localDeviceBaseName: _discovery.deviceBaseName,
      localDeviceNumber: _discovery.deviceNumber,
    );
  }

  Future<void> setDeviceNumber(int value) async {
    await _discovery.updateDeviceNumber(value);
    state = state.copyWith(
      localDeviceName: _discovery.deviceName,
      localDeviceManufacturer: _discovery.manufacturerTag,
      localDevicePlatform: _discovery.platformTag,
      localDeviceBaseName: _discovery.deviceBaseName,
      localDeviceNumber: _discovery.deviceNumber,
    );
  }

  Future<void> randomizeDeviceName() async {
    await _discovery.randomizeBaseName();
    state = state.copyWith(
      localDeviceName: _discovery.deviceName,
      localDeviceManufacturer: _discovery.manufacturerTag,
      localDeviceBaseName: _discovery.deviceBaseName,
      localDeviceNumber: _discovery.deviceNumber,
    );
  }

  Future<void> shutdownNetworkServices() async {
    await _tempShare.stop();
    await _web.stop();
    await _ftp.stop();
    await _transfer.stopReceiver();
  }

  Future<void> clearAllHistory() async {
    await _transfer.clearHistory();
    await _web.clearHistory();
    _tcpHistory = const [];
    _webHistory = const [];
    _persistedHistory = const [];
    await _saveHistory(const <TransferHistoryEntry>[]);
    _emitCombinedHistory();
  }

  void closeTransferSession() {
    _transferSessionMap.clear();
    state = state.copyWith(
      transferSessionActive: false,
      transferSessionItems: const <TransferModel>[],
    );
  }

  Future<void> removeHistoryEntry(TransferHistoryEntry entry) async {
    await _transfer.removeHistoryEntry(entry);
    await _web.removeHistoryEntry(entry);
    _persistedHistory = _persistedHistory.where((item) => !_sameHistoryEntry(item, entry)).toList(growable: false);
    await _saveHistory(_persistedHistory);
    _emitCombinedHistory();
  }

  Map<String, dynamic> analytics() {
    final sent = state.history.where((entry) => entry.status == TransferStatus.completed).length;
    final totalBytes = state.history.fold<int>(0, (sum, item) => sum + item.size);
    final avgSpeed = state.history.isEmpty
        ? 0.0
        : state.history.fold<double>(
              0,
              (sum, item) => sum + (item.size / item.duration.inMilliseconds.clamp(1, 1 << 30) * 1000),
            ) /
            state.history.length;

    final byDevice = <String, int>{};
    for (final item in state.history) {
      byDevice[item.deviceName] = (byDevice[item.deviceName] ?? 0) + 1;
    }
    String mostActive = 'N/A';
    var max = 0;
    byDevice.forEach((key, value) {
      if (value > max) {
        max = value;
        mostActive = key;
      }
    });

    return {
      'totalFiles': state.history.length,
      'totalSentOrReceived': sent,
      'totalBytes': totalBytes,
      'avgSpeed': avgSpeed,
      'mostActive': mostActive,
    };
  }

  List<TransferModel> _sortedTransferSessionItems() {
    final items = _transferSessionMap.values.toList(growable: false)
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return items;
  }

  void _emitCombinedHistory() {
    final all = <TransferHistoryEntry>[..._persistedHistory, ..._tcpHistory, ..._webHistory];
    final deduped = <TransferHistoryEntry>[];
    for (final entry in all) {
      final exists = deduped.any((item) => _sameHistoryEntry(item, entry));
      if (!exists) {
        deduped.add(entry);
      }
    }
    deduped.sort((a, b) => b.date.compareTo(a.date));
    _persistedHistory = deduped;
    unawaited(_saveHistory(deduped));
    state = state.copyWith(history: deduped);
  }

  bool _sameHistoryEntry(TransferHistoryEntry a, TransferHistoryEntry b) {
    return a.fileName == b.fileName &&
        a.size == b.size &&
        a.date == b.date &&
        a.deviceName == b.deviceName &&
        a.status == b.status &&
        a.duration == b.duration &&
        a.direction == b.direction;
  }

  List<TransferHistoryEntry> _restoreHistory(List<String> encodedItems) {
    final restored = <TransferHistoryEntry>[];
    for (final item in encodedItems) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is Map<String, dynamic>) {
          final entry = TransferHistoryEntry.fromJson(decoded);
          if (entry != null) {
            restored.add(entry);
          }
        }
      } catch (_) {}
    }
    restored.sort((a, b) => b.date.compareTo(a.date));
    return restored;
  }

  Future<void> _saveHistory(List<TransferHistoryEntry> history) async {
    _prefs ??= await SharedPreferences.getInstance();
    final encoded = history.map((entry) => jsonEncode(entry.toJson())).toList(growable: false);
    await _prefs!.setStringList(_historyKey, encoded);
  }

  String _taggedLocalName() {
    final tag = state.localDeviceManufacturer.trim();
    final parts = <String>[state.localDeviceName];
    if (tag.isNotEmpty) {
      parts.add(tag);
    }
    return parts.join(' • ');
  }

  Future<void> _saveThemeMode(ThemeMode mode) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_themeModeKey, mode.name);
  }

  Future<void> _saveThemeSeed(Color color) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(_themeSeedKey, color.toARGB32());
  }

  Future<void> _saveUseSystemAccent(bool value) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_useSystemAccentKey, value);
  }

  Future<void> _saveDownloadDirectory(String path) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_downloadDirectoryKey, path);
  }

  Future<void> _saveSaveMediaToGallery(bool value) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_saveMediaToGalleryKey, value);
  }

  Future<void> _saveFtpAutoRandomizeCredentials(bool value) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_ftpAutoRandomizeCredentialsKey, value);
  }

  Future<void> _saveFtpSavedCredentials({required String username, required String password}) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_ftpSavedUsernameKey, username);
    await _prefs!.setString(_ftpSavedPasswordKey, password);
  }

  Future<void> _saveFtpPreferredStorageRoot(String path) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_ftpPreferredStorageRootKey, path);
  }

  Future<void> _saveFtpSafTreeUris(List<String> uris) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setStringList(_ftpSafTreeUrisKey, uris);
  }

  Future<String> _resolveDownloadDirectory({String? preferred}) async {
    if (preferred != null && preferred.trim().isNotEmpty) {
      try {
        final preferredDir = Directory(preferred);
        await preferredDir.create(recursive: true);
        return preferredDir.path;
      } catch (_) {}
    }
    if (Platform.isAndroid || Platform.isIOS) {
      final dir = await getApplicationDocumentsDirectory();
      final target = Directory('${dir.path}${Platform.pathSeparator}DropNet');
      await target.create(recursive: true);
      return target.path;
    }
    Directory dir;
    try {
      dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    } on UnsupportedError {
      dir = await getApplicationDocumentsDirectory();
    }
    final target = Directory('${dir.path}${Platform.pathSeparator}DropNet');
    await target.create(recursive: true);
    return target.path;
  }

  ThemeMode? _themeModeFromName(String? value) {
    if (value == null) {
      return null;
    }
    for (final mode in ThemeMode.values) {
      if (mode.name == value) {
        return mode;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _devicesSub?.cancel();
    _activeSub?.cancel();
    _completedTransferSub?.cancel();
    _historySub?.cancel();
    _incomingSub?.cancel();
    _ftpSub?.cancel();
    _webSub?.cancel();
    _webPeerReqSub?.cancel();
    _webPeerSub?.cancel();
    _webIncomingUploadSub?.cancel();
    _webHistorySub?.cancel();
    _tempShareSub?.cancel();
    _sharedFilesSub?.cancel();
    super.dispose();
  }
}
