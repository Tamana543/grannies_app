import 'dart:convert';
import 'dart:io';

import '../models/care_plan.dart';

class BdappsService {
  BdappsService({
    this.applicationId = const String.fromEnvironment('BDAPPS_APPLICATION_ID'),
    this.password = const String.fromEnvironment('BDAPPS_PASSWORD'),
    Uri? baseUrl,
  }) : baseUrl = baseUrl ?? Uri.parse('https://developer.bdapps.com/');

  final String applicationId, password;
  final Uri baseUrl;

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    if (applicationId.isEmpty || password.isEmpty) {
      throw const HttpException('The SOS service has not been configured yet.');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .postUrl(baseUrl.resolve(path))
          .timeout(const Duration(seconds: 15));
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'applicationId': applicationId,
          'password': password,
          ...payload,
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw const HttpException(
          'The SOS service is unavailable. Please try again or call your helper.',
        );
      }
      final data = jsonDecode(body) as Map<String, dynamic>;
      if (data['statusCode'] != 'S1000') {
        // Show only the provider status code; responses can contain subscriber details.
        throw HttpException(
          'bdapps could not complete this request (${data['statusCode'] ?? 'unknown'}). Please try again or call your helper.',
        );
      }
      return data;
    } finally {
      client.close(force: true);
    }
  }

  String _address(String phone) {
    if (!validPhone(phone)) {
      throw const FormatException(
        'Ask your helper to add a valid phone number in their app.',
      );
    }
    return 'tel:${normalizePhone(phone)}';
  }

  bool _registered(Map<String, dynamic> data) =>
      '${data['subscriptionStatus']}'
          .toUpperCase()
          .replaceAll('.', '')
          .trim() ==
      'REGISTERED';

  Future<bool> isSubscribed(String phone) async => _registered(
    await _post('subscription/getStatus', {'subscriberId': _address(phone)}),
  );

  Future<void> subscribe(String phone) async {
    await _post('subscription/send', {
      'subscriberId': _address(phone),
      'action': '1',
    });
    if (!await isSubscribed(phone)) {
      throw const HttpException(
        'bdapps has not confirmed the family subscription. No SOS message was sent. Please call your helper.',
      );
    }
  }

  Future<void> sendSos(CarePlan plan) async {
    final destination = _address(plan.helperPhone);
    final data = await _post('sms/send', {
      'version': '1.0',
      'message':
          'hi ${plan.helperName}, grandma has reached for the S.O.S button. Please call her back.',
      'destinationAddresses': [destination],
      'deliveryStatusRequest': '1',
      'encoding': '0',
    });
    final responses = data['destinationResponses'];
    if (responses is! List ||
        !responses.any(
          (row) =>
              row is Map &&
              row['address'] == destination &&
              row['statusCode'] == 'S1000',
        )) {
      throw const HttpException(
        'bdapps did not accept the SOS message for your helper. Please call them directly.',
      );
    }
  }
}
