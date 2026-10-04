import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/models/models.dart';

void main() {
  group('to24HourTime', () {
    test('uses the AM/PM choice', () {
      expect(to24HourTime('10:30', pm: false), '10:30');
      expect(to24HourTime('1:30', pm: true), '13:30');
      expect(to24HourTime('9', pm: false), '09:00');
    });

    test('maps 12 o\'clock to noon and midnight', () {
      expect(to24HourTime('12:00', pm: true), '12:00');
      expect(to24HourTime('12:15', pm: false), '00:15');
    });

    test('a typed am/pm wins over the toggle', () {
      expect(to24HourTime('2:45 pm', pm: false), '14:45');
      expect(to24HourTime('11 A.M.', pm: true), '11:00');
      expect(to24HourTime('3:05PM', pm: false), '15:05');
    });

    test('rejects anything that is not a 12-hour time', () {
      for (final bad in ['', '13:00', '0:30', '10:60', '10:5', 'noon', '14']) {
        expect(to24HourTime(bad, pm: false), isNull, reason: bad);
      }
    });
  });

  group('to12HourTime', () {
    test('splits stored times into clock text and PM', () {
      expect(to12HourTime('09:00'), ('9:00', false));
      expect(to12HourTime('13:45'), ('1:45', true));
      expect(to12HourTime('00:10'), ('12:10', false));
      expect(to12HourTime('12:00:00'), ('12:00', true));
    });

    test('round-trips through to24HourTime', () {
      for (final t in ['00:00', '08:30', '12:00', '15:15', '23:59']) {
        final (time, pm) = to12HourTime(t);
        expect(to24HourTime(time, pm: pm), t);
      }
    });
  });
}
