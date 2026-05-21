// Number and date formatting helpers, mirroring the standalone HTML.

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const _monthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Adds thousands separators to an integer-like string.
String _group(String digits) {
  final buf = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return buf.toString();
}

/// Compact form: 1.2M, 45k, 6,800 — used in pills and headers.
String fmt(num n) {
  final abs = n.abs();
  if (abs >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (abs >= 1000) {
    return '${(n / 1000).toStringAsFixed(abs >= 10000 ? 0 : 1)}k';
  }
  final neg = n < 0 ? '-' : '';
  return '$neg${_group(abs.round().toString())}';
}

/// Full form with two decimals: "270,500.00" (no currency prefix).
String fmtFull(num n) {
  final abs = n.abs();
  final fixed = abs.toStringAsFixed(2);
  final parts = fixed.split('.');
  return '${_group(parts[0])}.${parts[1]}';
}

/// "22 May 2026" from a YYYY-MM-DD string.
String fmtDate(String dateStr) {
  final d = DateTime.tryParse(dateStr);
  if (d == null) return dateStr;
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

/// "22 May" from a YYYY-MM-DD string.
String fmtDateShort(String dateStr) {
  final d = DateTime.tryParse(dateStr);
  if (d == null) return dateStr;
  return '${d.day} ${_months[d.month - 1]}';
}

/// "May 2026" from a YYYY-MM key.
String fmtMonthLong(String monthKey) {
  final parts = monthKey.split('-');
  if (parts.length < 2) return monthKey;
  final m = int.tryParse(parts[1]) ?? 1;
  return '${_monthsLong[m - 1]} ${parts[0]}';
}

/// "Mar 26" short label for the month selector pills.
String fmtMonthShort(String monthKey) {
  final parts = monthKey.split('-');
  if (parts.length < 2) return monthKey;
  final m = int.tryParse(parts[1]) ?? 1;
  final yy = parts[0].substring(2);
  return '${_months[m - 1]} $yy';
}

/// A YYYY-MM key for a given date.
String monthKeyOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

/// A YYYY-MM-DD key for a given date.
String dateKeyOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Rolling list of the last [count] month keys, oldest first, ending this month.
List<String> recentMonths({int count = 12}) {
  final now = DateTime.now();
  final list = <String>[];
  for (int i = count - 1; i >= 0; i--) {
    final d = DateTime(now.year, now.month - i, 1);
    list.add(monthKeyOf(d));
  }
  return list;
}
