import 'dart:io';

import 'package:path/path.dart' as p;

import 'models.dart';
import 'repository.dart';

class MemoryLedgerRepository implements LedgerRepository {
  MemoryLedgerRepository(this.excelDir)
    : attachmentsDir = Directory(p.join(excelDir.parent.path, 'attachments'));

  @override
  final Directory excelDir;

  @override
  final Directory attachmentsDir;

  final List<CashProject> _projects = [];
  final List<LedgerEntry> _entries = [];

  @override
  Future<List<CashProject>> listProjects() async => List.unmodifiable(_projects);

  @override
  Future<List<LedgerEntry>> listEntries() async => List.unmodifiable(_entries);

  @override
  Future<void> insertProject(CashProject project) async {
    _projects.add(project);
  }

  @override
  Future<void> updateProject(CashProject project) async {
    final index = _projects.indexWhere((item) => item.id == project.id);
    if (index >= 0) _projects[index] = project;
  }

  @override
  Future<void> deleteProject(String id) async {
    _projects.removeWhere((item) => item.id == id);
    _entries.removeWhere((item) => item.projectId == id);
  }

  @override
  Future<void> insertEntries(List<LedgerEntry> entries) async {
    _entries.addAll(entries);
  }

  @override
  Future<void> updateEntry(LedgerEntry entry) async {
    final index = _entries.indexWhere((item) => item.id == entry.id);
    if (index >= 0) _entries[index] = entry;
  }

  @override
  Future<void> deleteEntry(String id) async {
    _entries.removeWhere((item) => item.id == id);
  }

  @override
  Future<void> close() async {}
}
