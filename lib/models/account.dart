/// A money account: a bank account, cash wallet or fixed deposit.
class Account {
  final String id;
  final String name;
  final String type; // bank | cash | fd
  final String colorHex;

  /// Balance the account had before any tracked transaction.
  /// Current balance is computed = openingBalance + transaction effects.
  final double openingBalance;

  /// Card/account number tails (e.g. "6709") used to match incoming bank SMS
  /// to this account for auto-import. Empty = SMS auto-import off for it.
  final List<String> smsIds;

  const Account({
    required this.id,
    required this.name,
    required this.type,
    required this.colorHex,
    required this.openingBalance,
    this.smsIds = const [],
  });

  factory Account.fromMap(String id, Map<String, dynamic> m) => Account(
        id: id,
        name: (m['name'] ?? '') as String,
        type: (m['type'] ?? 'bank') as String,
        colorHex: (m['colorHex'] ?? '#3DEBA8') as String,
        openingBalance: (m['openingBalance'] as num?)?.toDouble() ?? 0,
        smsIds: ((m['smsIds'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'type': type,
        'colorHex': colorHex,
        'openingBalance': openingBalance,
        'smsIds': smsIds,
      };

  Account copyWith({
    String? name,
    String? type,
    String? colorHex,
    double? openingBalance,
    List<String>? smsIds,
  }) =>
      Account(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        colorHex: colorHex ?? this.colorHex,
        openingBalance: openingBalance ?? this.openingBalance,
        smsIds: smsIds ?? this.smsIds,
      );

  String get typeLabel => type == 'fd'
      ? 'Fixed Deposit'
      : type == 'cash'
          ? 'Cash'
          : 'Bank';
}
