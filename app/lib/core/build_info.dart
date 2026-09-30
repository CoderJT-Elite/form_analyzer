/// Which code a given install is actually running.
///
/// Live test #3 (2026-09-29) was recorded on a build that predated the fixes
/// being tested, and nothing on the phone said so. `tools/install_phone.ps1`
/// passes these via `--dart-define`; a plain `flutter run` reports "dev".
class BuildInfo {
  const BuildInfo._();

  static const String gitSha = String.fromEnvironment('GIT_SHA', defaultValue: 'dev');
  static const bool dirty = bool.fromEnvironment('GIT_DIRTY');
  static const String builtAt = String.fromEnvironment('BUILD_TIME');

  /// e.g. `61f300d`, `61f300d+dirty`, or `dev`.
  static String get label => dirty ? '$gitSha+dirty' : gitSha;

  /// One line for a footer: `Build 61f300d · 2026-09-29 21:40`.
  static String get summary =>
      builtAt.isEmpty ? 'Build $label' : 'Build $label · $builtAt';
}
