import 'dart:io';

import 'package:flutter/material.dart';

import '../app.dart';
import '../attachment_field.dart';
import '../attachment_files.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class EditEntryScreen extends StatefulWidget {
  const EditEntryScreen({super.key, required this.entryId});

  final String entryId;

  @override
  State<EditEntryScreen> createState() => _EditEntryScreenState();
}

class _EditEntryScreenState extends State<EditEntryScreen> {
  LedgerEntry? _entry;
  late final TextEditingController _content;
  late final TextEditingController _amount;
  late final TextEditingController _date;
  late final TextEditingController _category;
  late final TextEditingController _note;
  MoneyDirection _direction = MoneyDirection.expense;
  String? _error;
  var _ready = false;
  var _saved = false;
  List<LedgerAttachment> _attachments = const [];
  Set<String> _originalPaths = const {};
  Directory? _attachmentsRoot;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    final entries = LedgerScope.of(context).snapshots.expand((snapshot) => snapshot.entries);
    final entry = entries.where((item) => item.id == widget.entryId).firstOrNull;
    _entry = entry;
    _content = TextEditingController(text: entry?.content ?? '');
    _amount = TextEditingController(text: entry == null ? '' : entry.amount.toStringAsFixed(2));
    _date = TextEditingController(text: entry?.date ?? formatDay(DateTime.now()));
    _category = TextEditingController(text: entry?.category ?? '');
    _note = TextEditingController(text: entry?.note ?? '');
    _direction = entry?.direction ?? MoneyDirection.expense;
    _attachments = List<LedgerAttachment>.of(entry?.attachments ?? const []);
    _originalPaths = entry?.attachments.map((item) => item.relativePath).toSet() ?? {};
    _attachmentsRoot = LedgerScope.of(context).attachmentsDir;
    _ready = true;
  }

  @override
  void dispose() {
    final root = _attachmentsRoot;
    if (!_saved && root != null) {
      for (final attachment in _attachments) {
        if (!_originalPaths.contains(attachment.relativePath)) {
          AttachmentFiles.delete(root, attachment);
        }
      }
    }
    if (_ready) {
      _content.dispose();
      _amount.dispose();
      _date.dispose();
      _category.dispose();
      _note.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final entry = _entry;
    if (entry == null) return;
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (_content.text.trim().isEmpty || amount == null || amount <= 0 || !validLedgerDate(_date.text)) {
      setState(() => _error = '请填写内容、大于 0 的金额，以及正确日期');
      return;
    }
    try {
      await LedgerScope.of(context).updateEntry(
        entry.copyWith(
          direction: _direction,
          content: _content.text.trim(),
          amount: amount,
          date: _date.text,
          category: _category.text.trim(),
          note: _note.text.trim(),
          attachments: _attachments,
        ),
      );
      _saved = true;
      if (mounted) Navigator.pop(context);
    } on LedgerException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_entry == null) {
      return Scaffold(appBar: AppBar(title: const Text('编辑记账')), body: const Center(child: Text('这笔账已经不存在')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('编辑记账')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          DirectionSwitch(value: _direction, onChanged: (value) => setState(() => _direction = value)),
          const SizedBox(height: 10),
          TextField(controller: _content, decoration: const InputDecoration(hintText: '记账内容')),
          const SizedBox(height: 10),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(hintText: '金额'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _date,
            readOnly: true,
            decoration: const InputDecoration(hintText: '日期'),
            onTap: () async {
              final picked = await pickLedgerDate(context, _date.text);
              if (picked != null) setState(() => _date.text = picked);
            },
          ),
          const SizedBox(height: 10),
          TextField(controller: _category, decoration: const InputDecoration(hintText: '类别，可选')),
          const SizedBox(height: 8),
          CategoryChips(onSelected: (value) => setState(() => _category.text = value)),
          const SizedBox(height: 10),
          AttachmentField(
            attachments: _attachments,
            root: LedgerScope.of(context).attachmentsDir,
            onChanged: (next) {
              final root = _attachmentsRoot;
              if (root != null) {
                for (final attachment in _attachments) {
                  final removed = !next.any((item) => item.relativePath == attachment.relativePath);
                  if (removed && !_originalPaths.contains(attachment.relativePath)) {
                    AttachmentFiles.delete(root, attachment);
                  }
                }
              }
              setState(() => _attachments = next);
            },
          ),
          const SizedBox(height: 10),
          TextField(controller: _note, decoration: const InputDecoration(hintText: '备注，可选')),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppColors.expense)),
          ],
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('保存修改')),
        ],
      ),
    );
  }
}
