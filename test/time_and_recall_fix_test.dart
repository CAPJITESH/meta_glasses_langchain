import 'package:flutter_test/flutter_test.dart';
import 'package:qualcom_hacks/core/services/local_data_store.dart';
import 'package:qualcom_hacks/core/utils/parameter_normalizer.dart';
import 'package:qualcom_hacks/core/utils/time_resolver.dart';

void main() {
  group('ParameterNormalizer — time object repair', () {
    test('abbreviated relative units resolve ("m" -> minutes)', () {
      final params = ParameterNormalizer.normalize({
        'task': 'call mom',
        'time': {'type': 'relative', 'clock_time': null, 'date': null, 'amount': 10, 'unit': 'm'},
      }, featureId: 'set_reminder_v1', transcript: 'remind me to call mom in 10 minutes');

      final resolved = TimeResolver.resolve(
        params['time'] as Map<String, dynamic>,
        now: DateTime(2026, 7, 13, 9, 0),
      );
      expect(resolved.human, isNotNull);
      expect(resolved.machineIso, '2026-07-13T09:10');
    });

    test('am/pm clock_time is converted to 24h HH:MM', () {
      final params = ParameterNormalizer.normalize({
        'task': 'meeting',
        'time': {'type': 'absolute', 'clock_time': '5pm', 'date': 'today', 'amount': null, 'unit': null},
      });

      expect((params['time'] as Map)['clock_time'], '17:00');
      final resolved = TimeResolver.resolve(
        params['time'] as Map<String, dynamic>,
        now: DateTime(2026, 7, 13, 9, 0),
      );
      expect(resolved.human, '5:00 PM today');
    });

    test('seconds-bearing clock_time is trimmed to HH:MM', () {
      final params = ParameterNormalizer.normalize({
        'time': {'type': 'absolute', 'clock_time': '17:30:00', 'date': 'today', 'amount': null, 'unit': null},
      });
      expect((params['time'] as Map)['clock_time'], '17:30');
    });

    test('missing type is inferred from the filled fields', () {
      final absolute = ParameterNormalizer.normalize({
        'time': {'type': 'unknown', 'clock_time': '08:00', 'date': 'tomorrow', 'amount': null, 'unit': null},
      });
      expect((absolute['time'] as Map)['type'], 'absolute');

      final relative = ParameterNormalizer.normalize({
        'time': {'type': null, 'clock_time': null, 'date': null, 'amount': '5', 'unit': 'min'},
      });
      expect((relative['time'] as Map)['type'], 'relative');
      expect((relative['time'] as Map)['unit'], 'minutes');
    });

    test('items arriving as one string are split into a list', () {
      final params = ParameterNormalizer.normalize({
        'list_name': 'swimming',
        'items': 'goggles, cap and towel',
      });
      expect(params['items'], ['goggles', 'cap', 'towel']);
    });
  });

  group('LocalDataStore.lookupFuzzy — checklist recall', () {
    test('exact and partial names both resolve the stored list', () {
      final store = LocalDataStore.instance;
      store.storeList('swimming checklist', ['goggles', 'cap', 'towel']);

      final exact = store.lookupFuzzy('swimming checklist');
      expect(exact, isNotNull);
      expect(exact!.items, ['goggles', 'cap', 'towel']);

      final partial = store.lookupFuzzy('swimming');
      expect(partial, isNotNull);
      expect(partial!.queryType, 'list');

      final phrase = store.lookupFuzzy("what's on my swimming checklist");
      expect(phrase, isNotNull);

      expect(store.lookupFuzzy('groceries'), isNull);
    });
  });
}
