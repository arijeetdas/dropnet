import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:ftp_server/file_operations/file_operations.dart';
import 'package:ftp_server/file_operations/physical_file_operations.dart';
import 'package:ftp_server/file_operations/virtual_file_operations.dart';
import 'package:ftp_server/ftp_server.dart';
import 'package:ftp_server/server_type.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../platform/android_saf_service.dart';
import 'mixed_file_operations.dart';
import 'saf_file_operations.dart';

class RandomCredentials {
  const RandomCredentials({
    required this.username,
    required this.password,
  });

  final String username;
  final String password;
}

class FtpServerState {
  const FtpServerState({
    required this.running,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.anonymous,
    required this.readOnly,
    required this.activeConnections,
    required this.sharedRoots,
    required this.sharedMounts,
    required this.logs,
  });

  final bool running;
  final String host;
  final int port;
  final String username;
  final String password;
  final bool anonymous;
  final bool readOnly;
  final int activeConnections;
  final List<String> sharedRoots;
  final List<String> sharedMounts;
  final List<String> logs;

  FtpServerState copyWith({
    bool? running,
    String? host,
    int? port,
    String? username,
    String? password,
    bool? anonymous,
    bool? readOnly,
    int? activeConnections,
    List<String>? sharedRoots,
    List<String>? sharedMounts,
    List<String>? logs,
  }) {
    return FtpServerState(
      running: running ?? this.running,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      anonymous: anonymous ?? this.anonymous,
      readOnly: readOnly ?? this.readOnly,
      activeConnections: activeConnections ?? this.activeConnections,
      sharedRoots: sharedRoots ?? this.sharedRoots,
      sharedMounts: sharedMounts ?? this.sharedMounts,
      logs: logs ?? this.logs,
    );
  }

  static FtpServerState initial() => const FtpServerState(
        running: false,
        host: '',
        port: 2121,
        username: 'dropnet',
        password: 'dropnet123',
        anonymous: false,
        readOnly: false,
        activeConnections: 0,
        sharedRoots: <String>[],
        sharedMounts: <String>[],
        logs: <String>[],
      );
}

class _BuiltFtpMount {
  const _BuiltFtpMount({
    required this.fileOperations,
    required this.mountPreview,
  });

  final FileOperations fileOperations;
  final List<String> mountPreview;
}

class FtpService {
  FtpService({AndroidSafService? safService}) : _safService = safService;

  final AndroidSafService? _safService;
  final _controller = StreamController<FtpServerState>.broadcast();
  FtpServerState _state = FtpServerState.initial();
  FtpServer? _server;
  Timer? _activeTimer;

  Stream<FtpServerState> get stateStream => _controller.stream;
  FtpServerState get currentState => _state;

  RandomCredentials generateRandomCredentials() {
    final random = Random.secure();
    const chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789';

    String createPart(int length) {
      final buffer = StringBuffer();
      for (var i = 0; i < length; i++) {
        buffer.write(chars[random.nextInt(chars.length)]);
      }
      return buffer.toString();
    }

    return RandomCredentials(
      username: 'dn_${createPart(6)}',
      password: '${createPart(6)}-${createPart(6)}-${createPart(4)}',
    );
  }

  Future<void> start({
    required List<String> sharedDirectories,
    int port = 2121,
    String username = 'dropnet',
    String password = 'dropnet123',
    bool anonymous = false,
    bool readOnly = false,
    String? preferredHost,
  }) async {
    await stop();

    final host = await _resolveLocalIp(preferred: preferredHost);
    final logs = <String>[];
    final normalizedRoots = await _normalizeRootDirectories(sharedDirectories);
    final safRoots = normalizedRoots.where((root) => root.startsWith('saf://')).toList(growable: false);
    final physicalRoots = normalizedRoots.where((root) => !root.startsWith('saf://')).toList(growable: false);

    final built = await _buildFileOperations(
      physicalRoots: physicalRoots,
      safRoots: safRoots,
    );

    _server = FtpServer(
      port,
      username: anonymous ? null : username,
      password: anonymous ? null : password,
      fileOperations: built.fileOperations,
      serverType: readOnly ? ServerType.readOnly : ServerType.readAndWrite,
      logFunction: (line) {
        logs.insert(0, line);
        if (logs.length > 200) {
          logs.removeLast();
        }
        _update(_state.copyWith(logs: List<String>.from(logs)));
      },
    );

    await _server!.startInBackground();

    _update(
      _state.copyWith(
        running: true,
        host: host,
        port: port,
        username: username,
        password: password,
        anonymous: anonymous,
        readOnly: readOnly,
        sharedRoots: normalizedRoots,
        sharedMounts: built.mountPreview,
      ),
    );

    _activeTimer?.cancel();
    _activeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final sessions = _server?.activeSessions ?? const [];
      final connectedAddresses = <String>{};
      for (final session in sessions) {
        connectedAddresses.add(session.controlSocket.remoteAddress.address);
      }
      _update(_state.copyWith(activeConnections: connectedAddresses.length));
    });
  }

  Future<void> stop() async {
    _activeTimer?.cancel();
    _activeTimer = null;
    await _server?.stop();
    _server = null;
    _update(
      _state.copyWith(
        running: false,
        activeConnections: 0,
        sharedRoots: const <String>[],
        sharedMounts: const <String>[],
      ),
    );
  }

  Future<List<String>> _normalizeRootDirectories(List<String> rootDirectories) async {
    final cleaned = <String>[];
    for (final path in rootDirectories) {
      final normalized = path.trim();
      if (normalized.isEmpty) {
        continue;
      }
      if (normalized.startsWith('saf://')) {
        cleaned.add(normalized);
        continue;
      }
      final directory = Directory(normalized);
      if (!await directory.exists()) {
        throw FileSystemException('Shared directory does not exist', normalized);
      }
      cleaned.add(directory.path);
    }

    if (cleaned.isEmpty) {
      throw const FileSystemException('At least one FTP shared directory is required');
    }

    final deduped = cleaned.toSet().toList(growable: false);
    final aliases = <String, int>{};
    for (final root in deduped) {
      final key = p.basename(root).toLowerCase();
      aliases[key] = (aliases[key] ?? 0) + 1;
    }
    final hasDuplicateAliases = aliases.values.any((count) => count > 1);
    if (hasDuplicateAliases && deduped.length > 1) {
      throw const FileSystemException(
        'Shared folders must have unique last folder names when sharing multiple roots (FTP virtual root limitation).',
      );
    }

    return deduped;
  }

  Future<_BuiltFtpMount> _buildFileOperations({
    required List<String> physicalRoots,
    required List<String> safRoots,
  }) async {
    if (safRoots.isNotEmpty) {
      if (!Platform.isAndroid || kIsWeb) {
        throw const FileSystemException('SAF roots are only supported on Android.');
      }
      final safService = _safService;
      if (safService == null) {
        throw const FileSystemException('SAF service is unavailable.');
      }

      final persisted = await safService.listPersistedTrees();
      final byUri = <String, AndroidSafTree>{};
      for (final tree in persisted) {
        byUri[tree.uri] = tree;
      }

      final safMappedRoots = <SafTreeRoot>[];
      for (final item in safRoots) {
        final uri = item.substring('saf://'.length);
        final tree = byUri[uri];
        if (tree == null) {
          throw FileSystemException('Missing persisted SAF permission for $uri');
        }
        final alias = _uniqueAlias(
          tree.name.isEmpty ? 'storage' : tree.name,
          [...physicalRoots.map(_physicalAlias), ...safMappedRoots.map((root) => root.alias)],
        );
        safMappedRoots.add(SafTreeRoot(alias: alias, treeUri: tree.uri, label: tree.name));
      }

      if (physicalRoots.isNotEmpty) {
        final mixedRoots = <MixedRoot>[];
        final mountPreview = <String>[];
        for (final root in physicalRoots) {
          final alias = _physicalAlias(root);
          mixedRoots.add(
            MixedRoot.physical(
              alias: alias,
              label: root,
              physicalPath: root,
            ),
          );
          mountPreview.add('/$alias  →  $root');
        }
        for (final root in safMappedRoots) {
          mixedRoots.add(
            MixedRoot.saf(
              alias: root.alias,
              label: root.label,
              treeUri: root.treeUri,
            ),
          );
          mountPreview.add('/${root.alias}  →  SAF:${root.label.isEmpty ? root.treeUri : root.label}');
        }
        return _BuiltFtpMount(
          fileOperations: MixedFileOperations(roots: mixedRoots, safService: safService),
          mountPreview: mountPreview,
        );
      }

      return _BuiltFtpMount(
        fileOperations: SafFileOperations(roots: safMappedRoots, service: safService),
        mountPreview: safMappedRoots
            .map((root) => '/${root.alias}  →  SAF:${root.label.isEmpty ? root.treeUri : root.label}')
            .toList(growable: false),
      );
    }

    if (physicalRoots.length == 1) {
      return _BuiltFtpMount(
        fileOperations: PhysicalFileOperations(physicalRoots.first),
        mountPreview: <String>['/  →  ${physicalRoots.first}'],
      );
    }

    return _BuiltFtpMount(
      fileOperations: VirtualFileOperations(physicalRoots),
      mountPreview: physicalRoots.map((root) {
        final alias = _physicalAlias(root);
        return '/$alias  →  $root';
      }).toList(growable: false),
    );
  }

  String _uniqueAlias(String base, Iterable<String> existingAliases) {
    final clean = base.trim().replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
    final preferred = clean.isEmpty ? 'storage' : clean;
    final used = existingAliases.map((alias) => alias.toLowerCase()).toSet();
    if (!used.contains(preferred.toLowerCase())) {
      return preferred;
    }
    var index = 2;
    while (used.contains('${preferred}_$index'.toLowerCase())) {
      index++;
    }
    return '${preferred}_$index';
  }

  String _physicalAlias(String rootPath) {
    final parts = rootPath.replaceAll('\\', '/').split('/').where((part) => part.isNotEmpty).toList(growable: false);
    if (parts.isEmpty) {
      return 'root';
    }
    return parts.last;
  }

  Future<String> _resolveLocalIp({String? preferred}) async {
    final normalizedPreferred = (preferred ?? '').trim();
    if (normalizedPreferred.isNotEmpty &&
        normalizedPreferred != '0.0.0.0' &&
        normalizedPreferred != '127.0.0.1') {
      return normalizedPreferred;
    }

    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    for (final iface in interfaces) {
      for (final address in iface.addresses) {
        if (!address.isLoopback && address.address != '0.0.0.0') {
          return address.address;
        }
      }
    }
    return '127.0.0.1';
  }

  void _update(FtpServerState state) {
    _state = state;
    _controller.add(_state);
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
