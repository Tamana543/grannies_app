// Replace lib/services/api_service.dart with this file.
//
// It talks to the same PHP API as the website (family.php on cPanel), so a
// family code created or saved on the website can be used in the app too.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/care_plan.dart';

class _Reply {
  _Reply(this.status, this.body);
  final int status;
  final Map<String, dynamic> body;
}

class ApiService {
  ApiService(this.address);
  final String address;

  /// The server folder with a trailing slash (also used by the tests and tools).
  Uri get endpoint {
    final uri = Uri.tryParse(address.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException(
        'Enter a full HTTP or HTTPS server address without a query.',
      );
    }
    return uri.replace(
      path: uri.path.endsWith('/') ? uri.path : '${uri.path}/',
    );
  }

  Uri _url(String file, [Map<String, String>? query]) {
    final base = endpoint;
    return base.replace(path: '${base.path}$file', queryParameters: query);
  }

  Future<_Reply> _send(
    String method,
    Uri uri, {
    Map<String, dynamic>? json,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .openUrl(method, uri)
          .timeout(const Duration(seconds: 10));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (json != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(json));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final text = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 10));
      var body = <String, dynamic>{};
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) body = decoded;
      } catch (_) {
        // Not JSON; the status code still tells us what happened.
      }
      return _Reply(response.statusCode, body);
    } finally {
      client.close(force: true);
    }
  }

  String _message(_Reply reply, String fallback) {
    final error = reply.body['error'];
    return error == null || '$error'.isEmpty ? fallback : '$error';
  }

  /// Returns the family row for [code], or null when the code does not exist.
  Future<Map<String, dynamic>?> _family(String code) async {
    final reply = await _send('GET', _url('family.php', {'code': code}));
    if (reply.status == 404) return null;
    if (reply.status != 200 || reply.body['family'] is! Map) {
      throw HttpException(_message(reply, 'Server returned ${reply.status}.'));
    }
    return Map<String, dynamic>.from(reply.body['family'] as Map);
  }

  /// Makes sure this code exists in the database (safe to call many times).
  /// Grandma's code is registered this way so a helper can log in with it.
  Future<void> registerCode(String code) async {
    final reply = await _send(
      'POST',
      _url('family.php'),
      json: {'action': 'register_code', 'code': code},
    );
    if (reply.status != 200 || reply.body['ok'] != true) {
      throw HttpException(_message(reply, 'Could not register the code.'));
    }
  }

  /// Helper login: returns the family for [code] (fields can be empty if the
  /// family has not been filled in yet), or null if the code is unknown.
  Future<CarePlan?> lookup(String code, {String? helperCode}) async {
    final row = await _family(code);
    return row == null ? null : _toPlan(row, code, helperCode ?? code);
  }

  /// Grandma polling: returns the care plan once a helper has filled it in.
  Future<CarePlan?> fetch(String grandmaCode, {String? helperCode}) async {
    final plan = await lookup(grandmaCode, helperCode: helperCode);
    if (plan == null || (plan.grandmaName.isEmpty && plan.medicines.isEmpty)) {
      return null;
    }
    return plan;
  }

  Future<void> save(CarePlan plan) async {
    // Keep the emergency number that may have been saved on the website.
    final existing = await _family(plan.grandmaCode);
    final sos = '${existing?['sos_phone'] ?? ''}';
    final reply = await _send(
      'POST',
      _url('family.php'),
      json: {
        'code': plan.grandmaCode,
        'grandmaName': plan.grandmaName,
        'grandmaAge': plan.age,
        'helperName': plan.helperName,
        'helperPhone': plan.helperPhone,
        'sosPhone': sos,
        'medicines': [
          for (final medicine in plan.medicines)
            {'name': medicine.name, 'times': medicine.times},
        ],
      },
    );
    if (reply.status != 200 || reply.body['ok'] != true) {
      throw HttpException(_message(reply, 'The server could not save the plan.'));
    }
  }

  CarePlan _toPlan(
    Map<String, dynamic> row,
    String grandmaCode,
    String helperCode,
  ) {
    final medicines = <Medicine>[];
    final raw = row['medicines'];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final name = '${item['name'] ?? ''}'.trim();
        final times = <String>[
          if (item['times'] is List)
            for (final time in item['times'] as List) '$time',
        ];
        if (name.isEmpty || times.isEmpty) continue;
        medicines.add(Medicine(name: name, times: times));
      }
    }
    final age = row['grandma_age'];
    return CarePlan(
      grandmaCode: grandmaCode,
      helperCode: helperCode,
      age: age is num ? age.toInt() : int.tryParse('${age ?? ''}') ?? 0,
      grandmaName: '${row['grandma_name'] ?? ''}',
      helperName: '${row['helper_name'] ?? ''}',
      helperPhone: _appPhone('${row['helper_phone'] ?? ''}'),
      medicines: medicines,
    );
  }

  /// The server stores numbers like tel:8801812345678; the app expects
  /// +8801812345678 or 01812345678.
  String _appPhone(String stored) {
    final digits = stored.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    return digits.startsWith('880') ? '+$digits' : digits;
  }
}