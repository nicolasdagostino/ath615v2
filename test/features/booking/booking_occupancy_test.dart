import 'package:ath615v2/features/booking/presentation/booking_occupancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the shared eighty percent almost-full threshold', () {
    expect(
      bookingOccupancy(bookedCount: 7, capacity: 10),
      BookingOccupancy.available,
    );
    expect(
      bookingOccupancy(bookedCount: 8, capacity: 10),
      BookingOccupancy.almostFull,
    );
    expect(
      bookingOccupancy(bookedCount: 10, capacity: 10),
      BookingOccupancy.full,
    );
  });
}
