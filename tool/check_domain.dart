import 'dart:io';
import 'dart:convert';

import 'package:grannies_healthbar/models/care_plan.dart';
import 'package:grannies_healthbar/services/api_service.dart';

void check(bool condition, String description) {
  if (!condition) throw StateError(description);
  stdout.writeln('PASS $description');
}

Future<void> main() async {
  final plan = CarePlan(
    grandmaCode: 'AB23',
    helperCode: 'XY89',
    age: 74,
    grandmaName: 'Rose',
    helperName: 'Sam',
    medicines: [
      Medicine(name: 'Vitamin D', times: ['08:00', '20:30']),
    ],
  );
  check(
    plan.toWire().keys.single == 'AB23--XY89',
    'Pair key matches backend format',
  );
  check(
    (jsonDecode(plan.encode())['AB23--XY89']['Medicenes']['Vitamin D'] as List)
            .length ==
        2,
    'Multiple daily times serialize as valid JSON arrays',
  );
  final response = [
    {'text': 'malformed'},
    {'text': plan.encode()},
    {'text': plan.encode()},
  ];
  check(
    findPlan(response, 'AB23')?.age == 74,
    'Malformed rows do not hide valid GET records',
  );
  check(
    findPlan(response, 'AB2') == null,
    'Pairing requires exact code matching',
  );
  check(
    findPlan(response, 'AB23', helperCode: 'WRNG') == null,
    'Helper verification checks both codes',
  );
  check(
    findPlan({
          '0': {'text': plan.encode()},
        }, 'AB23')?.grandmaName ==
        'Rose',
    'Legacy indexed envelopes are supported',
  );
  check(
    ApiService('http://127.0.0.1:8000').endpoint.toString() ==
        'http://127.0.0.1:8000/',
    'Default local API root normalized correctly',
  );
  try {
    ApiService('localhost:8000').endpoint;
    throw StateError('Expected rejection');
  } on FormatException {
    stdout.writeln('PASS Invalid endpoint rejected');
  }
  final oversized = CarePlan(
    grandmaCode: 'AB23',
    helperCode: 'XY89',
    age: 74,
    grandmaName: 'R' * 1001,
    helperName: 'Sam',
    medicines: [],
  );
  try {
    await ApiService('http://127.0.0.1:8000').save(oversized);
    throw StateError('Expected rejection');
  } on FormatException {
    stdout.writeln('PASS Oversized plan rejected before networking');
  }
  final wrongTime = plan.toWire();
  (wrongTime[plan.key] as Map)['Medicenes'] = {
    'Vitamin D': ['25:00'],
  };
  check(
    findPlan([
          {'text': jsonEncode(wrongTime)},
        ], 'AB23') ==
        null,
    'Invalid server schedules cannot enter the dashboard',
  );
}
