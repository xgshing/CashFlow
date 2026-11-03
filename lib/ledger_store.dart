import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'attachment_files.dart';
import 'excel_service.dart';
import 'format.dart';
import 'models.dart';
import 'repository.dart';

class LedgerStore extends ChangeNotifier {
  LedgerStore(this._repository);

  final LedgerRepository _repository;
  final Uuid _uuid = const Uuid();

  final List<CashProject> _projects = [];
  final List<LedgerEntry> _entries = [];
  final Map<String, int> _sizes = {};

  bool ready = false;
  bool saving = false;
  Object? loadError;
  String? _recentHash;
  DateTime? _recentAt;

  Directory get attachmentsDir => _repository.attachmentsDir;

  List<ProjectSnapshot> get snapshots {
    final list = _projects.map((project) {
      final entries = _entries.where((entry) => entry.projectId == project.id).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return ProjectSnapshot(
        project: project,
        entries: entries,
        fileBytes: _sizes[project.id] ?? 0,
      );
    }).toList();
    list.sort((a, b) {
      final aTime = a.latest?.createdAt ?? a.project.createdAt;
      final bTime = b.latest?.createdAt ?? b.project.createdAt;
      return bTime.compareTo(aTime);
    });
    return list;
  }

  LedgerEntry? get latestEntry {
    if (_entries.isEmpty) return null;
    final sorted = [..._entries]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted.first;
  }

  CashProject? projectById(String id) {
    for (final project in _projects) {
      if (project.id == id) return project;
    }
    return null;
  }

  ProjectSnapshot? snapshotById(String id) {
    for (final snapshot in snapshots) {
      if (snapshot.project.id == id) return snapshot;
    }
    return null;
  }

  String? projectNameOf(String projectId) => projectById(projectId)?.name;

  Future<void> load() async {
    try {
      _projects
        ..clear()
        ..addAll(await _repository.listProjects());
      _entries
        ..clear()
        ..addAll(await _repository.listEntries());
      for (final project in _projects) {
        _refreshSize(project);
      }
      loadError = null;
    } catch (error) {
      loadError = error;
    } finally {
      ready = true;
      notifyListeners();
    }
  }

  String? nameError(String rawName, {String? exceptId}) {
    final name = rawName.trim();
    if (name.isEmpty) return '请输入项目名称';
    if (name.length > 40) return '项目名称最多 40 个字';
    if (RegExp(r'[\\/:*?"<>|]').hasMatch(name)) {
      return r'名称不能包含 \ / : * ? " < > |';
    }
    if (name == '.' || name == '..') return '请换一个项目名称';
    final taken = _projects.any(
      (project) => project.id != exceptId && project.name.toLowerCase() == name.toLowerCase(),
    );
    if (taken) return '已经有同名项目';
    return null;
  }

  Future<CashProject> createProject(String rawName) async {
    final name = rawName.trim();
    final error = nameError(name);
    if (error != null) throw LedgerException(error);
    final project = CashProject(
      id: _uuid.v4(),
      name: name,
      filePath: _allocatePath(name),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _repository.insertProject(project);
    _projects.add(project);
    await _rewrite(project.id);
    notifyListeners();
    return project;
  }

  Future<void> renameProject(String id, String rawName) async {
    final name = rawName.trim();
    final current = _mustProject(id);
    if (current.name == name) return;
    final error = nameError(name, exceptId: id);
    if (error != null) throw LedgerException(error);
    final next = current.copyWith(name: name, filePath: _allocatePath(name));
    await _repository.updateProject(next);
    final index = _projects.indexWhere((project) => project.id == id);
    _projects[index] = next;
    await _rewrite(id);
    final oldFile = File(current.filePath);
    if (oldFile.path != next.filePath && oldFile.existsSync()) {
      oldFile.deleteSync();
    }
    notifyListeners();
  }

  Future<void> deleteProject(String id) async {
    final project = _mustProject(id);
    final doomed = _entries.where((item) => item.projectId == id).toList();
    await _repository.deleteProject(id);
    _projects.removeWhere((item) => item.id == id);
    _entries.removeWhere((item) => item.projectId == id);
    for (final entry in doomed) {
      AttachmentFiles.deleteAll(attachmentsDir, entry.attachments);
    }
    _sizes.remove(id);
    final file = File(project.filePath);
    if (file.existsSync()) file.deleteSync();
    notifyListeners();
  }

  Future<SaveOutcome> saveNewEntries({
    required String projectId,
    required List<DraftEntry> drafts,
  }) async {
    if (drafts.isEmpty) return const SaveOutcome(SaveKind.empty, 0, false);
    if (saving) return const SaveOutcome(SaveKind.busy, 0, false);
    final hash = _hash(projectId, drafts);
    final now = DateTime.now();
    if (_recentHash == hash &&
        _recentAt != null &&
        now.difference(_recentAt!) < const Duration(seconds: 8)) {
      return const SaveOutcome(SaveKind.duplicate, 0, false);
    }
    for (final draft in drafts) {
      if (draft.content.trim().isEmpty || draft.amount <= 0 || !validLedgerDate(draft.date)) {
        throw LedgerException('请补全每一笔的内容、金额和日期');
      }
    }

    saving = true;
    notifyListeners();
    try {
      _mustProject(projectId);
      final createdAt = DateTime.now().millisecondsSinceEpoch;
      final entries = <LedgerEntry>[
        for (var i = 0; i < drafts.length; i++)
          LedgerEntry(
            id: _uuid.v4(),
            projectId: projectId,
            direction: drafts[i].direction,
            content: drafts[i].content.trim(),
            amount: roundMoney(drafts[i].amount),
            date: drafts[i].date,
            category: drafts[i].category.trim(),
            note: drafts[i].note.trim(),
            attachments: drafts[i].attachments,
            createdAt: createdAt + i,
          ),
      ];
      await _repository.insertEntries(entries);
      _entries.addAll(entries);
      final excelWritten = await _rewrite(projectId);
      _recentHash = hash;
      _recentAt = DateTime.now();
      return SaveOutcome(SaveKind.saved, entries.length, excelWritten);
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<void> updateEntry(LedgerEntry entry) async {
    if (entry.content.trim().isEmpty || entry.amount <= 0 || !validLedgerDate(entry.date)) {
      throw LedgerException('请补全内容、金额和日期');
    }
    final previous = _entries.where((item) => item.id == entry.id).firstOrNull;
    final next = entry.copyWith(
      content: entry.content.trim(),
      amount: roundMoney(entry.amount),
      category: entry.category.trim(),
      note: entry.note.trim(),
    );
    await _repository.updateEntry(next);
    if (previous != null) {
      AttachmentFiles.deleteRemoved(attachmentsDir, previous.attachments, next.attachments);
    }
    final index = _entries.indexWhere((item) => item.id == next.id);
    if (index >= 0) _entries[index] = next;
    await _rewrite(next.projectId);
    notifyListeners();
  }

  Future<void> deleteEntry(String id) async {
    final entry = _entries.where((item) => item.id == id).firstOrNull;
    if (entry == null) return;
    await _repository.deleteEntry(id);
    _entries.removeWhere((item) => item.id == id);
    AttachmentFiles.deleteAll(attachmentsDir, entry.attachments);
    await _rewrite(entry.projectId);
    notifyListeners();
  }

  Future<bool> ensureExcel(String projectId) => _rewrite(projectId);

  List<LedgerEntry> chronological(String projectId) {
    final entries = _entries.where((entry) => entry.projectId == projectId).toList()
      ..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        if (byDate != 0) return byDate;
        return a.createdAt.compareTo(b.createdAt);
      });
    return entries;
  }

  Future<bool> _rewrite(String projectId) async {
    final project = _mustProject(projectId);
    try {
      final bytes = await ExcelService.build(
        projectName: project.name,
        entries: chronological(projectId),
        attachmentsDir: attachmentsDir,
      );
      final file = File(project.filePath);
      file.parent.createSync(recursive: true);
      final temporary = File('${project.filePath}.writing');
      temporary.writeAsBytesSync(bytes, flush: true);
      if (file.existsSync()) file.deleteSync();
      temporary.renameSync(file.path);
      _refreshSize(project);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _refreshSize(CashProject project) {
    final file = File(project.filePath);
    _sizes[project.id] = file.existsSync() ? file.lengthSync() : 0;
  }

  CashProject _mustProject(String id) {
    final project = projectById(id);
    if (project == null) throw LedgerException('记账项目不存在');
    return project;
  }

  String _allocatePath(String name) {
    final stem = _safeStem(name);
    var candidate = p.join(_repository.excelDir.path, '$stem.xlsx');
    var index = 2;
    while (File(candidate).existsSync() || _projects.any((project) => project.filePath == candidate)) {
      candidate = p.join(_repository.excelDir.path, '$stem($index).xlsx');
      index++;
    }
    return candidate;
  }

  String _safeStem(String name) {
    const reserved = {'con', 'prn', 'aux', 'nul', 'com1', 'com2', 'lpt1', 'lpt2'};
    if (reserved.contains(name.toLowerCase())) return '${name}_账';
    return name;
  }

  String _hash(String projectId, List<DraftEntry> drafts) {
    final body = drafts
        .map(
          (draft) =>
              '${draft.direction.name}|${draft.date}|${draft.content.trim()}|${draft.amount.toStringAsFixed(2)}|${draft.category.trim()}|${draft.note.trim()}|${draft.attachments.map((item) => item.relativePath).join(',')}',
        )
        .join('||');
    return '$projectId::$body';
  }
}
