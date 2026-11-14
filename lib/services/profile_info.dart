import 'package:flutter/foundation.dart';

import 'locator.dart';

/// The user's editable identity. Defaults keep the reference design's
/// header ("Shyan Ali Jalb" / shayanalibuilds@gmail.com) until the user
/// changes their own name/email on the Profile form — then it is theirs,
/// persisted in prefs, shown everywhere.
const String kDefaultName = 'Shyan Ali Jalb';
const String kDefaultEmail = 'shayanalibuilds@gmail.com';

final ValueNotifier<String> profileName =
    ValueNotifier<String>(kDefaultName);
final ValueNotifier<String> profileEmail =
    ValueNotifier<String>(kDefaultEmail);

/// Loads the persisted identity into the notifiers. SYNCHRONOUS on purpose:
/// SharedPreferences values are already in memory, and the header must be
/// correct on the very first frame — no async gap, no race. Safe when the
/// locator is not bound (widget tests) — the defaults stay.
void initProfile() {
  try {
    final p = Locator.prefs;
    profileName.value = p.getString('profile.name') ?? kDefaultName;
    profileEmail.value = p.getString('profile.email') ?? kDefaultEmail;
  } catch (_) {
    // Locator unbound — defaults are already in place.
  }
}

/// Persists the edited identity and pushes it to every listener at once.
Future<void> saveProfile({
  required String name,
  required String email,
}) async {
  await Locator.prefs.setString('profile.name', name);
  await Locator.prefs.setString('profile.email', email);
  profileName.value = name;
  profileEmail.value = email;
}
