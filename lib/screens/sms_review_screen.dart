import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/categories.dart';
import '../models/sms_suggestion.dart';
import '../services/sms_inbox.dart';
import '../state/app_state.dart';
import '../theme/app_text.dart';
import '../theme/palette.dart';
import '../theme/theme_controller.dart';
import '../utils/formatters.dart';
import '../utils/responsive.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';

/// Opens the bank-SMS review inbox, re-providing [AppState] for the pushed
/// route (it lands on the root navigator, above the AuthGate provider).
void openSmsReview(BuildContext context) {
  final app = context.read<AppState>();
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: const SmsReviewScreen(),
      ),
    ),
  );
}

/// A queue of transactions read out of bank SMS, waiting to be approved.
///
/// The whole point is that the daily job becomes tapping Add a few times
/// rather than filling in forms, so the approve button is the largest thing
/// on each card and everything else stays out of the way until needed.
class SmsReviewScreen extends StatefulWidget {
  const SmsReviewScreen({super.key});

  @override
  State<SmsReviewScreen> createState() => _SmsReviewScreenState();
}

class _SmsReviewScreenState extends State<SmsReviewScreen> {
  @override
  void initState() {
    super.initState();
    SmsInbox.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;
    final app = context.watch<AppState>();

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: colors.text),
        title: Text('Review Inbox',
            style: sans(size: 18, weight: FontWeight.w800, color: colors.text)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: colors.border),
        ),
      ),
      body: AnimatedBuilder(
        animation: SmsInbox.instance,
        builder: (context, _) {
          final items = SmsInbox.instance.pending;
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: EmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'Nothing to review',
                  subtitle: 'Bank messages show up here as ready-made '
                      'entries. Approve one and it is filed.',
                  colors: colors,
                ),
              ),
            );
          }
          return ListView(
            padding: centredInsets(context, maxWidth: 720),
            children: [
              Text(
                '${items.length} to review. Each was read from a bank '
                'message — check it and tap Add.',
                style: sans(size: 12.5, color: colors.sub),
              ),
              const SizedBox(height: 16),
              for (final s in items)
                _SuggestionCard(
                  suggestion: s,
                  colors: colors,
                  app: app,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.suggestion,
    required this.colors,
    required this.app,
  });

  final SmsSuggestion suggestion;
  final Palette colors;
  final AppState app;

  Color get _tone => suggestion.type == 'income'
      ? const Color(0xFF3DEBA8)
      : const Color(0xFFFF5C7A);

  @override
  Widget build(BuildContext context) {
    final blocker = suggestion.blocker;
    final account = app.accountById(suggestion.accountId);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        suggestion.note.isNotEmpty
                            ? suggestion.note
                            : 'Bank message',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(
                            size: 15,
                            weight: FontWeight.w700,
                            color: colors.text),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          _sourceChip(),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '${fmtDateShort(dateKeyOf(suggestion.receivedAt))}'
                              '${account != null ? ' · ${account.name}' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(size: 11.5, color: colors.sub),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${suggestion.type == 'income' ? '+' : '-'} Rs '
                  '${fmt(suggestion.amount)}',
                  style:
                      mono(size: 17, weight: FontWeight.w700, color: _tone),
                ),
              ],
            ),
          ),

          // Category, editable in place — the field most likely to be wrong.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                if (suggestion.category.isNotEmpty)
                  CategoryDot(category: suggestion.category, size: 9),
                if (suggestion.category.isNotEmpty) const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _pickCategory(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: colors.inputBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              suggestion.category.isNotEmpty
                                  ? suggestion.category
                                  : 'Pick a category',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(
                                size: 13,
                                color: suggestion.category.isNotEmpty
                                    ? colors.text
                                    : colors.muted,
                              ),
                            ),
                          ),
                          Icon(Icons.expand_more, size: 16, color: colors.sub),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (suggestion.accountId.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: AppDropdown<String>(
                colors: colors,
                label: 'Account',
                value: app.accounts.isEmpty ? '' : app.accounts.first.id,
                items: [
                  for (final a in app.accounts)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) => SmsInbox.instance
                    .update(suggestion.copyWith(accountId: v ?? '')),
              ),
            ),

          if (blocker != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 13, color: Color(0xFFFFB547)),
                  const SizedBox(width: 6),
                  Text(blocker,
                      style: sans(size: 11.5, color: const Color(0xFFFFB547))),
                ],
              ),
            ),

          // The original message, folded away — needed rarely, but the only
          // way to settle "is this right?" without leaving the screen.
          Theme(
            data: Theme.of(context)
                .copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              title: Text('Original message',
                  style: sans(size: 12, color: colors.sub)),
              iconColor: colors.sub,
              collapsedIconColor: colors.sub,
              children: [
                Text(suggestion.body,
                    style: sans(size: 12, color: colors.sub, height: 1.5)),
              ],
            ),
          ),

          Container(
            decoration:
                BoxDecoration(border: Border(top: BorderSide(color: colors.border))),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: suggestion.blocker == null
                        ? () => SmsInbox.instance.approve(suggestion, app)
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: suggestion.blocker == null
                            ? const Color(0xFF3DEBA8).withValues(alpha: 0.15)
                            : colors.inputBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          'Add',
                          style: sans(
                            size: 13,
                            weight: FontWeight.w700,
                            color: suggestion.blocker == null
                                ? const Color(0xFF3DEBA8)
                                : colors.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => SmsInbox.instance.dismiss(suggestion),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5C7A).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('Skip',
                        style: sans(
                            size: 13,
                            weight: FontWeight.w600,
                            color: const Color(0xFFFF5C7A))),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Says who proposed this, so an AI guess is never mistaken for a fact.
  Widget _sourceChip() {
    final (label, color) = switch (suggestion.source) {
      SuggestionSource.memory => ('LEARNED', const Color(0xFF3DEBA8)),
      SuggestionSource.ai => ('AI', const Color(0xFF60A5FA)),
      SuggestionSource.rules => ('RULES', const Color(0xFF94A3B8)),
    };
    return TagPill(text: label, color: color);
  }

  Future<void> _pickCategory(BuildContext context) async {
    final options = suggestion.type == 'income'
        ? kIncomeCategories
        : kExpenseCategories;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final c in options)
              ListTile(
                leading: CategoryDot(category: c.label, size: 10),
                title: Text(c.label, style: sans(size: 14, color: colors.text)),
                onTap: () => Navigator.of(context).pop(c.label),
              ),
          ],
        ),
      ),
    );
    if (picked != null) {
      // A hand-picked category is the ground truth the memory should learn
      // from, so confidence is raised to match.
      await SmsInbox.instance.update(
        suggestion.copyWith(category: picked, confidence: 1),
      );
    }
  }
}
