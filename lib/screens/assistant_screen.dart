import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/ai_service.dart';
import '../state/app_state.dart';
import '../theme/app_text.dart';
import '../theme/palette.dart';
import '../theme/theme_controller.dart';
import '../utils/responsive.dart';

/// Opens the assistant, re-providing [AppState] for the pushed route.
void openAssistant(BuildContext context) {
  final app = context.read<AppState>();
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: const AssistantScreen(),
      ),
    ),
  );
}

class _Message {
  _Message(this.role, this.text, {this.tools = const [], this.provider = ''});
  final String role; // user | assistant
  final String text;
  final List<String> tools;
  final String provider;
}

/// Ask questions about your own money.
///
/// The answer comes from an agent that calls tools over a snapshot of this
/// device's data, so it quotes real figures rather than inventing them. The
/// tools it used are shown under each answer: with money, being able to see
/// *how* it got there matters more than the reply sounding confident.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Message> _messages = [];
  bool _busy = false;

  static const _starters = [
    'How much did I spend on food this month?',
    'What do I still owe, and who owes me?',
    'Am I over budget on anything?',
    'What pending income is still outstanding?',
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final question = text.trim();
    if (question.isEmpty || _busy) return;

    final app = context.read<AppState>();
    setState(() {
      _messages.add(_Message('user', question));
      _busy = true;
      _input.clear();
    });
    _scrollDown();

    try {
      // Only prior turns travel as history; the snapshot is rebuilt each
      // time so the agent always sees current figures.
      final history = [
        for (final m in _messages.take(_messages.length - 1))
          (role: m.role, content: m.text),
      ];
      final reply = await AiService.instance.ask(question, app, history: history);
      if (!mounted) return;
      setState(() {
        _messages.add(_Message('assistant', reply.answer,
            tools: reply.toolCalls, provider: reply.provider));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(_Message('assistant',
            'I could not reach the assistant.\n\n$e'));
      });
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollDown();
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: colors.text),
        title: Text('Assistant',
            style: sans(size: 18, weight: FontWeight.w800, color: colors.text)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: colors.border),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _starterList(colors)
                : ListView(
                    controller: _scroll,
                    padding: centredInsets(context, maxWidth: 760, top: 16),
                    children: [
                      for (final m in _messages) _bubble(m, colors),
                      if (_busy) _thinking(colors),
                    ],
                  ),
          ),
          _composer(colors),
        ],
      ),
    );
  }

  Widget _starterList(Palette colors) {
    return ListView(
      padding: centredInsets(context, maxWidth: 760, top: 28),
      children: [
        Icon(Icons.auto_awesome, size: 32, color: colors.sub),
        const SizedBox(height: 12),
        Text('Ask about your money',
            textAlign: TextAlign.center,
            style:
                sans(size: 18, weight: FontWeight.w700, color: colors.text)),
        const SizedBox(height: 6),
        Text(
          'Answers come from your own entries, not guesswork.',
          textAlign: TextAlign.center,
          style: sans(size: 13, color: colors.sub),
        ),
        const SizedBox(height: 24),
        for (final s in _starters)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: () => _send(s),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: colors.card,
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(s,
                          style: sans(size: 13.5, color: colors.text)),
                    ),
                    Icon(Icons.north_east, size: 14, color: colors.sub),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _bubble(_Message m, Palette colors) {
    final isUser = m.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: isUser
              ? const Color(0xFF3DEBA8).withValues(alpha: 0.13)
              : colors.card,
          border: Border.all(
              color: isUser ? Colors.transparent : colors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.text,
                style: sans(size: 14, color: colors.text, height: 1.45)),
            if (m.tools.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in m.tools.toSet())
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: colors.elevated,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(t.replaceAll('_', ' '),
                          style: mono(size: 10, color: colors.sub)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _thinking(Palette colors) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colors.card,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFF3DEBA8)),
            ),
            const SizedBox(width: 10),
            Text('Looking through your entries…',
                style: sans(size: 13, color: colors.sub)),
          ],
        ),
      ),
    );
  }

  Widget _composer(Palette colors) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, MediaQuery.of(context).padding.bottom + 10),
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: ContentWidth(
        maxWidth: 760,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                onSubmitted: _send,
                textInputAction: TextInputAction.send,
                style: sans(size: 14, color: colors.text),
                cursorColor: const Color(0xFF3DEBA8),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Ask about your money…',
                  hintStyle: sans(size: 14, color: colors.muted),
                  filled: true,
                  fillColor: colors.inputBg,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 13),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colors.inputBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colors.inputBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF3DEBA8)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => _send(_input.text),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: _busy ? null : Brand.addButton,
                  color: _busy ? colors.inputBg : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.arrow_upward,
                  size: 19,
                  color: _busy ? colors.muted : const Color(0xFF0B0D14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
