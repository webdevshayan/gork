/// The version this build was made from. The build script greps the pubspec
/// and passes it as --dart-define; a bare `flutter test` run shows `dev`.
const String kAppVersion = String.fromEnvironment('GORK_VERSION', defaultValue: 'dev');
