import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Who Google says the connected Drive account is.
///
/// Comes from `about.get?fields=user`, which is permitted with the
/// `drive.file` scope the app already holds. No extra scope is requested.
/// Display-only: this value is shown in Settings and kept in local
/// preferences. It is never sent anywhere and never logged, so the "Data Not
/// Collected" privacy declaration stays true.
class DriveAccountUser {
  final String? displayName;
  final String? emailAddress;

  const DriveAccountUser({this.displayName, this.emailAddress});

  /// "Name (email)", or whichever half came back; null if neither did.
  String? get label {
    final name = displayName?.trim();
    final email = emailAddress?.trim();
    final hasName = name != null && name.isNotEmpty;
    final hasEmail = email != null && email.isNotEmpty;
    if (hasName && hasEmail) return '$name ($email)';
    if (hasName) return name;
    if (hasEmail) return email;
    return null;
  }
}

/// Asks Drive who the token belongs to. Returns null on any failure or when
/// Google withholds both fields; the caller then asks the user to name the
/// connection instead.
Future<DriveAccountUser?> fetchDriveAboutUser(http.Client client) async {
  try {
    final about = await drive.DriveApi(client).about.get($fields: 'user');
    final user = about.user;
    if (user == null) return null;
    final result = DriveAccountUser(
      displayName: user.displayName,
      emailAddress: user.emailAddress,
    );
    return result.label == null ? null : result;
  } catch (_) {
    return null;
  }
}

/// Local-only storage for the connection's display label.
class DriveAccountLabelStore {
  static const String key = 'google_drive_account_label';

  Future<String?> read() async {
    try {
      final value = (await SharedPreferences.getInstance()).getString(key);
      return (value == null || value.trim().isEmpty) ? null : value;
    } catch (_) {
      return null; // a missing label must never break login-status checks
    }
  }

  Future<void> write(String? label) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clean = label?.trim();
      if (clean == null || clean.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, clean);
      }
    } catch (_) {
      // Label is cosmetic; failing to store it is not worth an error.
    }
  }
}
