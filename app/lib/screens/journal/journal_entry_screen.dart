import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../services/journal_store.dart';
import '../../theme/zvelt_tokens.dart';

/// Composer for a single day's journal entry — new or edit-in-place.
///
/// Date uniqueness is enforced server-side (well, store-side) via
/// [JournalStore.upsertEntry] — this screen just supplies a `DateTime`.
class JournalEntryScreen extends StatefulWidget {
  const JournalEntryScreen({
    super.key,
    required this.date,
    this.existing,
  });

  /// Calendar day this entry is for. Time component is ignored.
  final DateTime date;

  /// Pre-existing entry to edit. `null` = new entry mode.
  final JournalEntry? existing;

  /// Sentinel value passed to `Navigator.pop` when the user deletes the entry.
  /// The parent list uses [isDeleted] to distinguish saved vs deleted vs
  /// dismissed.
  static const Object deletedSentinel = Object();

  /// Whether a Navigator.pop result indicates a delete (vs a saved entry
  /// or a plain dismissal).
  static bool isDeleted(Object? result) => identical(result, deletedSentinel);

  @override
  State<JournalEntryScreen> createState() => _JournalEntryScreenState();
}

class _JournalEntryScreenState extends State<JournalEntryScreen> {
  static const List<String> _moodEmojis = ['😞', '😕', '😐', '🙂', '😄'];
  static const List<String> _moodLabels = ['Awful', 'Low', 'Okay', 'Good', 'Great'];

  int? _mood;
  int? _energy;
  final Set<String> _soreness = <String>{};
  late final TextEditingController _notesCtrl;
  bool _saving = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _mood = e?.mood;
    _energy = e?.energy;
    if (e != null) _soreness.addAll(e.soreness);
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _notesCtrl.addListener(() {
      if (mounted) setState(() {}); // refresh char counter
    });
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.existing != null;

  bool get _canSave => _mood != null && _energy != null && !_saving;

  bool get _isToday {
    final now = DateTime.now();
    return widget.date.year == now.year &&
        widget.date.month == now.month &&
        widget.date.day == now.day;
  }

  String _appBarTitle() {
    if (_isToday) return 'Today';
    return DateFormat('EEE, MMM d').format(widget.date);
  }

  String _lastUpdatedLabel() {
    final e = widget.existing;
    if (e == null) return '';
    final delta = DateTime.now().difference(e.updatedAt);
    if (delta.inMinutes < 1) return 'Last updated just now';
    if (delta.inMinutes < 60) return 'Last updated ${delta.inMinutes}m ago';
    if (delta.inHours < 24) return 'Last updated ${delta.inHours}h ago';
    if (delta.inDays < 30) return 'Last updated ${delta.inDays}d ago';
    return 'Last updated on ${DateFormat('MMM d').format(e.updatedAt.toLocal())}';
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    HapticFeedback.lightImpact();
    final now = DateTime.now();
    final entry = JournalEntry(
      id: widget.existing?.id,
      entryDate: DateTime(widget.date.year, widget.date.month, widget.date.day),
      mood: _mood!,
      energy: _energy!,
      soreness: _soreness.toList(),
      notes: _notesCtrl.text.trim(),
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );
    try {
      final saved = await JournalStore.instance.upsertEntry(entry);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Journal entry saved'),
          duration: Duration(seconds: 1),
        ),
      );
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  Future<void> _confirmDelete() async {
    final id = widget.existing?.id;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entry?'),
        content: const Text(
          'This entry will be permanently removed from your journal. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: ZveltTokens.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _deleting = true);
    try {
      await JournalStore.instance.deleteEntry(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Entry deleted'),
          duration: Duration(seconds: 1),
        ),
      );
      Navigator.of(context).pop(JournalEntryScreen.deletedSentinel);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        title: Text(_appBarTitle()),
        actions: [
          IconButton(
            onPressed: _canSave ? _save : null,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ZveltTokens.brand,
                    ),
                  )
                : const Icon(AppIcons.check),
            tooltip: 'Save',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (_isEditing) _lastUpdatedBanner(),
            _moodCard(),
            const SizedBox(height: 12),
            _energyCard(),
            const SizedBox(height: 12),
            _sorenessCard(),
            const SizedBox(height: 12),
            _notesCard(),
            const SizedBox(height: 16),
            _saveButton(),
            if (_isEditing) ...[
              const SizedBox(height: 12),
              _deleteButton(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _lastUpdatedBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(AppIcons.time_past, size: 14, color: ZveltTokens.text3),
          const SizedBox(width: 6),
          Text(
            _lastUpdatedLabel(),
            style: TextStyle(color: ZveltTokens.text2, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _moodCard() {
    return _card(
      title: 'Mood',
      required: true,
      filled: _mood != null,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(5, (i) {
          final selected = _mood == i + 1;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _mood = i + 1);
            },
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? ZveltTokens.brandGlow : ZveltTokens.surface2,
                    border: Border.all(
                      color: selected ? ZveltTokens.brand : ZveltTokens.border,
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Center(
                    child: Text(_moodEmojis[i], style: const TextStyle(fontSize: 24)),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _moodLabels[i],
                  style: TextStyle(
                    color: selected ? ZveltTokens.brand : ZveltTokens.text3,
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _energyCard() {
    return _card(
      title: 'Energy',
      required: true,
      filled: _energy != null,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(5, (i) {
          final selected = (_energy ?? 0) >= i + 1;
          final tapped = _energy == i + 1;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _energy = i + 1);
            },
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tapped ? ZveltTokens.brandGlow : ZveltTokens.surface2,
                    border: Border.all(
                      color: tapped ? ZveltTokens.brand : ZveltTokens.border,
                      width: tapped ? 1.5 : 1,
                    ),
                  ),
                  child: Icon(
                    AppIcons.bolt,
                    size: 26,
                    color: selected ? ZveltTokens.brand : ZveltTokens.text4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${i + 1}',
                  style: TextStyle(
                    color: tapped ? ZveltTokens.brand : ZveltTokens.text3,
                    fontSize: 11,
                    fontWeight: tapped ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _sorenessCard() {
    return _card(
      title: 'Soreness',
      subtitle: _soreness.isEmpty
          ? 'Tap muscle groups that feel sore today'
          : '${_soreness.length} selected',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: JournalStore.kBodyParts.map((part) {
          final selected = _soreness.contains(part);
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                if (selected) {
                  _soreness.remove(part);
                } else {
                  _soreness.add(part);
                }
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s2),
              decoration: BoxDecoration(
                color: selected ? ZveltTokens.brandGlow : ZveltTokens.surface2,
                borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                border: Border.all(
                  color: selected ? ZveltTokens.brand : ZveltTokens.border,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Text(
                _prettyPart(part),
                style: TextStyle(
                  color: selected ? ZveltTokens.brand : ZveltTokens.text2,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _notesCard() {
    final len = _notesCtrl.text.characters.length;
    return _card(
      title: 'Notes',
      subtitle: 'Optional — sleep, stress, what you ate, anything',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          TextField(
            controller: _notesCtrl,
            maxLines: 5,
            minLines: 3,
            maxLength: 1000,
            buildCounter: (_,
                    {required currentLength, required isFocused, maxLength}) =>
                null,
            style: TextStyle(color: ZveltTokens.text, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'How was the day?',
              hintStyle: TextStyle(color: ZveltTokens.text3),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              filled: false,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$len / 1000',
            style: TextStyle(
              color: len > 950 ? ZveltTokens.warn : ZveltTokens.text3,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _saveButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _canSave ? _save : null,
        icon: _saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(AppIcons.check, size: 18),
        label: Text(_isEditing ? 'UPDATE ENTRY' : 'SAVE ENTRY'),
      ),
    );
  }

  Widget _deleteButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _deleting ? null : _confirmDelete,
        icon: _deleting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: ZveltTokens.error),
              )
            : const Icon(AppIcons.trash, size: 18),
        label: const Text('DELETE ENTRY'),
        style: OutlinedButton.styleFrom(
          foregroundColor: ZveltTokens.error,
          side: const BorderSide(color: ZveltTokens.error, width: 1),
        ),
      ),
    );
  }

  Widget _card({
    required String title,
    String? subtitle,
    bool required = false,
    bool filled = false,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s4, ZveltTokens.s4, ZveltTokens.s4),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontFamily: ZveltTokens.fontPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: ZveltTokens.text,
                  letterSpacing: 0.22,
                ),
              ),
              if (required) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: filled ? ZveltTokens.success.withValues(alpha: 0.18) : ZveltTokens.surface3,
                    borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                  ),
                  child: Text(
                    filled ? 'SET' : 'REQUIRED',
                    style: TextStyle(
                      color: filled ? ZveltTokens.success : ZveltTokens.text3,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(color: ZveltTokens.text2, fontSize: 12),
            ),
          ],
          const SizedBox(height: ZveltTokens.s4),
          child,
        ],
      ),
    );
  }

  static String _prettyPart(String id) {
    switch (id) {
      case 'lower_back':
        return 'Lower back';
      default:
        return id[0].toUpperCase() + id.substring(1);
    }
  }
}
