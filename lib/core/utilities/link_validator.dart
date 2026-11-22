import '../../shared/enums/enums.dart';

/// Offline, format-only classification of group links.
///
/// IMPORTANT: this can only ever return [ValidationStatus.validFormat] or
/// [ValidationStatus.invalidFormat]. A link is *never* reported as verified
/// here; verification needs an authorized platform integration (Phase 6+).
abstract final class LinkValidator {
  /// Known invite-link hosts. Rubika and Soroush are intentionally empty: their
  /// official link hosts have not been verified, so only generic URL checks apply.
  static const Map<MessagingPlatform, Set<String>> knownHosts = {
    MessagingPlatform.telegram: {'t.me', 'telegram.me', 'telegram.dog'},
    MessagingPlatform.whatsapp: {'chat.whatsapp.com'},
    MessagingPlatform.rubika: <String>{},
    MessagingPlatform.soroush: <String>{},
  };

  static ValidationStatus checkFormat(MessagingPlatform platform, String raw) {
    final text = raw.trim();
    if (text.isEmpty || text.contains(RegExp(r'\s'))) return ValidationStatus.invalidFormat;
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return ValidationStatus.invalidFormat;
    if (uri.scheme != 'https' && uri.scheme != 'http') return ValidationStatus.invalidFormat;

    var host = uri.host.toLowerCase();
    if (host.startsWith('www.')) host = host.substring(4);
    if (!host.contains('.')) return ValidationStatus.invalidFormat;

    final hosts = knownHosts[platform] ?? const <String>{};
    if (hosts.isNotEmpty) {
      if (!hosts.contains(host)) return ValidationStatus.invalidFormat;
      // Invite links need a non-empty path (the invite code / username).
      if (uri.pathSegments.where((s) => s.isNotEmpty).isEmpty) {
        return ValidationStatus.invalidFormat;
      }
    }
    return ValidationStatus.validFormat;
  }
}
