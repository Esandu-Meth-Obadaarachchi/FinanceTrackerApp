import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/messaging_service.dart';
import '../services/notification_service.dart';
import '../services/sms_service.dart';
import '../state/app_state.dart';
import '../theme/app_text.dart';
import '../theme/palette.dart';
import '../theme/theme_controller.dart';
import '../utils/formatters.dart';
import '../utils/responsive.dart';
import 'accounts_screen.dart';
import 'dashboard_screen.dart';
import 'loans_screen.dart';
import 'modals/sheets.dart';
import 'settings_screen.dart';
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

  late final AppState _appState;
  bool _smsStarted = false;

  @override
  void initState() {
    super.initState();
    // Runs once per signed-in session (HomeShell is keyed by uid). Ask for
    // notification permission, re-arm daily reminders, subscribe to broadcasts.
    _appState = context.read<AppState>();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await NotificationService.instance.requestPermissions();
      await NotificationService.instance.rearmDailyReminders();
      await MessagingService.instance.subscribeUser(_appState.uid);
    });
    // SMS auto-import needs accounts loaded to map tails — wait for first load.
    _appState.addListener(_maybeStartSms);
    _maybeStartSms();
  }

  void _maybeStartSms() {
    if (_smsStarted || _appState.isLoading) return;
    _smsStarted = true;
    SmsService.instance.startIfEnabled(_appState);
  }

  @override
  void dispose() {
    _appState.removeListener(_maybeStartSms);
    super.dispose();
  }

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
    final showMonths = _screen == AppScreen.dashboard ||
        _screen == AppScreen.transactions;

    return Scaffold(
      backgroundColor: colors.bg,
      body: context.isWide
          ? Row(
              children: [
                _SideNav(
                  colors: colors,
                  active: _screen,
                  onSelect: (s) => setState(() => _screen = s),
                  onAdd: _onAddPressed,
                ),
                Expanded(
                  child: Column(
                    children: [
                      _DesktopTopBar(
                        title: _titles[_screen]!,
                        colors: colors,
                        showMonths: showMonths,
                        month: _month,
                        onMonth: (m) => setState(() => _month = m),
                      ),
                      Expanded(child: _body()),
                    ],
                  ),
                ),
              ],
            )
          : Stack(
              children: [
                Column(
                  children: [
                    _TopBar(
                      title: _titles[_screen]!,
                      colors: colors,
                      showMonths: showMonths,
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

// ── Desktop side rail ─────────────────────────────────────────────────────
const _navEntries = <(AppScreen, IconData, IconData, String)>[
  (AppScreen.dashboard, Icons.home_outlined, Icons.home_rounded, 'Overview'),
  (
    AppScreen.transactions,
    Icons.receipt_long_outlined,
    Icons.receipt_long,
    'Transactions'
  ),
  (
    AppScreen.accounts,
    Icons.account_balance_wallet_outlined,
    Icons.account_balance_wallet,
    'Accounts'
  ),
  (AppScreen.loans, Icons.people_outline, Icons.people, 'Loans'),
  (AppScreen.tax, Icons.description_outlined, Icons.description, 'Tax Report'),
];

class _SideNav extends StatelessWidget {
  const _SideNav({
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
    final theme = context.watch<ThemeController>();
    return Container(
      width: 248,
      decoration: BoxDecoration(
        color: colors.isDark ? const Color(0xFF0F1520) : Colors.white,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset('assets/logo.png',
                      width: 32, height: 32, fit: BoxFit.cover),
                ),
                const SizedBox(width: 10),
                Text('FinTrack',
                    style: sans(
                        size: 18,
                        weight: FontWeight.w800,
                        color: colors.text)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: _addButton(),
          ),
          const SizedBox(height: 20),
          for (final (screen, icon, iconActive, label) in _navEntries)
            _navItem(screen, icon, iconActive, label),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: InkWell(
              onTap: theme.toggle,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                child: Row(
                  children: [
                    Icon(theme.isDark ? Icons.light_mode : Icons.dark_mode,
                        size: 19, color: colors.sub),
                    const SizedBox(width: 12),
                    Text(theme.isDark ? 'Light mode' : 'Dark mode',
                        style: sans(size: 14, color: colors.sub)),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
            child: _profileTile(context),
          ),
        ],
      ),
    );
  }

  Widget _navItem(
      AppScreen screen, IconData icon, IconData iconActive, String label) {
    final isActive = active == screen;
    final color = isActive ? const Color(0xFF3DEBA8) : colors.sub;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: InkWell(
        onTap: () => onSelect(screen),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF3DEBA8).withValues(alpha: 0.11)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(isActive ? iconActive : icon, size: 19, color: color),
              const SizedBox(width: 12),
              Text(label,
                  style: sans(
                      size: 14,
                      weight: isActive ? FontWeight.w700 : FontWeight.w500,
                      color: isActive ? colors.text : colors.sub)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addButton() {
    return InkWell(
      onTap: onAdd,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          gradient: Brand.addButton,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF3DEBA8).withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add, size: 19, color: Color(0xFF0B0D14)),
            const SizedBox(width: 7),
            Text('New entry',
                style: sans(
                    size: 14.5,
                    weight: FontWeight.w700,
                    color: const Color(0xFF0B0D14))),
          ],
        ),
      ),
    );
  }

  Widget _profileTile(BuildContext context) {
    final user = AuthService().currentUser;
    final email = user?.email ?? '';
    final name = user?.displayName ?? 'Signed in';
    final initial = (user?.displayName?.isNotEmpty == true
            ? user!.displayName![0]
            : (email.isNotEmpty ? email[0] : '?'))
        .toUpperCase();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.elevated,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              gradient: Brand.addButton,
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            child: Center(
              child: Text(initial,
                  style: sans(
                      size: 14,
                      weight: FontWeight.w700,
                      color: const Color(0xFF0B0D14))),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(
                        size: 13,
                        weight: FontWeight.w700,
                        color: colors.text)),
                Text(email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(size: 11, color: colors.sub)),
              ],
            ),
          ),
          _ProfileMenu(colors: colors, compact: true),
        ],
      ),
    );
  }
}

// ── Desktop top bar ───────────────────────────────────────────────────────
class _DesktopTopBar extends StatelessWidget {
  const _DesktopTopBar({
    required this.title,
    required this.colors,
    required this.showMonths,
    required this.month,
    required this.onMonth,
  });

  final String title;
  final Palette colors;
  final bool showMonths;
  final String month;
  final ValueChanged<String> onMonth;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 22, 32, 18),
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: ContentWidth(
        child: Row(
          children: [
            Text(title,
                style: sans(
                    size: 26, weight: FontWeight.w800, color: colors.text)),
            const Spacer(),
            if (showMonths)
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Row(
                    children: [
                      for (final m in recentMonths(12).reversed)
                        _monthChip(m),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _monthChip(String m) {
    final isActive = m == month;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: InkWell(
        onTap: () => onMonth(m),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF3DEBA8).withValues(alpha: 0.13)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            fmtMonthShort(m),
            style: sans(
              size: 12.5,
              weight: isActive ? FontWeight.w700 : FontWeight.w500,
              color: isActive ? const Color(0xFF3DEBA8) : colors.sub,
            ),
          ),
        ),
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
  const _ProfileMenu({required this.colors, this.compact = false});
  final Palette colors;

  /// Sidebar variant: a small "more" glyph instead of the avatar tile.
  final bool compact;

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
          value: 'settings',
          child: Row(
            children: [
              Icon(Icons.settings_outlined, size: 16, color: colors.text),
              const SizedBox(width: 10),
              Text('Settings', style: sans(size: 13, color: colors.text)),
            ],
          ),
        ),
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
      ],
      onSelected: (v) {
        if (v == 'signout') auth.signOut();
        if (v == 'settings') openSettings(context);
      },
      child: compact
          ? Icon(Icons.more_horiz, size: 20, color: colors.sub)
          : Container(
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
