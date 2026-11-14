import 'dart:convert';

import 'gmail_service.dart';
import 'integrations.dart';
import 'locator.dart';
import 'secure_store.dart';

/// A Google account the user connected by pasting an OAuth access token.
/// The token lives in the keystore with everything else.
class GoogleAccount {
  final String email;
  final String token;

  const GoogleAccount({required this.email, required this.token});

  Map<String, dynamic> toJson() => {'email': email, 'token': token};

  static GoogleAccount fromJson(Map<String, dynamic> j) => GoogleAccount(
        email: j['email'] as String,
        token: j['token'] as String,
      );
}

/// The user's Google accounts, and the one-click connector.
///
/// "Connect Google" means: pick an account, and EVERY Google-backed
/// connector in the app binds to it at once — no per-service token dialogs.
/// A future Google connector only needs to land in [kGoogleServices].
class GoogleAccountStore {
  GoogleAccountStore({
    required this.store,
    required this.verifier,
    required this.vault,
  });

  final SecureStore store;

  /// Turns a raw token into the account's email — the real one is Gmail's
  /// whoAmI; tests inject a fake. Throws on an unusable token.
  final Future<String> Function(String token) verifier;

  final IntegrationVault vault;

  static const String kAccountsKey = 'google.accounts';
  static const String kActiveKey = 'google.active';

  /// Every connector that rides on the Google account.
  static const List<String> kGoogleServices = ['gmail'];

  Future<List<GoogleAccount>> accounts() async {
    final raw = await store.read(kAccountsKey);
    if (raw == null || raw.isEmpty) return <GoogleAccount>[];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => GoogleAccount.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<GoogleAccount?> active() async {
    final email = await store.read(kActiveKey);
    if (email == null) return null;
    for (final a in await accounts()) {
      if (a.email == email) return a;
    }
    return null;
  }

  Future<void> setActive(String email) => store.write(kActiveKey, email);

  Future<void> removeAccount(String email) async {
    final rest =
        (await accounts()).where((a) => a.email != email).toList();
    await store.write(kAccountsKey, jsonEncode(rest));
    if ((await store.read(kActiveKey)) == email) {
      await store.delete(kActiveKey);
    }
  }

  /// Verifies the token first (a bad token throws and persists nothing),
  /// then stores the account. Re-adding an email upserts — never duplicates.
  Future<GoogleAccount> addAccount(String token) async {
    final email = await verifier(token);
    final rest =
        (await accounts()).where((a) => a.email != email).toList();
    final acct = GoogleAccount(email: email, token: token);
    rest.add(acct);
    await store.write(kAccountsKey, jsonEncode(rest));
    return acct;
  }

  /// ONE CLICK: the chosen account's token binds to every Google-scoped
  /// connector, and the account becomes the active one. Returns the human
  /// names of what got connected ("Gmail"), for the report line.
  Future<List<String>> connectAll(String email) async {
    final match =
        (await accounts()).where((a) => a.email == email).toList();
    if (match.isEmpty) {
      throw IntegrationException('No Google account for $email');
    }
    for (final id in kGoogleServices) {
      await vault.setToken(id, match.first.token);
    }
    await setActive(email);
    return [for (final id in kGoogleServices) integrationById(id)?.name ?? id];
  }

  /// Real verifier: Gmail's whoAmI doubles as the Google account check —
  /// a token that can read the Gmail profile is a working Google token.
  static Future<String> gmailVerifier(String token) async {
    return GmailService(
      client: Locator.httpClient,
      token: () async => token,
    ).whoAmI();
  }
}
