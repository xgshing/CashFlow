enum MoneyDirection { expense, income }

extension MoneyDirectionText on MoneyDirection {
  String get label => this == MoneyDirection.income ? '收入' : '支出';
}

const categorySuggestions = <String>[
  '餐饮',
  '交通',
  '办公用品',
  '生活用品',
  '住房',
  '医疗',
  '购物',
  '娱乐',
  '设备采购',
  '工资',
  '项目收入',
  '其他',
];

class LedgerException implements Exception {
  LedgerException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CashProject {
  const CashProject({
    required this.id,
    required this.name,
    required this.filePath,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String filePath;
  final int createdAt;

  CashProject copyWith({String? name, String? filePath}) {
    return CashProject(
      id: id,
      name: name ?? this.name,
      filePath: filePath ?? this.filePath,
      createdAt: createdAt,
    );
  }
}

class LedgerAttachment {
  const LedgerAttachment({required this.name, required this.relativePath});

  final String name;
  final String relativePath;

  bool get isPdf => relativePath.toLowerCase().endsWith('.pdf');

  bool get canPreview {
    final path = relativePath.toLowerCase();
    return path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.png') ||
        path.endsWith('.webp') ||
        path.endsWith('.gif');
  }
}

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.projectId,
    required this.direction,
    required this.content,
    required this.amount,
    required this.date,
    required this.category,
    required this.note,
    required this.createdAt,
    this.attachments = const [],
  });

  final String id;
  final String projectId;
  final MoneyDirection direction;
  final String content;
  final double amount;
  final String date;
  final String category;
  final String note;
  final int createdAt;
  final List<LedgerAttachment> attachments;

  LedgerEntry copyWith({
    MoneyDirection? direction,
    String? content,
    double? amount,
    String? date,
    String? category,
    String? note,
    List<LedgerAttachment>? attachments,
  }) {
    return LedgerEntry(
      id: id,
      projectId: projectId,
      direction: direction ?? this.direction,
      content: content ?? this.content,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      category: category ?? this.category,
      note: note ?? this.note,
      createdAt: createdAt,
      attachments: attachments ?? this.attachments,
    );
  }
}

class ProjectSnapshot {
  const ProjectSnapshot({
    required this.project,
    required this.entries,
    required this.fileBytes,
  });

  final CashProject project;
  final List<LedgerEntry> entries;
  final int fileBytes;

  double get income => entries
      .where((entry) => entry.direction == MoneyDirection.income)
      .fold<double>(0, (sum, entry) => sum + entry.amount);

  double get expense => entries
      .where((entry) => entry.direction == MoneyDirection.expense)
      .fold<double>(0, (sum, entry) => sum + entry.amount);

  double get balance => income - expense;

  LedgerEntry? get latest => entries.isEmpty ? null : entries.first;
}

enum DraftOrigin { manual, parsed }

class DraftEntry {
  const DraftEntry({
    required this.localId,
    required this.direction,
    required this.content,
    required this.amount,
    required this.date,
    this.category = '',
    this.note = '',
    this.attachments = const [],
    this.origin = DraftOrigin.manual,
  });

  final int localId;
  final MoneyDirection direction;
  final String content;
  final double amount;
  final String date;
  final String category;
  final String note;
  final List<LedgerAttachment> attachments;
  final DraftOrigin origin;

  DraftEntry copyWith({
    MoneyDirection? direction,
    String? content,
    double? amount,
    String? date,
    String? category,
    String? note,
    List<LedgerAttachment>? attachments,
    DraftOrigin? origin,
  }) {
    return DraftEntry(
      localId: localId,
      direction: direction ?? this.direction,
      content: content ?? this.content,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      category: category ?? this.category,
      note: note ?? this.note,
      attachments: attachments ?? this.attachments,
      origin: origin ?? this.origin,
    );
  }
}

enum SaveKind { saved, duplicate, busy, empty }

class SaveOutcome {
  const SaveOutcome(this.kind, this.count, this.excelWritten);

  final SaveKind kind;
  final int count;
  final bool excelWritten;
}
