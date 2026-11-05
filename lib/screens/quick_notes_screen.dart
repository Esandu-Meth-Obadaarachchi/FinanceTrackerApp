import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_text.dart';
import '../theme/palette.dart';
import '../theme/theme_controller.dart';
import '../utils/responsive.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';

/// Opens the quick-notes manager, re-providing [AppState] for the pushed route.
void openQuickNotes(BuildContext context) {
  final app = context.read<AppState>();
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: const QuickNotesScreen(),
      ),
    ),
  );
}

/// The headings the add form offers in a dropdown. Setting a few up here turns
/// a regular entry into "pick one" instead of typing.
class QuickNotesScreen extends StatefulWidget {
  const QuickNotesScreen({super.key});

  @override
  State<QuickNotesScreen> createState() => _QuickNotesScreenState();
}

class _QuickNotesScreenState extends State<QuickNotesScreen> {
  String _type = 'income';
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _add(AppState app) async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    try {
      await app.addNotePreset(_type, text);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save — check your connection')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;
    final app = context.watch<AppState>();
    final notes = app.notePresets.forType(_type);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: colors.text),
        title: Text('Quick notes',
            style: sans(size: 18, weight: FontWeight.w800, color: colors.text)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: colors.border),
        ),
      ),
      body: ListView(
        padding: centredInsets(context, top: 16),
        children: [
          Text(
            'Save the headings you use often, like "Tehan class". When you add '
            'an entry you can pick one instead of typing. Picking is optional: '
            'leave it empty and the note field works as usual.',
            style: sans(size: 13, color: colors.sub, height: 1.45),
          ),
          const SizedBox(height: 16),
          SegmentedControl<String>(
            colors: colors,
            value: _type,
            options: const [
              (value: 'income', label: 'Income'),
              (value: 'expense', label: 'Expense'),
            ],
            onChanged: (v) => setState(() => _type = v),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  colors: colors,
                  controller: _input,
                  hint: _type == 'income'
                      ? 'e.g. Tehan class'
                      : 'e.g. Bus fare',
                  onSubmitted: (_) => _add(app),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => _add(app),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: Brand.addButton,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.add, color: Color(0xFF0B0D14)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (notes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                    'No ${_type == 'income' ? 'income' : 'expense'} notes yet',
                    style: sans(size: 13.5, color: colors.sub)),
              ),
            )
          else
            AppCard(
              colors: colors,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (var i = 0; i < notes.length; i++) ...[
                    if (i > 0) ThinDivider(colors: colors),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 2, 6, 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(notes[i],
                                style: sans(size: 14.5, color: colors.text)),
                          ),
                          IconButton(
                            tooltip: 'Remove',
                            onPressed: () =>
                                app.removeNotePreset(_type, notes[i]),
                            icon: Icon(Icons.close,
                                size: 18, color: colors.sub),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
