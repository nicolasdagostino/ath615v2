enum BookingOccupancy { available, almostFull, full }

/// Shared threshold used when no gym-specific occupancy policy exists.
const double bookingAlmostFullThreshold = 0.8;

BookingOccupancy bookingOccupancy({
  required int bookedCount,
  required int capacity,
}) {
  if (capacity <= 0 || bookedCount < 0) return BookingOccupancy.available;
  if (bookedCount >= capacity) return BookingOccupancy.full;
  if (bookedCount / capacity >= bookingAlmostFullThreshold) {
    return BookingOccupancy.almostFull;
  }
  return BookingOccupancy.available;
}
