/// Fixed placeholder label ids, seeded in migration v1. Never change these —
/// they are referenced by id from app code and by row data on-device.
const String kNoCategoryId = '00000000-0000-7000-8000-000000000001';
const String kNoPaymentMethodId = '00000000-0000-7000-8000-000000000002';

/// 0-indexed max depth -> 3 levels (0, 1, 2).
const int kMaxDepth = 2;

/// Monday. One-line change to DateTime.sunday to shift week bucketing.
const int kWeekStartsOn = DateTime.monday;
