import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grannies_healthbar/models/care_plan.dart';
import 'package:grannies_healthbar/services/bdapps_service.dart';

class RealHttp extends HttpOverrides {}

Future<void> withProvider(
  Future<void> Function(BdappsService, List<Map<String, dynamic>>) run, {
  bool activateSubscription = true,
  bool registered = true,
  bool rejectSms = false,
  bool rejectSubscription = false,
}) async {
  await HttpOverrides.runWithHttpOverrides(() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final calls = <Map<String, dynamic>>[];
    server.listen((request) async {
      final body = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, dynamic>;
      calls.add({'path': request.uri.path, ...body});
      expect(body['applicationId'], 'test-app');
      expect(body['password'], 'test-password');
      request.response.headers.contentType = ContentType.json;
      final data = <String, dynamic>{'statusCode': 'S1000'};
      if (request.uri.path == '/subscription/getStatus') {
        data['subscriptionStatus'] = registered
            ? 'REGISTERED.'
            : 'UNREGISTERED.';
      } else if (request.uri.path == '/subscription/send') {
        if (rejectSubscription) {
          data['statusCode'] = 'E1000';
        } else {
          registered = activateSubscription;
        }
      } else if (request.uri.path == '/sms/send') {
        data['destinationResponses'] = [
          {
            'address': body['destinationAddresses'][0],
            'statusCode': rejectSms ? 'E1000' : 'S1000',
          },
        ];
      }
      request.response.write(jsonEncode(data));
      await request.response.close();
    });
    try {
      await run(
        BdappsService(
          applicationId: 'test-app',
          password: 'test-password',
          baseUrl: Uri.parse('http://127.0.0.1:${server.port}/'),
        ),
        calls,
      );
    } finally {
      await server.close(force: true);
    }
  }, RealHttp());
}

void main() {
  test(
    'direct registration uses action 1 and verifies provider status',
    () async {
      await withProvider((api, calls) async {
        expect(await api.isSubscribed('01812345678'), isFalse);
        await api.subscribe('01812345678');
        expect(calls.map((c) => c['path']), [
          '/subscription/getStatus',
          '/subscription/send',
          '/subscription/getStatus',
        ]);
        expect(calls[1]['subscriberId'], 'tel:8801812345678');
        expect(calls[1]['action'], '1');
        expect(calls.any((c) => c['path'].contains('debit')), isFalse);
      }, registered: false);
    },
  );

  test(
    'registration must be confirmed by the provider before completing',
    () async {
      await withProvider(
        (api, calls) async {
          await expectLater(
            api.subscribe('01812345678'),
            throwsA(isA<HttpException>()),
          );
          expect(calls.map((c) => c['path']), [
            '/subscription/send',
            '/subscription/getStatus',
          ]);
        },
        registered: false,
        activateSubscription: false,
      );
    },
  );

  test('SOS targets stored helper number with the requested message', () async {
    await withProvider((api, calls) async {
      await api.sendSos(
        CarePlan(
          grandmaCode: 'AB23',
          helperCode: 'XY89',
          age: 74,
          grandmaName: 'Rose',
          helperName: 'Sam',
          helperPhone: '+8801812345678',
          medicines: [],
        ),
      );
      expect(calls.single['destinationAddresses'], ['tel:8801812345678']);
      expect(
        calls.single['message'],
        'hi Sam, grandma has reached for the S.O.S button. Please call her back.',
      );
      expect(calls.single['encoding'], '0');
      expect(calls.single['deliveryStatusRequest'], '1');
    });
  });

  test('per-recipient SMS failure is not reported as success', () async {
    await withProvider((api, calls) async {
      await expectLater(
        api.sendSos(
          CarePlan(
            grandmaCode: 'AB23',
            helperCode: 'XY89',
            age: 74,
            grandmaName: 'Rose',
            helperName: 'Sam',
            helperPhone: '01812345678',
            medicines: [],
          ),
        ),
        throwsA(isA<HttpException>()),
      );
    }, rejectSms: true);
  });

  test(
    'provider rejects registration and missing numbers before sending',
    () async {
      await withProvider((api, calls) async {
        await expectLater(
          api.subscribe('01812345678'),
          throwsA(isA<HttpException>()),
        );
        expect(calls.length, 1);
        await expectLater(api.isSubscribed(''), throwsFormatException);
        expect(calls.length, 1);
      }, rejectSubscription: true);
    },
  );
}
