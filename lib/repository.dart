import 'dart:io';

import 'models.dart';

abstract class LedgerRepository {
  Directory get excelDir;

  Directory get attachmentsDir;

  Future<List<CashProject>> listProjects();

  Future<List<LedgerEntry>> listEntries();

  Future<void> insertProject(CashProject project);

  Future<void> updateProject(CashProject project);

  Future<void> deleteProject(String id);

  Future<void> insertEntries(List<LedgerEntry> entries);

  Future<void> updateEntry(LedgerEntry entry);

  Future<void> deleteEntry(String id);

  Future<void> close();
}
