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
import '../../models/favorite_peer_model.dart';
import '../../models/trusted_peer_model.dart';
import '../../models/transfer_model.dart';
import '../platform/media_store_service.dart';
import '../platform/share_intent_service.dart';
import '../platform/android_saf_service.dart';
import '../networking/discovery_service.dart';
import '../networking/temporary_link_share_service.dart';
import '../networking/tcp_transfer_service.dart';
import '../utils/transfer_visuals.dart';
import '../networking/web_server_service.dart';

bool isTransferPreviewEligible(TransferModel transfer) {
  if (transfer.direction != TransferDirection.received ||
      transfer.status != TransferStatus.completed) {
    return false;
  }
  final sessionFileCount = transfer.sessionFileCount ?? 1;
  if (sessionFileCount != 1) {
    return false;
  }

  final localPath = transfer.localPath?.trim() ?? '';
  if (localPath.isEmpty) {
    return false;
  }

  return TransferVisuals.isTextPreviewType(localPath) ||
      TransferVisuals.supportsReceivedPreview(localPath);
}

String trustedPeerKey(String deviceId, String tlsCertificateSha256) {
  return '${deviceId.trim().toLowerCase()}|${tlsCertificateSha256.trim().toLowerCase()}';
}

bool isDeviceTrusted({
  required List<TrustedPeer> trustedPeers,
  required DeviceModel device,
}) {
  final deviceId = device.deviceId.trim();
  final fingerprint = (device.tlsCertificateSha256 ?? '').trim().toLowerCase();
  if (deviceId.isEmpty || fingerprint.isEmpty) {
    return false;
  }
  final expected = trustedPeerKey(deviceId, fingerprint);
  return trustedPeers.any(
    (peer) =>
        trustedPeerKey(peer.deviceId, peer.tlsCertificateSha256) == expected,
  );
}

enum QuickSaveMode { off, favorites, on }

class AppState {
  const AppState({
    required this.devices,
    required this.activeTransfers,
    required this.history,
    required this.webState,
    required this.downloadDirectory,
    required this.pendingIncomingRequests,
    required this.pendingPairingRequests,
    required this.themeMode,
    required this.themeSeed,
    required this.useSystemAccent,
    required this.localDeviceName,
    required this.localDeviceId,
    required this.localDeviceManufacturer,
    required this.localDevicePlatform,
    required this.localDeviceCpuArchitecture,
    required this.localDeviceBaseName,
    required this.localDeviceNumber,
    required this.localIp,
    required this.localIps,
    required this.pendingWebPeerRequests,
    required this.connectedWebPeers,
    required this.pendingWebIncomingUploads,
    required this.tempLinkShare,
    required this.transferSessionItems,
    required this.transferSessionActive,
    required this.pendingSharedFilePaths,
    required this.pendingSharedTexts,
    required this.pendingTransferPreviewTexts,
    required this.pendingTransferPreviewFiles,
    required this.pendingSystemMessages,
    required this.trustedPeers,
    required this.favoritePeers,
    required this.quickSaveMode,
    required this.quickSaveInfoDismissedModes,
    required this.saveMediaToGallery,
    required this.requirePairingCodeForDirectTransfers,
    required this.showIncomingRequestList,
    required this.maxIncomingRequests,
    required this.incomingRequestTimeoutSeconds,
  });

  final List<DeviceModel> devices;
  final List<TransferModel> activeTransfers;
  final List<TransferHistoryEntry> history;
  final WebShareState webState;
  final String downloadDirectory;
  final List<IncomingTransferRequest> pendingIncomingRequests;
  final List<IncomingPairingRequest> pendingPairingRequests;
  final ThemeMode themeMode;
  final Color themeSeed;
  final bool useSystemAccent;
  final String localDeviceName;
  final String localDeviceId;
  final String localDeviceManufacturer;
  final String localDevicePlatform;
  final String localDeviceCpuArchitecture;
  final String localDeviceBaseName;
  final int localDeviceNumber;
  final String localIp;
  /// All eligible local IPv4 addresses, sorted by preference.
  final List<String> localIps;
  final List<WebPeerConnectRequest> pendingWebPeerRequests;
  final List<WebPeer> connectedWebPeers;
  final List<WebIncomingUploadRequest> pendingWebIncomingUploads;
  final TemporaryLinkShareState tempLinkShare;
  final List<TransferModel> transferSessionItems;
  final bool transferSessionActive;
  final List<String> pendingSharedFilePaths;
  final List<String> pendingSharedTexts;
  final List<String> pendingTransferPreviewTexts;
  final List<TransferModel> pendingTransferPreviewFiles;
  final List<String> pendingSystemMessages;
  final List<TrustedPeer> trustedPeers;
  final List<FavoritePeer> favoritePeers;
  final QuickSaveMode quickSaveMode;
  final Set<QuickSaveMode> quickSaveInfoDismissedModes;
  final bool saveMediaToGallery;
  final bool requirePairingCodeForDirectTransfers;
  final bool showIncomingRequestList;
  final int maxIncomingRequests;
  final int incomingRequestTimeoutSeconds;

  static AppState initial() => AppState(
    devices: const [],
    activeTransfers: const [],
    history: const [],
    webState: WebShareState.initial(),
    downloadDirectory: '',
    pendingIncomingRequests: const [],
    pendingPairingRequests: const [],
    themeMode: ThemeMode.system,
    themeSeed: Colors.indigo,
    useSystemAccent: true,
    localDeviceName: '',
    localDeviceId: '',
    localDeviceManufacturer: '',
    localDevicePlatform: '',
    localDeviceCpuArchitecture: '',
    localDeviceBaseName: '',
    localDeviceNumber: 0,
    localIp: '',
    localIps: const [],
    pendingWebPeerRequests: const [],
    connectedWebPeers: const [],
    pendingWebIncomingUploads: const [],
    tempLinkShare: TemporaryLinkShareState.initial(),
    transferSessionItems: const [],
    transferSessionActive: false,
    pendingSharedFilePaths: const [],
    pendingSharedTexts: const [],
    pendingTransferPreviewTexts: const [],
    pendingTransferPreviewFiles: const [],
    pendingSystemMessages: const [],
    trustedPeers: const [],
    favoritePeers: const [],
    quickSaveMode: QuickSaveMode.off,
    quickSaveInfoDismissedModes: const <QuickSaveMode>{},
    saveMediaToGallery: true,
    requirePairingCodeForDirectTransfers: false,
    showIncomingRequestList: false,
    maxIncomingRequests: 5,
    incomingRequestTimeoutSeconds: 60,
  );

  AppState copyWith({
    List<DeviceModel>? devices,
    List<TransferModel>? activeTransfers,
    List<TransferHistoryEntry>? history,
    WebShareState? webState,
    String? downloadDirectory,
    List<IncomingTransferRequest>? pendingIncomingRequests,
    List<IncomingPairingRequest>? pendingPairingRequests,
    ThemeMode? themeMode,
    Color? themeSeed,
    bool? useSystemAccent,
    String? localDeviceName,
    String? localDeviceId,
    String? localDeviceManufacturer,
    String? localDevicePlatform,
    String? localDeviceCpuArchitecture,
    String? localDeviceBaseName,
    int? localDeviceNumber,
    String? localIp,
    List<String>? localIps,
    List<WebPeerConnectRequest>? pendingWebPeerRequests,
    List<WebPeer>? connectedWebPeers,
    List<WebIncomingUploadRequest>? pendingWebIncomingUploads,
    TemporaryLinkShareState? tempLinkShare,
    List<TransferModel>? transferSessionItems,
    bool? transferSessionActive,
    List<String>? pendingSharedFilePaths,
    List<String>? pendingSharedTexts,
    List<String>? pendingTransferPreviewTexts,
    List<TransferModel>? pendingTransferPreviewFiles,
    List<String>? pendingSystemMessages,
    List<TrustedPeer>? trustedPeers,
    List<FavoritePeer>? favoritePeers,
    QuickSaveMode? quickSaveMode,
    Set<QuickSaveMode>? quickSaveInfoDismissedModes,
    bool? saveMediaToGallery,
    bool? requirePairingCodeForDirectTransfers,
    bool? showIncomingRequestList,
    int? maxIncomingRequests,
    int? incomingRequestTimeoutSeconds,
  }) {
    return AppState(
      devices: devices ?? this.devices,
      activeTransfers: activeTransfers ?? this.activeTransfers,
      history: history ?? this.history,
      webState: webState ?? this.webState,
      downloadDirectory: downloadDirectory ?? this.downloadDirectory,
      pendingIncomingRequests:
          pendingIncomingRequests ?? this.pendingIncomingRequests,
      pendingPairingRequests:
          pendingPairingRequests ?? this.pendingPairingRequests,
      themeMode: themeMode ?? this.themeMode,
      themeSeed: themeSeed ?? this.themeSeed,
      useSystemAccent: useSystemAccent ?? this.useSystemAccent,
      localDeviceName: localDeviceName ?? this.localDeviceName,
      localDeviceId: localDeviceId ?? this.localDeviceId,
      localDeviceManufacturer:
          localDeviceManufacturer ?? this.localDeviceManufacturer,
      localDevicePlatform: localDevicePlatform ?? this.localDevicePlatform,
        localDeviceCpuArchitecture:
          localDeviceCpuArchitecture ?? this.localDeviceCpuArchitecture,
      localDeviceBaseName: localDeviceBaseName ?? this.localDeviceBaseName,
      localDeviceNumber: localDeviceNumber ?? this.localDeviceNumber,
      localIp: localIp ?? this.localIp,
      localIps: localIps ?? this.localIps,
      pendingWebPeerRequests:
          pendingWebPeerRequests ?? this.pendingWebPeerRequests,
      connectedWebPeers: connectedWebPeers ?? this.connectedWebPeers,
      pendingWebIncomingUploads:
          pendingWebIncomingUploads ?? this.pendingWebIncomingUploads,
      tempLinkShare: tempLinkShare ?? this.tempLinkShare,
      transferSessionItems: transferSessionItems ?? this.transferSessionItems,
      transferSessionActive:
          transferSessionActive ?? this.transferSessionActive,
      pendingSharedFilePaths:
          pendingSharedFilePaths ?? this.pendingSharedFilePaths,
      pendingSharedTexts: pendingSharedTexts ?? this.pendingSharedTexts,
      pendingTransferPreviewTexts:
          pendingTransferPreviewTexts ?? this.pendingTransferPreviewTexts,
      pendingTransferPreviewFiles:
          pendingTransferPreviewFiles ?? this.pendingTransferPreviewFiles,
      pendingSystemMessages:
          pendingSystemMessages ?? this.pendingSystemMessages,
      trustedPeers: trustedPeers ?? this.trustedPeers,
        favoritePeers: favoritePeers ?? this.favoritePeers,
        quickSaveMode: quickSaveMode ?? this.quickSaveMode,
        quickSaveInfoDismissedModes:
          quickSaveInfoDismissedModes ?? this.quickSaveInfoDismissedModes,
      saveMediaToGallery: saveMediaToGallery ?? this.saveMediaToGallery,
      requirePairingCodeForDirectTransfers:
          requirePairingCodeForDirectTransfers ??
          this.requirePairingCodeForDirectTransfers,
      showIncomingRequestList: showIncomingRequestList ?? this.showIncomingRequestList,
      maxIncomingRequests: maxIncomingRequests ?? this.maxIncomingRequests,
      incomingRequestTimeoutSeconds: incomingRequestTimeoutSeconds ?? this.incomingRequestTimeoutSeconds,
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

final temporaryLinkShareServiceProvider = Provider<TemporaryLinkShareService>((
  ref,
) {
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

final appControllerProvider = StateNotifierProvider<AppController, AppState>((
  ref,
) {
  return AppController(
    discovery: ref.watch(discoveryServiceProvider),
    transfer: ref.watch(tcpTransferServiceProvider),
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
    required WebServerService web,
    required TemporaryLinkShareService tempShare,
    required ShareIntentService shareIntent,
    required MediaStoreService mediaStore,
  }) : _discovery = discovery,
       _transfer = transfer,
       _web = web,
       _tempShare = tempShare,
       _shareIntent = shareIntent,
       _mediaStore = mediaStore,
       super(AppState.initial());

  final DiscoveryService _discovery;
  final TcpTransferService _transfer;
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
  static const _trustedPeersKey = 'security.trustedPeers';
  static const _favoritePeersKey = 'peers.favoritePeers';
  static const _historyKey = 'history.entries';
  static const _requirePairingCodeKey = 'security.requirePairingCode';
  static const _quickSaveModeKey = 'receive.quickSaveMode';
  static const _quickSaveDismissedModesKey = 'receive.quickSaveDismissedModes';
  static const _showIncomingRequestListKey = 'receive.showIncomingRequestList';
  static const _maxIncomingRequestsKey = 'receive.maxIncomingRequests';
  static const _incomingRequestTimeoutSecondsKey = 'receive.incomingRequestTimeoutSeconds';

  StreamSubscription<List<DeviceModel>>? _devicesSub;
  StreamSubscription<List<TransferModel>>? _activeSub;
  StreamSubscription<TransferModel>? _completedTransferSub;
  StreamSubscription<List<TransferHistoryEntry>>? _historySub;
  StreamSubscription<List<IncomingTransferRequest>>? _incomingSub;
  StreamSubscription<List<IncomingPairingRequest>>? _incomingPairingSub;
  StreamSubscription<List<RemoteUnpairNotice>>? _remoteUnpairSub;
  StreamSubscription<WebShareState>? _webSub;
  StreamSubscription<List<WebPeerConnectRequest>>? _webPeerReqSub;
  StreamSubscription<List<WebPeer>>? _webPeerSub;
  StreamSubscription<List<WebIncomingUploadRequest>>? _webIncomingUploadSub;
  StreamSubscription<List<TransferHistoryEntry>>? _webHistorySub;
  StreamSubscription<TemporaryLinkShareState>? _tempShareSub;
  StreamSubscription<SharedIntentPayload>? _sharedPayloadSub;

  List<TransferHistoryEntry> _tcpHistory = const [];
  List<TransferHistoryEntry> _webHistory = const [];
  List<TransferHistoryEntry> _persistedHistory = const [];
  final Map<String, TransferModel> _transferSessionMap =
      <String, TransferModel>{};
  final Set<String> _gallerySyncedPaths = <String>{};
  final Set<String> _processedRemoteUnpairNoticeIds = <String>{};
  final Set<String> _knownIncomingRequestIds = <String>{};

  Future<void> bootstrap() async {
    await ensureStoragePermission();
    _prefs ??= await SharedPreferences.getInstance();

    // Batch all SharedPreferences reads
    final restoredThemeMode =
        _themeModeFromName(_prefs!.getString(_themeModeKey)) ??
        ThemeMode.system;
    final restoredUseSystemAccent =
        _prefs!.getBool(_useSystemAccentKey) ?? true;
    final restoredThemeSeedValue =
        _prefs!.getInt(_themeSeedKey) ?? Colors.indigo.toARGB32();
    final restoredSaveMediaToGallery =
        _prefs!.getBool(_saveMediaToGalleryKey) ?? true;
    final restoredTrustedPeers = _restoreTrustedPeers(
      _prefs!.getStringList(_trustedPeersKey) ?? const <String>[],
    );
    final restoredFavoritePeers = _restoreFavoritePeers(
      _prefs!.getStringList(_favoritePeersKey) ?? const <String>[],
    );
    final restoredRequirePairingCode =
        _prefs!.getBool(_requirePairingCodeKey) ?? false;
    final restoredQuickSaveMode = _quickSaveModeFromName(
      _prefs!.getString(_quickSaveModeKey),
    );
    final restoredDismissedModes = _restoreQuickSaveDismissedModes(
      _prefs!.getStringList(_quickSaveDismissedModesKey) ?? const <String>[],
    );
    final restoredShowIncomingRequestList =
        _prefs!.getBool(_showIncomingRequestListKey) ?? false;
    final restoredMaxIncomingRequests =
        _prefs!.getInt(_maxIncomingRequestsKey) ?? 5;
    final restoredIncomingRequestTimeoutSeconds =
        _prefs!.getInt(_incomingRequestTimeoutSecondsKey) ?? 60;
    _persistedHistory = _restoreHistory(
      _prefs!.getStringList(_historyKey) ?? const <String>[],
    );

    // Parallelize async operations that don't depend on each other
    final downloadDirFuture = _resolveDownloadDirectory(
      preferred: _prefs!.getString(_downloadDirectoryKey),
    );
    final localIpFuture = _discovery.getLocalIp();
    final localIpsFuture = _discovery.getAllLocalIps();
    final shareIntentFuture = Future<void>(() async {
      await _shareIntent.initialize();
    });

    final downloadDir = await downloadDirFuture;
    final localIp = await localIpFuture;
    final localIps = await localIpsFuture;
    await shareIntentFuture;
    final initialShared = await _shareIntent.consumePendingSharedPayload();

    await _discovery.updatePairingModeEnabled(restoredRequirePairingCode);

    final effectiveQuickSaveMode = restoredRequirePairingCode
      ? QuickSaveMode.off
      : restoredQuickSaveMode;

    // Save download directory if changed
    final restoredDownloadDir = _prefs!.getString(_downloadDirectoryKey);
    if ((restoredDownloadDir ?? '').trim() != downloadDir.trim()) {
      unawaited(_saveDownloadDirectory(downloadDir));
    }

    // Update state with all settings
    state = state.copyWith(
      downloadDirectory: downloadDir,
      themeMode: restoredThemeMode,
      useSystemAccent: restoredUseSystemAccent,
      themeSeed: Color(restoredThemeSeedValue),
      localDeviceName: _discovery.deviceName,
      localDeviceId: _discovery.deviceId,
      localDeviceManufacturer: _discovery.manufacturerTag,
      localDevicePlatform: _discovery.platformTag,
      localDeviceCpuArchitecture: _discovery.cpuArchitectureTag,
      localDeviceBaseName: _discovery.deviceBaseName,
      localDeviceNumber: _discovery.deviceNumber,
      localIp: localIp,
      localIps: localIps,
      history: _persistedHistory,
      saveMediaToGallery: restoredSaveMediaToGallery,
      pendingSharedFilePaths: initialShared.filePaths,
      pendingSharedTexts: initialShared.texts,
      trustedPeers: restoredTrustedPeers,
      favoritePeers: restoredFavoritePeers,
      quickSaveMode: effectiveQuickSaveMode,
      quickSaveInfoDismissedModes: restoredDismissedModes,
      requirePairingCodeForDirectTransfers: restoredRequirePairingCode,
      showIncomingRequestList: restoredShowIncomingRequestList,
      maxIncomingRequests: restoredMaxIncomingRequests,
      incomingRequestTimeoutSeconds: restoredIncomingRequestTimeoutSeconds,
    );

    if (effectiveQuickSaveMode != restoredQuickSaveMode) {
      unawaited(_saveQuickSaveMode(effectiveQuickSaveMode));
    }

    // Parallelize discovery and transfer startup
    await Future.wait<void>([
      _discovery.start(),
      _transfer.startReceiver(saveDirectory: downloadDir),
    ]);

    // Defer device number update to avoid blocking startup
    unawaited(
      _discovery.updateDeviceNumber(1000 + Random().nextInt(9000)).then((_) {
        state = state.copyWith(
          localDeviceName: _discovery.deviceName,
          localDeviceId: _discovery.deviceId,
          localDeviceManufacturer: _discovery.manufacturerTag,
          localDevicePlatform: _discovery.platformTag,
          localDeviceCpuArchitecture: _discovery.cpuArchitectureTag,
          localDeviceBaseName: _discovery.deviceBaseName,
          localDeviceNumber: _discovery.deviceNumber,
        );
      }),
    );

    // Defer stream subscriber setup to avoid blocking app startup
    unawaited(
      Future<void>(() async {
        await Future<void>.delayed(
          Duration.zero,
        ); // Yield to allow UI to render
        _setupStreamSubscribers();
      }),
    );
  }

  void _setupStreamSubscribers() {
    _devicesSub ??= _discovery.devicesStream.listen((devices) {
      final previousFavorites = state.favoritePeers;
      final syncedFavorites = _syncFavoritePeersWithDevices(
        previousFavorites,
        devices,
      );
      state = state.copyWith(devices: devices, favoritePeers: syncedFavorites);
      if (!_sameFavoritePeerList(syncedFavorites, previousFavorites)) {
        unawaited(_saveFavoritePeers(syncedFavorites));
      }
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
        transferSessionItems: state.transferSessionActive
            ? _sortedTransferSessionItems()
            : state.transferSessionItems,
      );
    });

    _completedTransferSub ??= _transfer.completedTransfersStream.listen((
      completedTransfer,
    ) {
      if (!state.transferSessionActive && state.activeTransfers.isEmpty) {
        _transferSessionMap.clear();
        state = state.copyWith(transferSessionActive: true);
      }
      _transferSessionMap[completedTransfer.id] = completedTransfer;
      state = state.copyWith(
        transferSessionItems: _sortedTransferSessionItems(),
      );
      if (completedTransfer.direction == TransferDirection.received &&
          completedTransfer.status == TransferStatus.completed &&
          state.saveMediaToGallery) {
        final localPath = completedTransfer.localPath;
        if (localPath != null && localPath.trim().isNotEmpty) {
          unawaited(_saveMediaToGalleryIfEligible(localPath));
        }
      }
      unawaited(_enqueueTransferPreviewIfEligible(completedTransfer));
    });

    _historySub ??= _transfer.historyStream.listen((history) {
      _tcpHistory = history;
      _emitCombinedHistory();
    });

    _incomingSub ??= _transfer.incomingRequestsStream.listen((requests) {
      var incomingRequests = requests;

      if (state.requirePairingCodeForDirectTransfers) {
        final trustedRequests = <IncomingTransferRequest>[];
        for (final request in requests) {
          if (_isIncomingRequestTrusted(request)) {
            trustedRequests.add(request);
            continue;
          }
          _transfer.rejectIncomingRequest(request.id);
        }
        incomingRequests = trustedRequests;
      }

      if (state.showIncomingRequestList) {
        final maxRequests = state.maxIncomingRequests.clamp(1, 100);
        if (incomingRequests.length > maxRequests) {
          final overflow = incomingRequests.skip(maxRequests);
          for (final request in overflow) {
            _transfer.rejectIncomingRequest(request.id);
          }
          incomingRequests = incomingRequests.take(maxRequests).toList(
            growable: false,
          );
        }
      }

      final nextIds = incomingRequests.map((request) => request.id).toSet();
      final hasNewIncoming = nextIds.any(
        (requestId) => !_knownIncomingRequestIds.contains(requestId),
      );
      _knownIncomingRequestIds
        ..clear()
        ..addAll(nextIds);

      if (state.showIncomingRequestList && hasNewIncoming) {
        final pendingMessages = List<String>.from(state.pendingSystemMessages)
          ..add('New incoming request detected');
        state = state.copyWith(
          pendingIncomingRequests: incomingRequests,
          pendingSystemMessages: pendingMessages,
        );
        return;
      }

      state = state.copyWith(pendingIncomingRequests: incomingRequests);
    });

    _incomingPairingSub ??= _transfer.incomingPairingRequestsStream.listen((
      requests,
    ) {
      state = state.copyWith(pendingPairingRequests: requests);
    });

    _remoteUnpairSub ??= _transfer.remoteUnpairNoticesStream.listen((notices) {
      var trustedPeers = state.trustedPeers;
      var trustedPeersUpdated = false;
      var messagesAdded = false;
      final pendingMessages = List<String>.from(state.pendingSystemMessages);

      for (final notice in notices) {
        if (!_processedRemoteUnpairNoticeIds.add(notice.id)) {
          continue;
        }

        final peerKey = trustedPeerKey(
          notice.fromDeviceId,
          notice.fromTlsCertificateSha256,
        );
        final next = trustedPeers
            .where(
              (peer) =>
                  trustedPeerKey(peer.deviceId, peer.tlsCertificateSha256) !=
                  peerKey,
            )
            .toList(growable: false);
        if (next.length != trustedPeers.length) {
          trustedPeers = next;
          trustedPeersUpdated = true;
          final fromName = notice.fromDeviceName.trim().isEmpty
              ? 'A paired device'
              : notice.fromDeviceName.trim();
          pendingMessages.add('$fromName unpaired this device.');
          messagesAdded = true;
        }
      }

      if (trustedPeersUpdated) {
        unawaited(_saveTrustedPeers(trustedPeers));
      }

      if (trustedPeersUpdated || messagesAdded) {
        state = state.copyWith(
          trustedPeers: trustedPeers,
          pendingSystemMessages: pendingMessages,
        );
      }
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

    _webIncomingUploadSub ??= _web.incomingUploadRequestsStream.listen((
      requests,
    ) {
      state = state.copyWith(pendingWebIncomingUploads: requests);
    });

    _webHistorySub ??= _web.historyStream.listen((history) {
      final previousWebHistory = _webHistory;
      _webHistory = history;
      unawaited(
        _syncNewWebReceivedMediaToGallery(
          previous: previousWebHistory,
          current: history,
        ),
      );
      _emitCombinedHistory();
    });

    _tempShareSub ??= _tempShare.stateStream.listen((tempShareState) {
      state = state.copyWith(tempLinkShare: tempShareState);
    });

    _sharedPayloadSub ??= _shareIntent.sharedPayloadStream.listen((payload) {
      if (payload.isEmpty) {
        return;
      }
      final mergedFiles = _mergeUnique(
        state.pendingSharedFilePaths,
        payload.filePaths,
      );
      final mergedTexts = _mergeUnique(state.pendingSharedTexts, payload.texts);
      state = state.copyWith(
        pendingSharedFilePaths: mergedFiles,
        pendingSharedTexts: mergedTexts,
      );
    });
  }

  Future<void> sendFiles(
    DeviceModel target,
    List<String> filePaths, {
    String? pairingCode,
  }) async {
    if (state.requirePairingCodeForDirectTransfers &&
        !isTargetTrusted(target)) {
      throw StateError(
        'Device is not paired yet. Pair this device before sending files.',
      );
    }

    final localFingerprint = await _discovery.ensureLocalTlsCertificateSha256();
    return _transfer.sendFiles(
      target: target,
      filePaths: filePaths,
      senderDeviceName: _taggedLocalName(),
      senderDeviceId: state.localDeviceId,
      senderTlsCertificateSha256: localFingerprint,
      pairingCode: pairingCode,
    );
  }

  bool isTargetTrusted(DeviceModel target) {
    return isDeviceTrusted(trustedPeers: state.trustedPeers, device: target);
  }

  String? consumeNextPendingSystemMessage() {
    if (state.pendingSystemMessages.isEmpty) {
      return null;
    }
    final next = state.pendingSystemMessages.first;
    final remaining = state.pendingSystemMessages
        .skip(1)
        .toList(growable: false);
    state = state.copyWith(pendingSystemMessages: remaining);
    return next;
  }

  Future<void> respondToIncomingPairingRequest(
    IncomingPairingRequest request, {
    required bool approved,
  }) async {
    if (approved) {
      await _upsertTrustedPeer(
        deviceId: request.fromDeviceId,
        deviceName: request.fromDeviceName,
        tlsCertificateSha256: request.fromTlsCertificateSha256,
      );
      _transfer.approveIncomingPairingRequest(request.id);
      return;
    }
    _transfer.rejectIncomingPairingRequest(request.id);
  }

  Future<void> pairDeviceWithVerification(
    DeviceModel device, {
    required String pairingCode,
  }) async {
    if (!state.requirePairingCodeForDirectTransfers) {
      await pairDevice(device);
      return;
    }

    if (!device.isOnline) {
      throw StateError('Device must be online on the same network to pair.');
    }

    final deviceId = device.deviceId.trim();
    if (deviceId.isEmpty || device.ipAddress.trim().isEmpty) {
      throw StateError(
        'Cannot pair this device because identity metadata is incomplete.',
      );
    }

    final localFingerprint = await _discovery.ensureLocalTlsCertificateSha256();
    final pairingResult = await _transfer.requestPairing(
      target: device,
      senderDeviceName: _taggedLocalName(),
      senderDeviceId: state.localDeviceId,
      senderTlsCertificateSha256: localFingerprint,
      pairingCode: pairingCode,
    );
    if (!pairingResult.accepted) {
      throw StateError('Pairing was rejected or timed out.');
    }

    final trustedFingerprint = pairingResult.peerFingerprint
        .trim()
        .toLowerCase();
    if (trustedFingerprint.isEmpty) {
      throw const HandshakeException(
        'Pairing failed because peer fingerprint could not be verified.',
      );
    }

    await _upsertTrustedPeer(
      deviceId: deviceId,
      deviceName: device.taggedName.trim().isEmpty
          ? device.deviceName.trim()
          : device.taggedName.trim(),
      tlsCertificateSha256: trustedFingerprint,
    );
  }

  Future<void> pairDevice(DeviceModel device) async {
    final deviceId = device.deviceId.trim();
    final fingerprint = (device.tlsCertificateSha256 ?? '')
        .trim()
        .toLowerCase();
    if (deviceId.isEmpty || fingerprint.isEmpty) {
      throw StateError(
        'Cannot pair this device because identity metadata is incomplete.',
      );
    }

    final displayName = device.taggedName.trim().isEmpty
        ? device.deviceName.trim()
        : device.taggedName.trim();
    await _upsertTrustedPeer(
      deviceId: deviceId,
      deviceName: displayName.isEmpty ? deviceId : displayName,
      tlsCertificateSha256: fingerprint,
    );
  }

  Future<void> unpairDevice(DeviceModel device) async {
    final deviceId = device.deviceId.trim().toLowerCase();
    final fingerprint = (device.tlsCertificateSha256 ?? '')
        .trim()
        .toLowerCase();
    if (deviceId.isEmpty || fingerprint.isEmpty) {
      return;
    }

    if (state.requirePairingCodeForDirectTransfers) {
      if (!device.isOnline) {
        throw StateError(
          'Unpairing requires both devices on the same network with the app open.',
        );
      }

      final localFingerprint = await _discovery
          .ensureLocalTlsCertificateSha256();
      final accepted = await _transfer.requestUnpair(
        target: device,
        senderDeviceName: _taggedLocalName(),
        senderDeviceId: state.localDeviceId,
        senderTlsCertificateSha256: localFingerprint,
      );
      if (!accepted) {
        throw StateError(
          'Unpair request failed. Ensure both devices are online and open.',
        );
      }
    }

    // First try exact key (deviceId + current fingerprint).
    final exactKey = trustedPeerKey(deviceId, fingerprint);
    final beforeCount = state.trustedPeers.length;
    await _removeTrustedPeerByKey(exactKey);

    // If nothing was removed the stored entry has a stale fingerprint (cert
    // rotation). Remove the orphan by deviceId alone so it doesn't get stuck.
    if (state.trustedPeers.length == beforeCount) {
      final updated = state.trustedPeers
          .where(
            (peer) => peer.deviceId.trim().toLowerCase() != deviceId,
          )
          .toList(growable: false);
      state = state.copyWith(trustedPeers: updated);
      await _saveTrustedPeers(updated);
    }
  }

  Future<void> unpairTrustedPeer(TrustedPeer target) async {
    final targetKey = trustedPeerKey(
      target.deviceId,
      target.tlsCertificateSha256,
    );
    final normalizedTargetId = target.deviceId.trim().toLowerCase();

    if (state.requirePairingCodeForDirectTransfers) {
      // Try to find the device by the stored fingerprint first; if the peer
      // has rotated its cert, fall back to matching by deviceId alone so an
      // online peer with a new cert can still be remotely unpaired.
      final matchedDevice = state.devices
          .where((device) {
            if (!device.isOnline || device.deviceId.trim().isEmpty) {
              return false;
            }
            final fp = (device.tlsCertificateSha256 ?? '').trim().toLowerCase();
            if (fp.isNotEmpty &&
                trustedPeerKey(device.deviceId, fp) == targetKey) {
              return true;
            }
            // Cert-rotation fallback: match by deviceId only.
            return device.deviceId.trim().toLowerCase() == normalizedTargetId;
          })
          .firstOrNull;

      if (matchedDevice == null) {
        throw StateError(
          'Unpairing requires both devices on the same network with the app open.',
        );
      }

      await unpairDevice(matchedDevice);
      return;
    }

    await _removeTrustedPeerByKey(targetKey);
  }

  Future<void> toggleFavoriteDevice(DeviceModel device) async {
    final normalizedId = device.deviceId.trim();
    if (normalizedId.isEmpty) {
      return;
    }

    final lowerId = normalizedId.toLowerCase();
    final existing = state.favoritePeers.where(
      (peer) => peer.deviceId.trim().toLowerCase() == lowerId,
    );
    if (existing.isNotEmpty) {
      await removeFavoritePeerByDeviceId(normalizedId);
      return;
    }

    final now = DateTime.now();
    final updated = <FavoritePeer>[
      FavoritePeer(
        deviceId: normalizedId,
        deviceName: device.taggedName.trim().isEmpty
            ? device.deviceName.trim()
            : device.taggedName.trim(),
        manufacturer: device.manufacturer.trim(),
        platform: device.platform.trim(),
        lastKnownIp: device.ipAddress.trim(),
        addedAt: now,
        lastSeenAt: device.lastSeen,
      ),
      ...state.favoritePeers,
    ];
    state = state.copyWith(favoritePeers: updated);
    await _saveFavoritePeers(updated);
  }

  Future<void> removeFavoritePeerByDeviceId(String deviceId) async {
    final normalized = deviceId.trim().toLowerCase();
    if (normalized.isEmpty) {
      return;
    }
    final updated = state.favoritePeers
        .where((peer) => peer.deviceId.trim().toLowerCase() != normalized)
        .toList(growable: false);
    state = state.copyWith(favoritePeers: updated);
    await _saveFavoritePeers(updated);
  }

  Future<void> _upsertTrustedPeer({
    required String deviceId,
    required String deviceName,
    required String tlsCertificateSha256,
  }) async {
    final normalizedDeviceId = deviceId.trim();
    final normalizedFingerprint = tlsCertificateSha256.trim().toLowerCase();
    if (normalizedDeviceId.isEmpty || normalizedFingerprint.isEmpty) {
      return;
    }

    final updated = <TrustedPeer>[];
    for (final peer in state.trustedPeers) {
      if (peer.deviceId.trim().toLowerCase() ==
          normalizedDeviceId.toLowerCase()) {
        continue;
      }
      updated.add(peer);
    }
    updated.insert(
      0,
      TrustedPeer(
        deviceId: normalizedDeviceId,
        deviceName: deviceName.trim().isEmpty
            ? normalizedDeviceId
            : deviceName.trim(),
        tlsCertificateSha256: normalizedFingerprint,
        pairedAt: DateTime.now(),
      ),
    );

    state = state.copyWith(trustedPeers: updated);
    await _saveTrustedPeers(updated);
  }

  Future<void> _removeTrustedPeerByKey(String targetKey) async {
    final updated = state.trustedPeers
        .where(
          (peer) =>
              trustedPeerKey(peer.deviceId, peer.tlsCertificateSha256) !=
              targetKey,
        )
        .toList(growable: false);
    state = state.copyWith(trustedPeers: updated);
    await _saveTrustedPeers(updated);
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
            (manageStatus.isPermanentlyDenied ||
                manageStatus.isRestricted ||
                manageStatus.isDenied)) {
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
      if (!granted &&
          openSettingsIfDenied &&
          photosStatus.isPermanentlyDenied) {
        await openAppSettings();
      }
      return granted;
    }

    return true;
  }

  Future<void> refreshNearbyDevices() => _discovery.refreshNow();

  Future<int> stageFilesForWebPeers({
    required List<String> filePaths,
    required List<String> peerIds,
  }) {
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

  Future<void> startWebShare({
    int port = 8080,
    String pin = '',
    bool stopTemporaryShareIfRunning = false,
  }) async {
    if (state.tempLinkShare.running) {
      if (!stopTemporaryShareIfRunning) {
        throw StateError(
          'Temporary link share is active. Stop it first or allow replacing it.',
        );
      }
      await _tempShare.stop();
      state = state.copyWith(tempLinkShare: _tempShare.currentState);
    }

    await _web.start(
      rootDirectory: state.downloadDirectory,
      hostDeviceName: _taggedLocalName(),
      port: port,
      pin: pin,
    );
    state = state.copyWith(webState: _web.currentState);
  }

  Future<void> stopWebShare() async {
    await _web.stop();
    state = state.copyWith(webState: _web.currentState);
  }

  Future<void> startTemporaryLinkShare({
    required List<String> filePaths,
    Duration? ttl,
    String pin = '',
    bool stopWebShareIfRunning = false,
  }) async {
    if (state.webState.running) {
      if (!stopWebShareIfRunning) {
        throw StateError(
          'Web server is active. Stop it first or allow replacing it.',
        );
      }
      await _web.stop();
      state = state.copyWith(webState: _web.currentState);
    }

    final resolvedIp = await _discovery.getLocalIp();
    final hostIp = resolvedIp.isEmpty ? state.localIp : resolvedIp;
    if (hostIp.isEmpty) {
      throw StateError(
        'Local IP is unavailable. Connect to a LAN/Wi-Fi network and try again.',
      );
    }
    await _tempShare.start(
      filePaths: filePaths,
      host: hostIp,
      deviceName: _taggedLocalName(),
      platformLabel: state.localDevicePlatform.isEmpty
          ? 'Unknown'
          : state.localDevicePlatform,
      idSuffix: '#${state.localDeviceNumber}',
      ttl: ttl,
      pin: pin,
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

  void setRequirePairingCodeForDirectTransfers(bool value) {
    final forcedMode = value ? QuickSaveMode.off : state.quickSaveMode;
    state = state.copyWith(
      requirePairingCodeForDirectTransfers: value,
      quickSaveMode: forcedMode,
    );
    unawaited(_discovery.updatePairingModeEnabled(value));
    unawaited(_saveRequirePairingCode(value));
    if (value) {
      unawaited(_saveQuickSaveMode(QuickSaveMode.off));
    }
  }

  void setQuickSaveMode(QuickSaveMode mode) {
    final nextMode = state.requirePairingCodeForDirectTransfers
        ? QuickSaveMode.off
        : mode;
    if (nextMode == state.quickSaveMode) {
      return;
    }
    state = state.copyWith(quickSaveMode: nextMode);
    unawaited(_saveQuickSaveMode(nextMode));
  }

  void setQuickSaveInfoDismissed({
    required QuickSaveMode mode,
    required bool dismissed,
  }) {
    final updated = Set<QuickSaveMode>.from(state.quickSaveInfoDismissedModes);
    if (dismissed) {
      updated.add(mode);
    } else {
      updated.remove(mode);
    }
    state = state.copyWith(quickSaveInfoDismissedModes: updated);
    unawaited(_saveQuickSaveDismissedModes(updated));
  }

  void setShowIncomingRequestList(bool value) {
    state = state.copyWith(showIncomingRequestList: value);
    unawaited(_saveShowIncomingRequestList(value));
  }

  void setMaxIncomingRequests(int value) {
    final validValue = value.clamp(1, 100);
    state = state.copyWith(maxIncomingRequests: validValue);
    unawaited(_saveMaxIncomingRequests(validValue));
  }

  void setIncomingRequestTimeoutSeconds(int value) {
    final validValue = value.clamp(10, 600);
    state = state.copyWith(incomingRequestTimeoutSeconds: validValue);
    unawaited(_saveIncomingRequestTimeoutSeconds(validValue));
  }

  void addPendingSharedFiles(List<String> filePaths) {
    if (filePaths.isEmpty) {
      return;
    }
    final merged = _mergeUnique(state.pendingSharedFilePaths, filePaths);
    state = state.copyWith(pendingSharedFilePaths: merged);
  }

  List<String> consumePendingSharedFiles() {
    final pending = state.pendingSharedFilePaths;
    if (pending.isEmpty) {
      return const <String>[];
    }
    state = state.copyWith(pendingSharedFilePaths: const <String>[]);
    return pending;
  }

  List<String> consumePendingSharedTexts() {
    final pending = state.pendingSharedTexts;
    if (pending.isEmpty) {
      return const <String>[];
    }
    state = state.copyWith(pendingSharedTexts: const <String>[]);
    return pending;
  }

  String? consumeNextPendingSharedText() {
    final pending = state.pendingSharedTexts;
    if (pending.isEmpty) {
      return null;
    }
    final next = pending.first;
    final remaining = pending.length == 1
        ? const <String>[]
        : pending.sublist(1);
    state = state.copyWith(pendingSharedTexts: remaining);
    return next;
  }

  String? consumeNextPendingTransferPreviewText() {
    final pending = state.pendingTransferPreviewTexts;
    if (pending.isEmpty) {
      return null;
    }
    final next = pending.first;
    final remaining = pending.length == 1
        ? const <String>[]
        : pending.sublist(1);
    state = state.copyWith(pendingTransferPreviewTexts: remaining);
    return next;
  }

  TransferModel? consumeNextPendingTransferPreviewFile() {
    final pending = state.pendingTransferPreviewFiles;
    if (pending.isEmpty) {
      return null;
    }
    final next = pending.first;
    final remaining = pending.length == 1
        ? const <TransferModel>[]
        : pending.sublist(1);
    state = state.copyWith(pendingTransferPreviewFiles: remaining);
    return next;
  }

  Future<void> setDeviceName(String name) async {
    await _discovery.updateDeviceName(name);
    state = state.copyWith(
      localDeviceName: _discovery.deviceName,
      localDeviceManufacturer: _discovery.manufacturerTag,
      localDevicePlatform: _discovery.platformTag,
      localDeviceCpuArchitecture: _discovery.cpuArchitectureTag,
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
      localDeviceCpuArchitecture: _discovery.cpuArchitectureTag,
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
      localDeviceCpuArchitecture: _discovery.cpuArchitectureTag,
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
      localDeviceCpuArchitecture: _discovery.cpuArchitectureTag,
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

  Future<void> clearHistoryByDirection(TransferDirection direction) async {
    await _transfer.clearHistoryByDirection(direction);
    await _web.clearHistoryByDirection(direction);

    _tcpHistory = _tcpHistory
        .where((entry) => entry.direction != direction)
        .toList(growable: false);
    _webHistory = _webHistory
        .where((entry) => entry.direction != direction)
        .toList(growable: false);
    _persistedHistory = _persistedHistory
        .where((entry) => entry.direction != direction)
        .toList(growable: false);

    await _saveHistory(_persistedHistory);
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
    _persistedHistory = _persistedHistory
        .where((item) => !_sameHistoryEntry(item, entry))
        .toList(growable: false);
    await _saveHistory(_persistedHistory);
    _emitCombinedHistory();
  }

  Map<String, dynamic> analytics() {
    final sent = state.history
        .where((entry) => entry.status == TransferStatus.completed)
        .length;
    final totalBytes = state.history.fold<int>(
      0,
      (sum, item) => sum + item.size,
    );
    final avgSpeed = state.history.isEmpty
        ? 0.0
        : state.history.fold<double>(
                0,
                (sum, item) =>
                    sum +
                    (item.size /
                        item.duration.inMilliseconds.clamp(1, 1 << 30) *
                        1000),
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
    final all = <TransferHistoryEntry>[
      ..._persistedHistory,
      ..._tcpHistory,
      ..._webHistory,
    ];
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

  Future<void> _enqueueTransferPreviewIfEligible(TransferModel transfer) async {
    if (!isTransferPreviewEligible(transfer)) {
      return;
    }

    final localPath = transfer.localPath!.trim();

    final file = File(localPath);
    if (!await file.exists()) {
      return;
    }

    if (TransferVisuals.supportsReceivedPreview(localPath)) {
      final queued = List<TransferModel>.from(state.pendingTransferPreviewFiles)
        ..add(transfer);
      state = state.copyWith(pendingTransferPreviewFiles: queued);
      return;
    }

    const maxPreviewBytes = 1024 * 512;
    final length = await file.length();
    if (length <= 0 || length > maxPreviewBytes) {
      return;
    }

    String text;
    try {
      text = await file.readAsString();
    } catch (_) {
      return;
    }

    final normalized = text.trim();
    if (normalized.isEmpty) {
      return;
    }

    final queued = List<String>.from(state.pendingTransferPreviewTexts)
      ..add(normalized);
    state = state.copyWith(pendingTransferPreviewTexts: queued);
  }

  Future<void> _syncNewWebReceivedMediaToGallery({
    required List<TransferHistoryEntry> previous,
    required List<TransferHistoryEntry> current,
  }) async {
    if (!state.saveMediaToGallery || current.isEmpty) {
      return;
    }

    for (final entry in current) {
      if (entry.direction != TransferDirection.received ||
          entry.status != TransferStatus.completed) {
        continue;
      }

      final localPath = (entry.localPath ?? '').trim();
      if (localPath.isEmpty) {
        continue;
      }

      final alreadyKnown = previous.any(
        (item) => _sameHistoryEntry(item, entry),
      );
      if (alreadyKnown) {
        continue;
      }

      await _saveMediaToGalleryIfEligible(localPath);
    }
  }

  Future<void> _saveMediaToGalleryIfEligible(String path) async {
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty || !_isGalleryMediaPath(normalizedPath)) {
      return;
    }
    if (!_gallerySyncedPaths.add(normalizedPath)) {
      return;
    }

    await _mediaStore.saveToGallery(normalizedPath);
  }

  bool _isGalleryMediaPath(String path) {
    final lowerPath = path.toLowerCase();
    const imageExtensions = <String>{
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.bmp',
      '.webp',
      '.heic',
      '.heif',
      '.tif',
      '.tiff',
    };
    const videoExtensions = <String>{
      '.mp4',
      '.mov',
      '.mkv',
      '.avi',
      '.webm',
      '.m4v',
      '.3gp',
    };

    for (final extension in imageExtensions) {
      if (lowerPath.endsWith(extension)) {
        return true;
      }
    }
    for (final extension in videoExtensions) {
      if (lowerPath.endsWith(extension)) {
        return true;
      }
    }
    return false;
  }

  bool _isIncomingRequestTrusted(IncomingTransferRequest request) {
    final fromDeviceId = (request.fromDeviceId ?? '').trim();
    final fingerprint = (request.fromTlsCertificateSha256 ?? '')
        .trim()
        .toLowerCase();
    if (fromDeviceId.isEmpty || fingerprint.isEmpty) {
      return false;
    }
    final expected = trustedPeerKey(fromDeviceId, fingerprint);
    return state.trustedPeers.any(
      (peer) =>
          trustedPeerKey(peer.deviceId, peer.tlsCertificateSha256) == expected,
    );
  }

  List<TrustedPeer> _restoreTrustedPeers(List<String> encodedItems) {
    final restored = <TrustedPeer>[];
    final seen = <String>{};
    for (final encoded in encodedItems) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is! Map<String, dynamic>) {
          continue;
        }
        final peer = TrustedPeer.fromJson(decoded);
        if (peer == null) {
          continue;
        }
        final key = trustedPeerKey(peer.deviceId, peer.tlsCertificateSha256);
        if (!seen.add(key)) {
          continue;
        }
        restored.add(peer);
      } catch (_) {}
    }
    restored.sort((a, b) => b.pairedAt.compareTo(a.pairedAt));
    return restored;
  }

  Future<void> _saveTrustedPeers(List<TrustedPeer> peers) async {
    _prefs ??= await SharedPreferences.getInstance();
    final encoded = peers
        .map((peer) => jsonEncode(peer.toJson()))
        .toList(growable: false);
    await _prefs!.setStringList(_trustedPeersKey, encoded);
  }

  List<FavoritePeer> _restoreFavoritePeers(List<String> encodedItems) {
    final restored = <FavoritePeer>[];
    final seen = <String>{};
    for (final encoded in encodedItems) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is! Map<String, dynamic>) {
          continue;
        }
        final peer = FavoritePeer.fromJson(decoded);
        if (peer == null) {
          continue;
        }
        final key = peer.deviceId.trim().toLowerCase();
        if (key.isEmpty || !seen.add(key)) {
          continue;
        }
        restored.add(peer);
      } catch (_) {}
    }
    restored.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return restored;
  }

  Future<void> _saveFavoritePeers(List<FavoritePeer> peers) async {
    _prefs ??= await SharedPreferences.getInstance();
    final encoded = peers
        .map((peer) => jsonEncode(peer.toJson()))
        .toList(growable: false);
    await _prefs!.setStringList(_favoritePeersKey, encoded);
  }

  List<FavoritePeer> _syncFavoritePeersWithDevices(
    List<FavoritePeer> favorites,
    List<DeviceModel> devices,
  ) {
    if (favorites.isEmpty || devices.isEmpty) {
      return favorites;
    }

    final byId = <String, DeviceModel>{};
    for (final device in devices) {
      final id = device.deviceId.trim().toLowerCase();
      if (id.isEmpty) {
        continue;
      }
      byId[id] = device;
    }

    if (byId.isEmpty) {
      return favorites;
    }

    var changed = false;
    final updated = favorites.map((favorite) {
      final device = byId[favorite.deviceId.trim().toLowerCase()];
      if (device == null) {
        return favorite;
      }

      final next = favorite.copyWith(
        deviceName: device.taggedName.trim().isEmpty
            ? device.deviceName.trim()
            : device.taggedName.trim(),
        manufacturer: device.manufacturer.trim(),
        platform: device.platform.trim(),
        lastKnownIp: device.ipAddress.trim(),
        lastSeenAt: device.lastSeen,
      );
      if (!_sameFavoritePeer(next, favorite)) {
        changed = true;
      }
      return next;
    }).toList(growable: false);

    return changed ? updated : favorites;
  }

  bool _sameFavoritePeer(FavoritePeer a, FavoritePeer b) {
    return a.deviceId == b.deviceId &&
        a.deviceName == b.deviceName &&
        a.manufacturer == b.manufacturer &&
        a.platform == b.platform &&
        a.lastKnownIp == b.lastKnownIp &&
        a.addedAt == b.addedAt &&
        a.lastSeenAt == b.lastSeenAt;
  }

  bool _sameFavoritePeerList(List<FavoritePeer> a, List<FavoritePeer> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (!_sameFavoritePeer(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }

  List<String> _mergeUnique(List<String> current, List<String> incoming) {
    if (incoming.isEmpty) {
      return current;
    }
    final merged = <String>[];
    final seen = <String>{};
    for (final value in current) {
      final normalized = value.trim();
      if (normalized.isEmpty || !seen.add(normalized)) {
        continue;
      }
      merged.add(normalized);
    }
    for (final value in incoming) {
      final normalized = value.trim();
      if (normalized.isEmpty || !seen.add(normalized)) {
        continue;
      }
      merged.add(normalized);
    }
    return merged;
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
    final encoded = history
        .map((entry) => jsonEncode(entry.toJson()))
        .toList(growable: false);
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

  Future<void> _saveRequirePairingCode(bool value) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_requirePairingCodeKey, value);
  }

  Future<void> _saveShowIncomingRequestList(bool value) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_showIncomingRequestListKey, value);
  }

  Future<void> _saveMaxIncomingRequests(int value) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(_maxIncomingRequestsKey, value);
  }

  Future<void> _saveIncomingRequestTimeoutSeconds(int value) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(_incomingRequestTimeoutSecondsKey, value);
  }

  QuickSaveMode _quickSaveModeFromName(String? name) {
    switch ((name ?? '').trim().toLowerCase()) {
      case 'on':
        return QuickSaveMode.on;
      case 'favorites':
        return QuickSaveMode.favorites;
      case 'off':
      default:
        return QuickSaveMode.off;
    }
  }

  Set<QuickSaveMode> _restoreQuickSaveDismissedModes(List<String> names) {
    final restored = <QuickSaveMode>{};
    for (final name in names) {
      restored.add(_quickSaveModeFromName(name));
    }
    return restored;
  }

  Future<void> _saveQuickSaveMode(QuickSaveMode mode) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_quickSaveModeKey, mode.name);
  }

  Future<void> _saveQuickSaveDismissedModes(Set<QuickSaveMode> modes) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setStringList(
      _quickSaveDismissedModesKey,
      modes.map((mode) => mode.name).toList(growable: false),
    );
  }

  Future<String> _resolveDownloadDirectory({String? preferred}) async {
    final preferredPath = preferred?.trim() ?? '';
    if (Platform.isAndroid) {
      final legacyPrivatePath = await _legacyMobileDownloadDirectory();
      final usingLegacyPrivateDefault =
          preferredPath.isNotEmpty &&
          _isSameNormalizedPath(preferredPath, legacyPrivatePath);

      if (preferredPath.isNotEmpty && !usingLegacyPrivateDefault) {
        try {
          final preferredDir = Directory(preferredPath);
          await preferredDir.create(recursive: true);
          return preferredDir.path;
        } catch (_) {}
      }

      final sharedDownloadPath = await _resolveAndroidSharedDownloadDirectory();
      if (sharedDownloadPath != null) {
        return sharedDownloadPath;
      }

      final fallback = Directory(legacyPrivatePath);
      await fallback.create(recursive: true);
      return fallback.path;
    }

    if (preferredPath.isNotEmpty) {
      try {
        final preferredDir = Directory(preferredPath);
        await preferredDir.create(recursive: true);
        return preferredDir.path;
      } catch (_) {}
    }

    if (Platform.isIOS) {
      final fallback = Directory(await _legacyMobileDownloadDirectory());
      await fallback.create(recursive: true);
      return fallback.path;
    }

    Directory dir;
    try {
      dir =
          await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
    } on UnsupportedError {
      dir = await getApplicationDocumentsDirectory();
    }
    final target = Directory('${dir.path}${Platform.pathSeparator}DropNet');
    await target.create(recursive: true);
    return target.path;
  }

  Future<String> _legacyMobileDownloadDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}${Platform.pathSeparator}DropNet';
  }

  bool _isSameNormalizedPath(String a, String b) {
    String normalize(String input) {
      final replaced = input.trim().replaceAll('\\', '/').toLowerCase();
      return replaced.replaceAll(RegExp('/+'), '/');
    }

    return normalize(a) == normalize(b);
  }

  Future<String?> _resolveAndroidSharedDownloadDirectory() async {
    final candidateRoots = <String>{};

    try {
      final externalDownloadDirs =
          await getExternalStorageDirectories(
            type: StorageDirectory.downloads,
          ) ??
          const <Directory>[];
      for (final directory in externalDownloadDirs) {
        final root = _extractAndroidSharedStorageRoot(directory.path);
        if (root.isNotEmpty) {
          candidateRoots.add(root);
        }
      }
    } catch (_) {}

    try {
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        final root = _extractAndroidSharedStorageRoot(externalDir.path);
        if (root.isNotEmpty) {
          candidateRoots.add(root);
        }
      }
    } catch (_) {}

    candidateRoots.add('/storage/emulated/0');

    for (final root in candidateRoots) {
      final candidate = Directory('$root/Download/DropNet');
      try {
        await candidate.create(recursive: true);
        return candidate.path;
      } catch (_) {}
    }

    return null;
  }

  String _extractAndroidSharedStorageRoot(String rawPath) {
    final normalized = rawPath.trim().replaceAll('\\', '/');
    if (normalized.isEmpty || !normalized.startsWith('/storage/')) {
      return '';
    }

    if (normalized.startsWith('/storage/emulated/')) {
      final segments = normalized
          .split('/')
          .where((part) => part.isNotEmpty)
          .toList(growable: false);
      if (segments.length >= 3) {
        return '/${segments[0]}/${segments[1]}/${segments[2]}';
      }
    }

    final segments = normalized
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (segments.length >= 2) {
      return '/${segments[0]}/${segments[1]}';
    }

    return '';
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
    _incomingPairingSub?.cancel();
    _remoteUnpairSub?.cancel();
    _webSub?.cancel();
    _webPeerReqSub?.cancel();
    _webPeerSub?.cancel();
    _webIncomingUploadSub?.cancel();
    _webHistorySub?.cancel();
    _tempShareSub?.cancel();
    _sharedPayloadSub?.cancel();
    super.dispose();
  }
}
