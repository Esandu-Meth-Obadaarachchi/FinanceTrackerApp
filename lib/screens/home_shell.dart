import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../services/auth_service.dart';
import '../theme/app_text.dart';
import '../theme/palette.dart';
import '../theme/theme_controller.dart';
import '../utils/formatters.dart';
import 'accounts_screen.dart';
import 'dashboard_screen.dart';
import 'loans_screen.dart';
import 'modals/sheets.dart';
import 'tax_screen.dart';
import 'transactions_screen.dart';

enum AppScreen { dashboard, transactions, accounts, loans, tax }

/// Top-level frame: top bar, active screen, bottom nav with centre add button.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  AppScreen _screen = AppScreen.dashboard;
  late String _month = monthKeyOf(DateTime.now());

  static const _titles = {
    AppScreen.dashboard: 'Overview',
    AppScreen.transactions: 'Transactions',
    AppScreen.accounts: 'Accounts',
    AppScreen.loans: 'Loans',
    AppScreen.tax: 'Tax Report',
  };

  void _onAddPressed() {
    if (_screen == AppScreen.loans) {
      showAddLoanSheet(context);
    } else {
      showTypePicker(context);
    }
  }

  Widget _body() {
    switch (_screen) {
      case AppScreen.dashboard:
        return DashboardScreen(month: _month);
      case AppScreen.transactions:
        return TransactionsScreen(month: _month);
      case AppScreen.accounts:
        return const AccountsScreen();
      case AppScreen.loans:
        return const LoansScreen();
      case AppScreen.tax:
        return const TaxScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;

    return Scaffold(
      backgroundColor: colors.bg,
      body: Stack(
        children: [
          Column(
            children: [
              _TopBar(
                title: _titles[_screen]!,
                colors: colors,
                showMonths: _screen == AppScreen.dashboard ||
                    _screen == AppScreen.transactions,
                month: _month,
                onMonth: (m) => setState(() => _month = m),
                accountsActive: _screen == AppScreen.accounts,
                onWallet: () =>
                    setState(() => _screen = AppScreen.accounts),
              ),
              Expanded(child: _body()),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomNav(
              colors: colors,
              active: _screen,
              onSelect: (s) => setState(() => _screen = s),
              onAdd: _onAddPressed,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.colors,
    required this.showMonths,
    required this.month,
    required this.onMonth,
    required this.accountsActive,
    required this.onWallet,
  });

  final String title;
  final Palette colors;
  final bool showMonths;
  final String month;
  final ValueChanged<String> onMonth;
  final bool accountsActive;
  final VoidCallback onWallet;

  @override
  Widget build(BuildContext context) {
    final theme = context.read<ThemeController>();
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, MediaQuery.of(context).padding.top + 12, 12, 10),
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: sans(
                      size: 20,
                      weight: FontWeight.w800,
                      color: colors.text),
                ),
              ),
              _iconBtn(
                icon: Icons.account_balance_wallet_outlined,
                active: accountsActive,
                colors: colors,
                onTap: onWallet,
              ),
              const SizedBox(width: 8),
              _iconBtn(
                icon: theme.isDark ? Icons.light_mode : Icons.dark_mode,
                active: false,
                colors: colors,
                onTap: theme.toggle,
              ),
              const SizedBox(width: 8),
              _ProfileMenu(colors: colors),
            ],
          ),
          if (showMonths) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 26,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final m in recentMonths(12))
                    GestureDetector(
                      onTap: () => onMonth(m),
                      child: Container(
                        margin: const EdgeInsets.only(right: 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: m == month
                              ? const Color(0xFF3DEBA8)
                                  .withValues(alpha: 0.13)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Center(
                          child: Text(
                            fmtMonthShort(m),
                            style: sans(
                              size: 11,
                              weight: m == month
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: m == month
                                  ? const Color(0xFF3DEBA8)
                                  : colors.sub,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required bool active,
    required Palette colors,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF3DEBA8).withValues(alpha: 0.13)
              : colors.inputBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 18,
          color: active ? const Color(0xFF3DEBA8) : colors.sub,
        ),
      ),
    );
  }
}

class _ProfileMenu extends StatelessWidget {
  const _ProfileMenu({required this.colors});
  final Palette colors;

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    final user = auth.currentUser;
    final email = user?.email ?? '';
    final initial = (user?.displayName?.isNotEmpty == true
            ? user!.displayName![0]
            : (email.isNotEmpty ? email[0] : '?'))
        .toUpperCase();

    return PopupMenuButton<String>(
      offset: const Offset(0, 44),
      color: colors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.border),
      ),
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user?.displayName ?? 'Signed in',
                  style: sans(
                      size: 13,
                      weight: FontWeight.w700,
                      color: colors.text)),
              Text(email, style: sans(size: 11, color: colors.sub)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'signout',
          child: Row(
            children: [
              const Icon(Icons.logout, size: 16, color: Color(0xFFFF5C7A)),
              const SizedBox(width: 10),
              Text('Sign out',
                  style: sans(size: 13, color: const Color(0xFFFF5C7A))),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          enabled: false,
          height: 32,
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: colors.muted),
              const SizedBox(width: 8),
              Text('Version $kAppVersion',
                  style: sans(size: 12, color: colors.muted)),
            ],
          ),
        ),
      ],
      onSelected: (v) {
        if (v == 'signout') auth.signOut();
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF3DEBA8), Color(0xFF60A5FA)],
          ),
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        child: Center(
          child: Text(
            initial,
            style: sans(
                size: 15,
                weight: FontWeight.w700,
                color: const Color(0xFF0B0D14)),
          ),
        ),
      ),
    );
  }
}

// ── Bottom navigation ─────────────────────────────────────────────────────
class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.colors,
    required this.active,
    required this.onSelect,
    required this.onAdd,
  });

  final Palette colors;
  final AppScreen active;
  final ValueChanged<AppScreen> onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.only(bottom: bottomInset > 0 ? bottomInset : 8),
      decoration: BoxDecoration(
        color: colors.isDark ? const Color(0xFF0F1520) : Colors.white,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _navItem(Icons.home_outlined, Icons.home_rounded, 'Home',
              AppScreen.dashboard),
          _navItem(Icons.receipt_long_outlined, Icons.receipt_long, 'Txns',
              AppScreen.transactions),
          _addButton(),
          _navItem(Icons.people_outline, Icons.people, 'Loans',
              AppScreen.loans),
          _navItem(Icons.description_outlined, Icons.description, 'Tax',
              AppScreen.tax),
        ],
      ),
    );
  }

  Widget _navItem(
      IconData icon, IconData iconActive, String label, AppScreen screen) {
    final isActive = active == screen;
    final color = isActive
        ? const Color(0xFF3DEBA8)
        : (colors.isDark
            ? const Color(0xFF4A5270)
            : const Color(0xFF9BA8C0));
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelect(screen),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isActive ? iconActive : icon, size: 22, color: color),
              const SizedBox(height: 3),
              Text(
                label,
                style: sans(
                  size: 10,
                  weight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addButton() {
    return Expanded(
      child: Center(
        child: Transform.translate(
          offset: const Offset(0, -10),
          child: GestureDetector(
            onTap: onAdd,
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF3DEBA8), Color(0xFF60A5FA)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF3DEBA8).withValues(alpha: 0.45),
                    blurRadius: 18,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.add,
                  size: 26, color: Color(0xFF0B0D14)),
            ),
          ),
        ),
      ),
    );
  }
}
