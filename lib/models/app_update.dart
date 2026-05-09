enum AppUpdateType {
  optional,
  force,
}

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.type,
    required this.versionName,
    required this.versionCode,
    required this.title,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.fileSizeBytes,
    required this.sha256,
    required this.publishedAt,
  });

  final AppUpdateType type;
  final String versionName;
  final int versionCode;
  final String title;
  final List<String> releaseNotes;
  final String downloadUrl;
  final int fileSizeBytes;
  final String sha256;
  final DateTime? publishedAt;

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    final latest = json['latest'] as Map<String, dynamic>;
    final type = json['updateType'] == 'force'
        ? AppUpdateType.force
        : AppUpdateType.optional;
    return AppUpdateInfo(
      type: type,
      versionName: latest['versionName'] as String? ?? '',
      versionCode: latest['versionCode'] as int? ?? 0,
      title: latest['title'] as String? ?? '发现新版本',
      releaseNotes: (latest['releaseNotes'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      downloadUrl: latest['downloadUrl'] as String? ?? '',
      fileSizeBytes: latest['fileSizeBytes'] as int? ?? 0,
      sha256: latest['sha256'] as String? ?? '',
      publishedAt: DateTime.tryParse(latest['publishedAt'] as String? ?? ''),
    );
  }

  bool get isForce => type == AppUpdateType.force;
}
