// Put this file in your Flutter project at: lib/family_code_login.dart
//
// pubspec.yaml needs these two packages (run `flutter pub get` after adding):
//   http: ^1.2.0
//   shared_preferences: ^2.2.0

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Same server folder the website uses.
const String kApiBase = 'https://bdappsdigitalapps.com/auw26/AUW242106/';

/// Same keys idea as the website (gh_family_code / gh_role).
const String kCodeKey = 'gh_family_code';
const String kRoleKey = 'gh_role';

class FamilyLoginResult {
  final bool ok;
  final String message;
  final Map<String, dynamic>? family;
  const FamilyLoginResult(this.ok, this.message, [this.family]);
}

/// Keeps only letters and numbers, upper-case, like the website does.
String cleanFamilyCode(String input) =>
    input.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// Checks the code against the database (GET family.php?code=XXXX).
/// If the code exists, it is saved on the phone and the family data is returned.
/// [role] is 'helper' or 'grandma'.
Future<FamilyLoginResult> loginWithFamilyCode(
  String input, {
  String role = 'helper',
}) async {
  final code = cleanFamilyCode(input);
  if (code.length != 4) {
    return const FamilyLoginResult(false, 'Enter the 4-character family code.');
  }

  try {
    final uri = Uri.parse('${kApiBase}family.php')
        .replace(queryParameters: {'code': code});
    final response = await http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 15));

    final decoded = jsonDecode(response.body);
    final body = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};

    if (response.statusCode == 404) {
      return const FamilyLoginResult(
        false,
        'That code was not found. Check it and try again.',
      );
    }
    if (response.statusCode != 200 || body['family'] == null) {
      final error = body['error']?.toString();
      return FamilyLoginResult(
        false,
        (error == null || error.isEmpty) ? 'Could not check the code.' : error,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kCodeKey, code);
    await prefs.setString(kRoleKey, role);

    return FamilyLoginResult(
      true,
      'Welcome back!',
      Map<String, dynamic>.from(body['family'] as Map),
    );
  } catch (_) {
    return const FamilyLoginResult(
      false,
      'Could not reach the server. Check your connection.',
    );
  }
}

/// Call this when the app starts: returns the saved code and role if the user
/// already logged in before, so they can skip the login screen.
Future<({String code, String role})?> savedLogin() async {
  final prefs = await SharedPreferences.getInstance();
  final code = prefs.getString(kCodeKey) ?? '';
  final role = prefs.getString(kRoleKey) ?? '';
  if (code.length != 4) return null;
  return (code: code, role: role.isEmpty ? 'helper' : role);
}

// ---------------------------------------------------------------------------
// How to use it on your login button:
//
//   final result = await loginWithFamilyCode(codeController.text, role: 'helper');
//   if (!mounted) return;
//   if (result.ok) {
//     // go to the dashboard, result.family has grandma_name, medicines, etc.
//   } else {
//     ScaffoldMessenger.of(context)
//         .showSnackBar(SnackBar(content: Text(result.message)));
//   }
// ---------------------------------------------------------------------------
