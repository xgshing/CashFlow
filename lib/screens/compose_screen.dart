import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app.dart';
import '../attachment_field.dart';
import '../attachment_files.dart';
import '../format.dart';
import '../tencent_speech.dart';
import '../models.dart';
import '../parser.dart';
import '../theme.dart';
import '../widgets.dart';

enum InputMode { voice, handwriting, paste }

class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key, required this.projectId});

  final String projectId;

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  InputMode _mode = InputMode.voice;
  final List<DraftEntry> _drafts = [];
  int _nextId = 1;
  bool _holding = false;
  bool _preparing = false;
  bool _cancelArmed = false;
  bool _recognizing = false;
  bool _fingerDown = false;
  int _session = 0;
  int _finishedSession = -1;
  double _pointerOrigin = 0;
  String? _voiceError;
  bool _voiceHint = false;
  MoneyDirection _manualDirection = MoneyDirection.expense;
  String? _formError;
  List<LedgerAttachment> _manualAttachments = [];
  Directory? _attachmentsRoot;
  var _committed = false;

  final _voiceText = TextEditingController();
  final _pasteText = TextEditingController();
  final _content = TextEditingController();
  final _amount = TextEditingController();
  final _category = TextEditingController();
  final _note = TextEditingController();
  final _date = TextEditingController(text: formatDay(DateTime.now()));
  final _speech = TencentSpeech();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachmentsRoot = LedgerScope.of(context).attachmentsDir;
  }

  @override
  void dispose() {
    final root = _attachmentsRoot;
    if (!_committed && root != null) {
      for (final draft in _drafts) {
        AttachmentFiles.deleteAll(root, draft.attachments);
      }
      AttachmentFiles.deleteAll(root, _manualAttachments);
    }
    unawaited(_speech.close());
    _voiceText.dispose();
    _pasteText.dispose();
    _content.dispose();
    _amount.dispose();
    _category.dispose();
    _note.dispose();
    _date.dispose();
    super.dispose();
  }

  Future<void> _setMode(InputMode mode) async {
    if (mode != InputMode.voice && (_holding || _recognizing || _preparing)) {
      _session++;
      _fingerDown = false;
      _cancelArmed = true;
      await _speech.cancel();
      _holding = false;
      _recognizing = false;
      _preparing = false;
      _cancelArmed = false;
    }
    setState(() => _mode = mode);
  }

  Future<void> _pointerDown(double origin) async {
    if (_recognizing || _preparing) return;
    final session = ++_session;
    _pointerOrigin = origin;
    _fingerDown = true;
    _cancelArmed = false;
    setState(() {
      _holding = true;
      _preparing = true;
      _voiceError = null;
      _voiceHint = false;
    });
    try {
      final status = await _speech.begin(
        stillHolding: () => _fingerDown && !_cancelArmed && session == _session,
        onText: (text) {
          if (!mounted || session != _session) return;
          setState(() {
            _voiceText.text = text;
            _voiceText.selection = TextSelection.collapsed(offset: text.length);
            _voiceError = null;
          });
        },
      );
      if (!mounted || session != _session) {
        await _speech.cancel();
        return;
      }
      if (status == 'granted') {
        _fingerDown = false;
        setState(() {
          _holding = false;
          _preparing = false;
          _recognizing = false;
          _voiceError = null;
          _voiceHint = false;
        });
        return;
      }
      if (status == 'idle') {
        final cancelled = _cancelArmed;
        _fingerDown = false;
        setState(() {
          _holding = false;
          _preparing = false;
          _recognizing = false;
          _cancelArmed = false;
          _voiceHint = !cancelled;
          _voiceError = cancelled ? null : '请再按住说话。';
        });
        return;
      }
      if (status != 'ok') {
        _fingerDown = false;
        setState(() {
          _holding = false;
          _preparing = false;
          _voiceHint = false;
          _voiceError = switch (status) {
            'denied' => '需要麦克风权限才能语音记账。',
            'assistant_only' => '这部华为手机只提供了语音助手，它不能把记账句子转成文字。微信用的是自己的语音，所以同一句话在微信里可以识别。',
            _ => '语音准备失败，请再按住试一次，或改用手写。',
          };
        });
        return;
      }
      if (mounted) setState(() => _preparing = false);
      if (_cancelArmed || !_fingerDown) await _finishHold(session);
    } catch (_) {
      if (!mounted || session != _session) return;
      _fingerDown = false;
      setState(() {
        _holding = false;
        _preparing = false;
        _voiceHint = false;
        _voiceError = '语音准备失败，请再按住试一次，或改用手写。';
      });
    }
  }

  void _pointerMove(double y) {
    if (!_holding) return;
    final armed = _pointerOrigin - y > 72;
    if (armed == _cancelArmed) return;
    setState(() => _cancelArmed = armed);
  }

  Future<void> _pointerUp({bool forceCancel = false}) async {
    if (forceCancel) _cancelArmed = true;
    final session = _session;
    _fingerDown = false;
    if (_preparing || session == _finishedSession || !_holding) return;
    await _finishHold(session);
  }

  Future<void> _finishHold(int session) async {
    if (session != _session || session == _finishedSession) return;
    _finishedSession = session;
    final cancel = _cancelArmed;
    if (mounted) {
      setState(() {
        _holding = false;
        _preparing = false;
        _cancelArmed = false;
        _recognizing = !cancel;
      });
    }
    if (cancel) {
      await _speech.cancel();
      if (!mounted || session != _session) return;
      setState(() => _recognizing = false);
      return;
    }
    final text = await _speech.finish();
    if (!mounted || session != _session) return;
    setState(() {
      _recognizing = false;
      if (text.trim().isEmpty) {
        _voiceHint = false;
        _voiceError = _speech.lastError ?? '没有听清，请按住重说。';
      } else {
        _voiceText.text = text;
        _voiceText.selection = TextSelection.collapsed(offset: text.length);
        _voiceError = null;
      }
    });
    if (text.trim().isNotEmpty && LedgerParser.parse(text).isNotEmpty) {
      _recognize(text);
    }
  }

  void _recognize(String raw) {
    final parsed = LedgerParser.parse(raw, idStart: _nextId);
    if (parsed.isEmpty) {
      showMessage(context, '没有识别到金额。请写明“268元”这样的金额，或改用手写。');
      return;
    }
    _nextId += parsed.length;
    final root = _attachmentsRoot;
    if (root != null) {
      for (final draft in _drafts.where((item) => item.origin == DraftOrigin.parsed)) {
        AttachmentFiles.deleteAll(root, draft.attachments);
      }
    }
    setState(() {
      _drafts
        ..removeWhere((draft) => draft.origin == DraftOrigin.parsed)
        ..addAll(parsed);
    });
  }

  void _addManual() {
    final content = _content.text.trim();
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (content.isEmpty || amount == null || amount <= 0 || !validLedgerDate(_date.text)) {
      setState(() => _formError = '请填写内容、大于 0 的金额，以及正确日期');
      return;
    }
    setState(() {
      _formError = null;
      _drafts.add(
        DraftEntry(
          localId: _nextId++,
          direction: _manualDirection,
          content: content,
          amount: roundMoney(amount),
          date: _date.text,
          category: _category.text.trim(),
          note: _note.text.trim(),
          attachments: _manualAttachments,
        ),
      );
      _manualAttachments = [];
      _content.clear();
      _amount.clear();
      _note.clear();
    });
  }

  Future<void> _save() async {
    final store = LedgerScope.of(context);
    final name = store.projectNameOf(widget.projectId) ?? '项目';
    try {
      final outcome = await store.saveNewEntries(projectId: widget.projectId, drafts: _drafts);
      if (!mounted) return;
      switch (outcome.kind) {
        case SaveKind.saved:
          _committed = true;
          showMessage(
            context,
            outcome.excelWritten
                ? '已保存到「$name」，并写入 Excel'
                : '账目已保存，表格写入失败。可稍后在项目里再次分享',
          );
          Navigator.pop(context);
        case SaveKind.duplicate:
          _committed = true;
          showMessage(context, '这些记录刚刚已经保存，未重复写入');
          Navigator.pop(context);
        case SaveKind.busy:
          return;
        case SaveKind.empty:
          showMessage(context, '请先添加记账内容');
      }
    } on LedgerException catch (error) {
      if (mounted) showMessage(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = LedgerScope.of(context);
    final projectName = store.projectNameOf(widget.projectId) ?? '项目';
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('新增记账'),
            Text('记入 $projectName', style: const TextStyle(fontSize: 12, color: AppColors.sub, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                _modeButton(InputMode.voice, '语音', const Key('mode-voice')),
                const SizedBox(width: 8),
                _modeButton(InputMode.handwriting, '手写', const Key('mode-handwriting')),
                const SizedBox(width: 8),
                _modeButton(InputMode.paste, '粘贴识别', const Key('mode-paste')),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                if (_mode == InputMode.voice) _voicePanel(),
                if (_mode == InputMode.handwriting) _handPanel(),
                if (_mode == InputMode.paste) _pastePanel(),
                if (_drafts.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Text('识别结果（可修改）', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 8),
                  for (final draft in _drafts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _DraftCard(
                        key: ValueKey(draft.localId),
                        draft: draft,
                        onChanged: (next) {
                          final index = _drafts.indexWhere((item) => item.localId == next.localId);
                          if (index >= 0) setState(() => _drafts[index] = next);
                        },
                        onDelete: () {
                          final root = _attachmentsRoot;
                          if (root != null) AttachmentFiles.deleteAll(root, draft.attachments);
                          setState(() => _drafts.removeWhere((item) => item.localId == draft.localId));
                        },
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_mode == InputMode.voice) ...[
                _holdButton(),
                const SizedBox(height: 8),
              ],
              FilledButton(
                key: const Key('save-entry-button'),
                onPressed: store.saving || _drafts.isEmpty ? null : _save,
                child: store.saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_drafts.isEmpty ? '确认保存' : '确认保存 ${_drafts.length} 笔'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeButton(InputMode mode, String label, Key key) {
    final selected = _mode == mode;
    return Expanded(
      child: Material(
        color: selected ? AppColors.primary : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(12),
          onTap: () => _setMode(mode),
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? AppColors.primary : AppColors.line),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppColors.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _holdButton() {
    final cancel = _holding && _cancelArmed;
    final label = _preparing
        ? '正在准备…'
        : _recognizing
        ? '正在识别…'
        : cancel
        ? '松开取消'
        : _holding
        ? '松开 结束'
        : '按住 说话';
    final color = cancel ? AppColors.expense : AppColors.primary;
    return Listener(
      key: const Key('voice-hold-button'),
      onPointerDown: (event) => _pointerDown(event.position.dy),
      onPointerMove: (event) => _pointerMove(event.position.dy),
      onPointerUp: (_) => _pointerUp(),
      onPointerCancel: (_) => _pointerUp(forceCancel: true),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            if (_holding)
              Text(
                cancel ? '松开后不会保留这段语音' : '上滑取消',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }

  Widget _voicePanel() {
    return Column(
      children: [
        const Text(
          '按住底部按钮说话，松开后转成文字。手指上滑可以取消。',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.sub, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 4),
        const Text(
          '语音由腾讯云识别，说话时需要网络。账本只保存在本机。',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.sub, fontSize: 12, height: 1.4),
        ),
        if (_voiceError != null) ...[
          const SizedBox(height: 8),
          Text(
            _voiceError!,
            textAlign: TextAlign.center,
            style: TextStyle(color: _voiceHint ? AppColors.sub : AppColors.expense),
          ),
          if (!_voiceHint) TextButton(onPressed: () => _setMode(InputMode.handwriting), child: const Text('改用手写')),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _voiceText,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(hintText: '例如：今天买了鼠标 89 元，键盘 199 元'),
        ),
      ],
    );
  }

  Widget _pastePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('一次粘贴可以识别多笔记账', style: TextStyle(color: AppColors.sub)),
        const SizedBox(height: 8),
        TextField(
          controller: _pasteText,
          minLines: 8,
          maxLines: 12,
          decoration: const InputDecoration(
            hintText: '今天购买办公用品：\n1. 打印纸 268元\n2. 文件夹 45元\n另外，项目服务费 5000元。\n日期：2026-10-30',
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(96, 40)),
            onPressed: () => _recognize(_pasteText.text),
            child: const Text('识别'),
          ),
        ),
      ],
    );
  }

  Widget _handPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DirectionSwitch(
          value: _manualDirection,
          onChanged: (value) => setState(() => _manualDirection = value),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('manual-content'),
          controller: _content,
          decoration: const InputDecoration(hintText: '记账内容'),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('manual-amount'),
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
        TextField(
          controller: _category,
          decoration: const InputDecoration(hintText: '类别，可选'),
        ),
        const SizedBox(height: 8),
        CategoryChips(onSelected: (value) => setState(() => _category.text = value)),
        const SizedBox(height: 10),
        AttachmentField(
          attachments: _manualAttachments,
          root: LedgerScope.of(context).attachmentsDir,
          onChanged: (next) {
            final root = LedgerScope.of(context).attachmentsDir;
            AttachmentFiles.deleteRemoved(root, _manualAttachments, next);
            setState(() => _manualAttachments = next);
          },
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _note,
          decoration: const InputDecoration(hintText: '备注，可选'),
        ),
        if (_formError != null) ...[
          const SizedBox(height: 8),
          Text(_formError!, style: const TextStyle(color: AppColors.expense)),
        ],
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('add-draft-button'),
          onPressed: _addManual,
          child: const Text('加入本笔'),
        ),
      ],
    );
  }
}

class _DraftCard extends StatefulWidget {
  const _DraftCard({
    super.key,
    required this.draft,
    required this.onChanged,
    required this.onDelete,
  });

  final DraftEntry draft;
  final ValueChanged<DraftEntry> onChanged;
  final VoidCallback onDelete;

  @override
  State<_DraftCard> createState() => _DraftCardState();
}

class _DraftCardState extends State<_DraftCard> {
  late final TextEditingController _content = TextEditingController(text: widget.draft.content);
  late final TextEditingController _amount = TextEditingController(text: widget.draft.amount.toStringAsFixed(2));
  late final TextEditingController _date = TextEditingController(text: widget.draft.date);
  late final TextEditingController _category = TextEditingController(text: widget.draft.category);
  late final TextEditingController _note = TextEditingController(text: widget.draft.note);

  @override
  void dispose() {
    _content.dispose();
    _amount.dispose();
    _date.dispose();
    _category.dispose();
    _note.dispose();
    super.dispose();
  }

  void _emit({MoneyDirection? direction}) {
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', '')) ?? 0;
    widget.onChanged(
      widget.draft.copyWith(
        direction: direction,
        content: _content.text,
        amount: amount,
        date: _date.text,
        category: _category.text,
        note: _note.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WhiteCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              DirectionTag(direction: widget.draft.direction),
              const Spacer(),
              IconButton(
                tooltip: '删除这笔',
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.expense),
              ),
            ],
          ),
          DirectionSwitch(value: widget.draft.direction, onChanged: (value) => _emit(direction: value)),
          const SizedBox(height: 8),
          TextField(
            controller: _content,
            decoration: const InputDecoration(hintText: '内容'),
            onChanged: (_) => _emit(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(hintText: '金额'),
                  onChanged: (_) => _emit(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _date,
                  readOnly: true,
                  decoration: const InputDecoration(hintText: '日期'),
                  onTap: () async {
                    final picked = await pickLedgerDate(context, _date.text);
                    if (picked == null) return;
                    _date.text = picked;
                    _emit();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _category,
            decoration: const InputDecoration(hintText: '类别，可选'),
            onChanged: (_) => _emit(),
          ),
          const SizedBox(height: 8),
          AttachmentField(
            attachments: widget.draft.attachments,
            root: LedgerScope.of(context).attachmentsDir,
            onChanged: (next) {
              AttachmentFiles.deleteRemoved(
                LedgerScope.of(context).attachmentsDir,
                widget.draft.attachments,
                next,
              );
              widget.onChanged(widget.draft.copyWith(attachments: next));
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _note,
            decoration: const InputDecoration(hintText: '备注，可选'),
            onChanged: (_) => _emit(),
          ),
        ],
      ),
    );
  }
}
