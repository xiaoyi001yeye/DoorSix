class AppBuildInfo {
  const AppBuildInfo({
    this.platform = 'android',
    this.versionName = const String.fromEnvironment(
      'DOORSIX_APP_VERSION_NAME',
      defaultValue: '0.1.0',
    ),
    this.versionCode = const int.fromEnvironment(
      'DOORSIX_APP_VERSION_CODE',
      defaultValue: 1,
    ),
    this.channel = const String.fromEnvironment(
      'DOORSIX_RELEASE_CHANNEL',
      defaultValue: 'stable',
    ),
  });

  final String platform;
  final String versionName;
  final int versionCode;
  final String channel;
}
