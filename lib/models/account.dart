/// A money account: a bank account, cash wallet or fixed deposit.
class Account {
  final String id;
  final String name;
  final String type; // bank | cash | fd
  final String colorHex;

  /// Balance the account had before any tracked transaction.
  /// Current balance is computed = openingBalance + transaction effects.
  final double openingBalance;

  const Account({
    required this.id,
    required this.name,
    required this.type,
    required this.colorHex,
    required this.openingBalance,
  });

  factory Account.fromMap(String id, Map<String, dynamic> m) => Account(
        id: id,
        name: (m['name'] ?? '') as String,
        type: (m['type'] ?? 'bank') as String,
        colorHex: (m['colorHex'] ?? '#3DEBA8') as String,
        openingBalance: (m['openingBalance'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'type': type,
        'colorHex': colorHex,
        'openingBalance': openingBalance,
      };

  Account copyWith({
    String? name,
    String? type,
    String? colorHex,
    double? openingBalance,
  }) =>
      Account(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        colorHex: colorHex ?? this.colorHex,
        openingBalance: openingBalance ?? this.openingBalance,
      );

  String get typeLabel => type == 'fd'
      ? 'Fixed Deposit'
      : type == 'cash'
          ? 'Cash'
          : 'Bank';
}
