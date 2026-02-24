enum TransferStatus {
  pending,
  connecting,
  transferring,
  paused,
  completed,
  canceled,
  failed,
}

enum TransferDirection {
  sent,
  received,
}

class TransferModel {
  const TransferModel({
    required this.id,
    required this.fileName,
    required this.size,
    required this.progress,
    required this.speed,
    required this.status,
    required this.deviceName,
    required this.startedAt,
    required this.direction,
    this.localPath,
    this.eta,
    this.sha256,
    this.verified = false,
    this.errorMessage,
  });

  final String id;
  final String fileName;
  final int size;
  final double progress;
  final double speed;
  final TransferStatus status;
  final String deviceName;
  final DateTime startedAt;
  final TransferDirection direction;
  final String? localPath;
  final Duration? eta;
  final String? sha256;
  final bool verified;
  final String? errorMessage;

  TransferModel copyWith({
    String? id,
    String? fileName,
    int? size,
    double? progress,
    double? speed,
    TransferStatus? status,
    String? deviceName,
    DateTime? startedAt,
    TransferDirection? direction,
    String? localPath,
    Duration? eta,
    String? sha256,
    bool? verified,
    String? errorMessage,
  }) {
    return TransferModel(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      size: size ?? this.size,
      progress: progress ?? this.progress,
      speed: speed ?? this.speed,
      status: status ?? this.status,
      deviceName: deviceName ?? this.deviceName,
      startedAt: startedAt ?? this.startedAt,
      direction: direction ?? this.direction,
      localPath: localPath ?? this.localPath,
      eta: eta ?? this.eta,
      sha256: sha256 ?? this.sha256,
      verified: verified ?? this.verified,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class TransferHistoryEntry {
  const TransferHistoryEntry({
    required this.fileName,
    required this.size,
    required this.date,
    required this.deviceName,
    required this.status,
    required this.duration,
    required this.direction,
  });

  final String fileName;
  final int size;
  final DateTime date;
  final String deviceName;
  final TransferStatus status;
  final Duration duration;
  final TransferDirection direction;

  Map<String, dynamic> toJson() {
    return {
      'fileName': fileName,
      'size': size,
      'date': date.toIso8601String(),
      'deviceName': deviceName,
      'status': status.name,
      'durationMs': duration.inMilliseconds,
      'direction': direction.name,
    };
  }

  static TransferHistoryEntry? fromJson(Map<String, dynamic> json) {
    try {
      final fileName = json['fileName']?.toString() ?? '';
      final size = (json['size'] as num?)?.toInt() ?? 0;
      final dateRaw = json['date']?.toString() ?? '';
      final deviceName = json['deviceName']?.toString() ?? '';
      final statusName = json['status']?.toString() ?? '';
      final durationMs = (json['durationMs'] as num?)?.toInt() ?? 0;
      final directionName = json['direction']?.toString() ?? '';

      if (fileName.isEmpty || dateRaw.isEmpty || deviceName.isEmpty) {
        return null;
      }

      final date = DateTime.tryParse(dateRaw);
      if (date == null) {
        return null;
      }

      final status = TransferStatus.values.firstWhere(
        (value) => value.name == statusName,
        orElse: () => TransferStatus.failed,
      );
      final direction = TransferDirection.values.firstWhere(
        (value) => value.name == directionName,
        orElse: () => TransferDirection.received,
      );

      return TransferHistoryEntry(
        fileName: fileName,
        size: size,
        date: date,
        deviceName: deviceName,
        status: status,
        duration: Duration(milliseconds: durationMs.clamp(0, 1 << 30)),
        direction: direction,
      );
    } catch (_) {
      return null;
    }
  }
}

class IncomingTransferRequest {
  const IncomingTransferRequest({
    required this.id,
    required this.fileName,
    required this.size,
    required this.fromAddress,
    required this.fromDeviceName,
    required this.requestedAt,
    this.batchId,
    this.batchFileCount,
    this.batchIndex,
    this.batchTotalBytes,
  });

  final String id;
  final String fileName;
  final int size;
  final String fromAddress;
  final String fromDeviceName;
  final DateTime requestedAt;
  final String? batchId;
  final int? batchFileCount;
  final int? batchIndex;
  final int? batchTotalBytes;
}
