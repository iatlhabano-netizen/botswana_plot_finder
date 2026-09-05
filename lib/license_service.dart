import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

enum LicenseTier {
  free('Free', 0),
  fieldUnlock('Field Unlock', 1),
  contractorPro('Contractor Pro', 2);

  final String label;
  final int level;
  const LicenseTier(this.label, this.level);
}

class LicenseInfo {
  final LicenseTier tier;
  final DateTime? expiresAt;
  final bool isActive;

  const LicenseInfo({required this.tier, required this.expiresAt, required this.isActive});

  factory LicenseInfo.expired() => const LicenseInfo(tier: LicenseTier.free, expiresAt: null, isActive: false);

  bool get isPro => isActive && tier.level >= LicenseTier.contractorPro.level;
  bool get isFieldUnlock => isActive && tier.level >= LicenseTier.fieldUnlock.level;
}

/// Handles feature gating and activation code validation.
class LicenseService {
  static const _key = 'license';
  static const _tierKey = 'license_tier';
  static const _expiryKey = 'license_expiry';

  // Voucher code prefixes per tier (case-insensitive)
  // Format: XXXXXX-XXXXXX e.g. FU-AB12-CD34, CP-EF56-GH78
  static bool _validCodeFormat(String code) =>
      RegExp(r'^(FU|CP)[-\s]?[A-Z0-9]{4}[-\s]?[A-Z0-9]{4}$', caseSensitive: false).hasMatch(code.trim());

  /// Validates an activation code and activates the matching tier.
  /// Returns a user-facing message.
  static Future<String> activateWithCode(String code) async {
    final c = code.trim();

    if (!_validCodeFormat(c)) {
      return 'Invalid code.\nUse format: FU-AB12-CD34 (Field) or CP-EF56-GH78 (Pro)';
    }

    final tier = c.toUpperCase().startsWith('CP') ? LicenseTier.contractorPro : LicenseTier.fieldUnlock;

    // NOTE: In production, verify the code against your server/DB.
    // Here we accept any well-formed code for demo/dev.
    final sp = await SharedPreferences.getInstance();
    final duration = tier == LicenseTier.contractorPro
        ? const Duration(days: 365) // 6-month pass (approx 1 year demo)
        : const Duration(days: 36500); // lifetime (100 years)

    final expiry = DateTime.now().add(duration);
    await sp.setString(_tierKey, tier.name);
    await sp.setString(_expiryKey, expiry.toIso8601String());

    return tier == LicenseTier.contractorPro
        ? 'Contractor Pro activated! 🎉'
        : 'Field Unlock activated! Your plot is permanently unlocked. 🎉';
  }

  static String _checksum(String input) {
    var h = 0;
    for (final c in input.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    // create a deterministic 4-char token
    return (h % 0x10000).toRadixString(16).padLeft(4, '0').toUpperCase();
  }

  /// Generates a valid activation code from a secret (admin side).
  /// Not used in-app by end users — exposed for dev/agent tooling.
  static String generateCode({required String secret, required LicenseTier tier}) {
    final prefix = tier == LicenseTier.contractorPro ? 'CP' : 'FU';
    final body = _checksum('$prefix:$secret:$tier.name');
    final a = body.substring(0, 2) + _checksum(secret);
    final b = body.substring(2, 4) + _checksum('$secret-x');
    return '$prefix-$a-$b';
  }

  static Future<LicenseInfo> load() async {
    final sp = await SharedPreferences.getInstance();
    final tierName = sp.getString(_tierKey);
    if (tierName == null) return const LicenseInfo(tier: LicenseTier.free, expiresAt: null, isActive: false);

    final tier = LicenseTier.values.firstWhere((t) => t.name == tierName, orElse: () => LicenseTier.free);
    final expiryStr = sp.getString(_expiryKey);
    final expiry = expiryStr != null ? DateTime.tryParse(expiryStr) : null;

    if (tier == LicenseTier.free) return const LicenseInfo(tier: LicenseTier.free, expiresAt: null, isActive: false);
    if (expiry == null || expiry.isBefore(DateTime.now())) {
      // Expired — clear it
      await sp.remove(_tierKey);
      await sp.remove(_expiryKey);
      return LicenseInfo.expired();
    }
    return LicenseInfo(tier: tier, expiresAt: expiry, isActive: true);
  }

  /// Checks if a premium feature is allowed and, if not, triggers the upgrade UI.
  /// Returns true if the caller should proceed (feature is unlocked or was just handled).
  static Future<bool> require(
    BuildContext context,
    LicenseTier requiredTier,
    String featureName,
  ) async {
    final info = await load();
    if (info.tier.level >= requiredTier.level && info.isActive) return true;

    if (!context.mounted) return false;
    final shouldUpgrade = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$featureName is ${requiredTier.label}'),
        content: Text(info.tier == LicenseTier.free
            ? 'This feature is included with ${requiredTier.label}. Activate a code to continue.'
            : 'Upgrade to ${requiredTier.label} to use $featureName.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Activate')),
        ],
      ),
    );
    return shouldUpgrade ?? false;
  }
}
