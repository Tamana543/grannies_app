import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grannies_healthbar/models/care_plan.dart';
import 'package:grannies_healthbar/services/api_service.dart';
import 'package:grannies_healthbar/services/app_store.dart';

CarePlan examplePlan() => CarePlan(
  grandmaCode: 'AB23',
  helperCode: 'XY89',
  age: 74,
  grandmaName: 'Rose',
  helperName: 'Sam',
  helperPhone: '8801812345678',
  medicines: [
    Medicine(name: 'Vitamin D', times: ['08:00', '20:30']),
  ],
);

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('GET selects exact grandma code in newest-first records, skipping malformed rows', () {
    final old = examplePlan();
    final recent = CarePlan(
      grandmaCode: 'AB23',
      helperCode: 'XY89',
      age: 75,
      grandmaName: 'Rose',
      helperName: 'Sam',
      medicines: old.medicines,
    );
    final response = [
      {'text': 'broken'},
      {'text': recent.encode()},
      {'text': old.encode()},
    ];
    expect(findPlan(response, 'AB23')?.age, 75);
    expect(findPlan(response, 'AB2'), isNull);
    expect(findPlan(response, 'AB23', helperCode: 'AAAA'), isNull);
    expect(
      findPlan({
        '0': {'text': old.encode()},
      }, 'AB23')?.medicines.single.times,
      ['08:00', '20:30'],
    );
  });
  test('POST uses an encoded JSON path and GET verifies the asynchronously saved record', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      String? saved;
      var gets = 0;
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.method == 'POST') {
          saved = request.uri.pathSegments.single;
          expect(await utf8.decoder.bind(request).join(), isEmpty);
          request.response.write('200');
        } else {
          gets++;
          request.response.write(
            jsonEncode(
              gets == 1
                  ? []
                  : [
                      {'text': saved, 'date': '2026-11-21', 'time': '10:00:00'},
                    ],
            ),
          );
        }
        await request.response.close();
      });
      await ApiService('http://127.0.0.1:${server.port}').save(examplePlan());
      expect(saved, examplePlan().encode());
      expect(gets, 2);
    }, _RealHttpOverrides());
  });
  test(
    'identity, onboarding draft, plan and pending sync survive restart',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'grannies_store_test',
      );
      addTearDown(() => directory.delete(recursive: true));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            native,
            (call) async => 'Test Android model',
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(native, null),
      );
      final original = AppStore(directory);
      await original.load();
      expect(original.code.length, 4);
      original.role = 'helper';
      original.draft = {'age': '74'};
      await original.savePlan(examplePlan());
      final reopened = AppStore(directory);
      await reopened.load();
      expect(reopened.code, original.code);
      expect(reopened.role, 'helper');
      expect(reopened.draft['age'], '74');
      expect(reopened.plan?.encode(), examplePlan().encode());
      expect(reopened.pendingSync, isTrue);
    },
  );
  test(
    'invalid endpoints and oversized plans fail before making requests',
    () async {
      expect(
        () => ApiService('localhost:8000').endpoint,
        throwsFormatException,
      );
      final plan = CarePlan(
        grandmaCode: 'AB23',
        helperCode: 'XY89',
        age: 74,
        grandmaName: 'R' * 1001,
        helperName: 'Sam',
        medicines: [],
      );
      await expectLater(
        ApiService('http://127.0.0.1:8000').save(plan),
        throwsFormatException,
      );
    },
  );
}
