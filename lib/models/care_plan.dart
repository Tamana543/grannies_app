import 'dart:convert';

const codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
bool validCode(String code) => RegExp(r'^[A-Z0-9]{4}$').hasMatch(code);

String normalizePhone(String value) {
  var digits = value.replaceAll(RegExp(r'[\s()+-]'), '');
  if (digits.startsWith('00')) digits = digits.substring(2);
  if (RegExp(r'^01[3-9]\d{8}$').hasMatch(digits)) digits = '88$digits';
  return digits;
}

bool validPhone(String value) =>
    RegExp(r'^8801[3-9]\d{8}$').hasMatch(normalizePhone(value));

class Medicine {
  Medicine({required this.name, required this.times});
  final String name;
  final List<String> times;
  Map<String, dynamic> toJson() => {'name': name, 'times': times};
  factory Medicine.fromJson(Map<String, dynamic> json) => Medicine(
    name: json['name'] as String,
    times: List<String>.from(json['times'] as List),
  );
}

class CarePlan {
  CarePlan({
    required this.grandmaCode,
    required this.helperCode,
    required this.age,
    required this.grandmaName,
    required this.helperName,
    required this.medicines,
    this.helperPhone = '',
  });
  final String grandmaCode, helperCode, grandmaName, helperName;
  final String helperPhone;
  final int age;
  final List<Medicine> medicines;
  String get key => '$grandmaCode--$helperCode';
  Map<String, dynamic> get details => {
    'granmasAge': age,
    'granmasName': grandmaName,
    'childName': helperName,
    if (helperPhone.isNotEmpty) 'helperPhone': normalizePhone(helperPhone),
    'Medicenes': {
      for (final medicine in medicines) medicine.name: medicine.times,
    },
  };
  Map<String, dynamic> toWire() => {key: details};
  String encode() => jsonEncode(toWire());
  CarePlan withHelperPhone(String phone) => CarePlan(
    grandmaCode: grandmaCode,
    helperCode: helperCode,
    age: age,
    grandmaName: grandmaName,
    helperName: helperName,
    medicines: medicines,
    helperPhone: normalizePhone(phone),
  );
  factory CarePlan.fromEntry(String key, Map<String, dynamic> value) {
    final codes = key.split('--');
    if (codes.length != 2 || !validCode(codes[0]) || !validCode(codes[1])) {
      throw const FormatException('Invalid pairing code');
    }
    final age = int.parse('${value['granmasAge']}');
    if (age < 1 || age > 130) throw const FormatException('Invalid age');
    final raw = value['Medicenes'] as Map;
    final medicines = raw.entries.map((entry) {
      final times = entry.value is Map
          ? (entry.value as Map).values.map((e) => '$e').toList()
          : List<String>.from(entry.value as List);
      if (times.isEmpty ||
          times.any((t) => !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(t))) {
        throw const FormatException('Invalid medicine times');
      }
      return Medicine(name: '${entry.key}', times: times..sort());
    }).toList();
    return CarePlan(
      grandmaCode: codes[0],
      helperCode: codes[1],
      age: age,
      grandmaName: value['granmasName'] as String,
      helperName: value['childName'] as String,
      helperPhone: value['helperPhone'] as String? ?? '',
      medicines: medicines,
    );
  }
}

/// Records arrive newest first from FastAPI. Ignore unrelated/malformed rows.
CarePlan? findPlan(dynamic response, String grandmaCode, {String? helperCode}) {
  final records = response is List
      ? response
      : (response is Map ? response.values : const []);
  for (final record in records) {
    try {
      final dynamic payload = record is Map && record.containsKey('text')
          ? jsonDecode(record['text'] as String)
          : record;
      if (payload is! Map) continue;
      for (final entry in payload.entries) {
        final plan = CarePlan.fromEntry(
          '${entry.key}',
          Map<String, dynamic>.from(entry.value as Map),
        );
        if (plan.grandmaCode == grandmaCode &&
            (helperCode == null || plan.helperCode == helperCode)) {
          return plan;
        }
      }
    } on Object {
      continue;
    }
  }
  return null;
}
