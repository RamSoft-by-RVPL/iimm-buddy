import 'package:attendance_planner/menu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('everyday dishes are sides, the day\'s own dishes are not', () {
    for (final s in ['Green Salad', 'Chapati / Fulka', 'Plain Rice / Jeera Rice', 'Papad', 'Mixed Pickle', 'Tea / Coffee / Milk', 'Banana', 'Sauce']) {
      expect(isSide(s), isTrue, reason: s);
    }
    for (final s in ['Papadi Chat', 'Dal Makhani', 'Paneer Butter Masala', 'Pasta', 'Kadi Pakoda', 'Steamed Momos']) {
      expect(isSide(s), isFalse, reason: s);
    }
  });

  test('meal hours follow the times posted at the mess', () {
    expect(mealHours('Breakfast', 0), '7:30 to 10:15 am');
    expect(mealHours('Lunch', 1), '12:10 to 3:00 pm');
    expect(mealHours('Evening Snacks', 2), '5:00 to 6:15 pm');
    expect(mealHours('Dinner', 3), '8:15 to 10:30 pm');
    expect(mealEnds('Lunch', 1), '3:00 pm');
    DateTime at(int h, int m) => DateTime(2026, 11, 24, h, m);
    expect(isServing('Lunch', 1, at(12, 10)), isTrue);
    expect(isServing('Lunch', 1, at(14, 59)), isTrue);
    expect(isServing('Lunch', 1, at(15, 0)), isFalse);
    expect(isServing('Lunch', 1, at(11, 0)), isFalse);
    expect(isServing('Dinner', 3, at(19, 0)), isFalse);
  });
}
