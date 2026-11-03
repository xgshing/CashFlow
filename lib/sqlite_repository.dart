import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'attachment_files.dart';
import 'models.dart';
import 'repository.dart';

class SqliteLedgerRepository implements LedgerRepository {
  SqliteLedgerRepository._(this._db, this.excelDir, this.attachmentsDir);

  final Database _db;

  @override
  final Directory excelDir;

  @override
  final Directory attachmentsDir;

  static Future<SqliteLedgerRepository> open({Directory? root}) async {
    final base = root ?? await getApplicationDocumentsDirectory();
    final excelDir = Directory(p.join(base.path, 'excel'));
    final attachmentsDir = Directory(p.join(base.path, 'attachments'));
    await excelDir.create(recursive: true);
    await attachmentsDir.create(recursive: true);
    final db = await openDatabase(
      p.join(base.path, 'cashflow.db'),
      version: 2,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE projects (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            file_path TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE entries (
            id TEXT PRIMARY KEY,
            project_id TEXT NOT NULL,
            direction TEXT NOT NULL,
            content TEXT NOT NULL,
            amount REAL NOT NULL,
            entry_date TEXT NOT NULL,
            category TEXT NOT NULL,
            note TEXT NOT NULL,
            attachments TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_entries_project ON entries(project_id)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute("ALTER TABLE entries ADD COLUMN attachments TEXT NOT NULL DEFAULT '[]'");
        }
      },
    );
    return SqliteLedgerRepository._(db, excelDir, attachmentsDir);
  }

  @override
  Future<List<CashProject>> listProjects() async {
    final rows = await _db.query('projects', orderBy: 'created_at DESC');
    return rows.map(_projectFromRow).toList();
  }

  @override
  Future<List<LedgerEntry>> listEntries() async {
    final rows = await _db.query('entries', orderBy: 'created_at ASC');
    return rows.map(_entryFromRow).toList();
  }

  @override
  Future<void> insertProject(CashProject project) async {
    await _db.insert('projects', {
      'id': project.id,
      'name': project.name,
      'file_path': project.filePath,
      'created_at': project.createdAt,
    });
  }

  @override
  Future<void> updateProject(CashProject project) async {
    await _db.update(
      'projects',
      {'name': project.name, 'file_path': project.filePath},
      where: 'id = ?',
      whereArgs: [project.id],
    );
  }

  @override
  Future<void> deleteProject(String id) async {
    await _db.transaction((txn) async {
      await txn.delete('entries', where: 'project_id = ?', whereArgs: [id]);
      await txn.delete('projects', where: 'id = ?', whereArgs: [id]);
    });
  }

  @override
  Future<void> insertEntries(List<LedgerEntry> entries) async {
    await _db.transaction((txn) async {
      for (final entry in entries) {
        await txn.insert('entries', _entryToMap(entry));
      }
    });
  }

  @override
  Future<void> updateEntry(LedgerEntry entry) async {
    await _db.update('entries', _entryToMap(entry), where: 'id = ?', whereArgs: [entry.id]);
  }

  @override
  Future<void> deleteEntry(String id) async {
    await _db.delete('entries', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> close() => _db.close();
}

CashProject _projectFromRow(Map<String, Object?> row) {
  return CashProject(
    id: row['id']! as String,
    name: row['name']! as String,
    filePath: row['file_path']! as String,
    createdAt: row['created_at']! as int,
  );
}

LedgerEntry _entryFromRow(Map<String, Object?> row) {
  return LedgerEntry(
    id: row['id']! as String,
    projectId: row['project_id']! as String,
    direction: row['direction'] == 'income' ? MoneyDirection.income : MoneyDirection.expense,
    content: row['content']! as String,
    amount: (row['amount']! as num).toDouble(),
    date: row['entry_date']! as String,
    category: row['category']! as String,
    note: row['note']! as String,
    createdAt: row['created_at']! as int,
    attachments: AttachmentFiles.decode(row['attachments']),
  );
}

Map<String, Object?> _entryToMap(LedgerEntry entry) {
  return {
    'id': entry.id,
    'project_id': entry.projectId,
    'direction': entry.direction.name,
    'content': entry.content,
    'amount': entry.amount,
    'entry_date': entry.date,
    'category': entry.category,
    'note': entry.note,
    'attachments': AttachmentFiles.encode(entry.attachments),
    'created_at': entry.createdAt,
  };
}
