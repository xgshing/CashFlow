import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cashflow/attachment_files.dart';
import 'package:cashflow/excel_service.dart';
import 'package:cashflow/ledger_store.dart';
import 'package:cashflow/memory_repository.dart';
import 'package:cashflow/models.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('cashflow_ledger');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('writes summed excel and blocks an immediate duplicate save', () async {
    final store = LedgerStore(MemoryLedgerRepository(Directory(p.join(root.path, 'excel'))));
    await store.load();
    final project = await store.createProject('家庭日常');

    final first = await store.saveNewEntries(
      projectId: project.id,
      drafts: const [
        DraftEntry(
          localId: 1,
          direction: MoneyDirection.income,
          content: '项目服务费',
          amount: 5000,
          date: '2026-10-30',
          category: '项目收入',
        ),
        DraftEntry(
          localId: 2,
          direction: MoneyDirection.expense,
          content: '打印纸',
          amount: 268,
          date: '2026-10-30',
          category: '办公用品',
        ),
        DraftEntry(
          localId: 3,
          direction: MoneyDirection.expense,
          content: '文件夹',
          amount: 45,
          date: '2026-10-28',
          category: '办公用品',
        ),
      ],
    );
    expect(first.kind, SaveKind.saved);
    expect(first.excelWritten, isTrue);
    expect(store.snapshotById(project.id)!.balance, 5000 - 313);

    final duplicate = await store.saveNewEntries(
      projectId: project.id,
      drafts: const [
        DraftEntry(
          localId: 1,
          direction: MoneyDirection.income,
          content: '项目服务费',
          amount: 5000,
          date: '2026-10-30',
          category: '项目收入',
        ),
        DraftEntry(
          localId: 2,
          direction: MoneyDirection.expense,
          content: '打印纸',
          amount: 268,
          date: '2026-10-30',
          category: '办公用品',
        ),
        DraftEntry(
          localId: 3,
          direction: MoneyDirection.expense,
          content: '文件夹',
          amount: 45,
          date: '2026-10-28',
          category: '办公用品',
        ),
      ],
    );
    expect(duplicate.kind, SaveKind.duplicate);
    expect(store.snapshotById(project.id)!.entries, hasLength(3));

    final bytes = await File(project.filePath).readAsBytes();
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables[excelSheetName]!;
    String textAt(String cell) => (sheet.cell(CellIndex.indexByString(cell)).value as TextCellValue).value.text!;
    num numberAt(String cell) {
      final value = sheet.cell(CellIndex.indexByString(cell)).value;
      return switch (value) {
        DoubleCellValue(:final value) => value,
        IntCellValue(:final value) => value,
        _ => throw StateError('$cell is ${value.runtimeType}'),
      };
    }

    expect(textAt('A1'), '家庭日常记账明细');
    expect(excel.getMergedCells(excelSheetName), contains('A1:H1'));
    final packedStyles = ZipDecoder().decodeBytes(bytes);
    final stylesXml = utf8.decode(
      packedStyles.files.firstWhere((file) => file.name.endsWith('styles.xml')).content as List<int>,
    );
    final sheetXml = utf8.decode(
      packedStyles.files.firstWhere((file) => file.name.contains('worksheets/sheet')).content as List<int>,
    );
    expect(stylesXml, contains('horizontal="center"'));
    expect(stylesXml, contains('vertical="center"'));
    expect(stylesXml, contains('style="thin"'));
    expect(stylesXml, contains('4B5563'));
    expect(sheetXml, contains('ref="A1:H1"'));
    expect(textAt('C3'), '文件夹');
    expect(textAt('C4'), '项目服务费');
    expect(numberAt('F3'), 45);
    expect(numberAt('E4'), 5000);
    expect((sheet.cell(CellIndex.indexByString('E7')).value as FormulaCellValue).formula, 'SUM(E3:E5)');
    expect((sheet.cell(CellIndex.indexByString('F8')).value as FormulaCellValue).formula, 'SUM(F3:F5)');
    expect((sheet.cell(CellIndex.indexByString('E9')).value as FormulaCellValue).formula, 'E7-F8');

    final different = await store.saveNewEntries(
      projectId: project.id,
      drafts: const [
        DraftEntry(
          localId: 9,
          direction: MoneyDirection.expense,
          content: '午餐',
          amount: 35,
          date: '2026-10-30',
          category: '餐饮',
        ),
      ],
    );
    expect(different.kind, SaveKind.saved);
    expect(store.latestEntry!.content, '午餐');
  });

  test('edit and delete refresh the project balance', () async {
    final store = LedgerStore(MemoryLedgerRepository(Directory(p.join(root.path, 'excel'))));
    await store.load();
    final project = await store.createProject('装修费用');
    await store.saveNewEntries(
      projectId: project.id,
      drafts: const [
        DraftEntry(
          localId: 1,
          direction: MoneyDirection.expense,
          content: '水电费',
          amount: 120,
          date: '2026-10-30',
          category: '住房',
        ),
      ],
    );
    final entry = store.latestEntry!;
    await store.updateEntry(entry.copyWith(amount: 80));
    expect(store.snapshotById(project.id)!.expense, 80);
    await store.deleteEntry(entry.id);
    expect(store.snapshotById(project.id)!.entries, isEmpty);
    expect(store.snapshotById(project.id)!.balance, 0);
  });

  test('rejects a duplicate project name and removes the excel file on delete', () async {
    final store = LedgerStore(MemoryLedgerRepository(Directory(p.join(root.path, 'excel'))));
    await store.load();
    final project = await store.createProject('机器人项目');
    expect(File(project.filePath).existsSync(), isTrue);
    expect(() => store.createProject('机器人项目'), throwsA(isA<LedgerException>()));
    await store.deleteProject(project.id);
    expect(store.snapshots, isEmpty);
    expect(File(project.filePath).existsSync(), isFalse);
  });

  test('keeps an image or pdf with the entry and lists it before the note', () async {
    final store = LedgerStore(MemoryLedgerRepository(Directory(p.join(root.path, 'excel'))));
    await store.load();
    final project = await store.createProject('家庭日常');
    final source = File(p.join(root.path, '发票.pdf'));
    source.writeAsBytesSync([...ascii.encode('%PDF-1.4'), ...List<int>.filled(5000, 0x20)]);
    final attachment = AttachmentFiles.importFile(store.attachmentsDir, source.path, displayName: '发票.pdf');

    await store.saveNewEntries(
      projectId: project.id,
      drafts: [
        DraftEntry(
          localId: 1,
          direction: MoneyDirection.expense,
          content: '打印纸',
          amount: 45,
          date: '2026-10-30',
          category: '办公用品',
          note: '发票',
          attachments: [attachment],
        ),
      ],
    );

    final saved = store.latestEntry!;
    final stored = AttachmentFiles.resolve(store.attachmentsDir, saved.attachments.single);
    expect(saved.attachments.single.name, '发票.pdf');
    expect(saved.note, '发票');
    expect(stored.existsSync(), isTrue);

    final excel = Excel.decodeBytes(await File(project.filePath).readAsBytes());
    final sheet = excel.tables[excelSheetName]!;
    String textAt(String cell) => (sheet.cell(CellIndex.indexByString(cell)).value as TextCellValue).value.text!;
    expect(textAt('G2'), '附件');
    expect(textAt('H2'), '备注');
    final attachmentCell = sheet.cell(CellIndex.indexByString('G3')).value;
    final attachmentText = attachmentCell is TextCellValue ? attachmentCell.value.text : '';
    expect(attachmentText, '');
    expect(textAt('H3'), '发票');
    final packed = ZipDecoder().decodeBytes(await File(project.filePath).readAsBytes());
    final embedded = packed.files.where((file) => file.name.contains('oleObject')).toList();
    expect(embedded, isNotEmpty);
    final oleBytes = embedded.first.content as List<int>;
    expect(_pdfInsideOle(oleBytes), isTrue);
    expect(oleBytes, containsAll(const [0x0C, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46]));
    final vml = packed.files.firstWhere((file) => file.name.contains('vmlDrawing') && file.name.endsWith('.vml'));
    expect(utf8.decode(vml.content as List<int>), contains('o:ole="t"'));
    final sheetFile = packed.files.firstWhere((file) => file.name.contains('worksheets/sheet'));
    final sheetXml = utf8.decode(sheetFile.content as List<int>);
    expect(sheetXml, contains('legacyDrawing'));
    expect(sheetXml, contains('progId="Package"'));
    expect(sheetXml, isNot(contains('<xdr:pic>')));

    await store.updateEntry(saved.copyWith(attachments: const []));
    expect(stored.existsSync(), isFalse);
    expect(store.latestEntry!.note, '发票');
  });

  test('embeds a picture into the workbook attachment column', () async {
    final store = LedgerStore(MemoryLedgerRepository(Directory(p.join(root.path, 'excel'))));
    await store.load();
    final project = await store.createProject('家庭日常');
    final source = File(p.join(root.path, '收据.png'));
    source.writeAsBytesSync(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    ));
    final attachment = AttachmentFiles.importFile(store.attachmentsDir, source.path, displayName: '收据.png');
    await store.saveNewEntries(
      projectId: project.id,
      drafts: [
        DraftEntry(
          localId: 1,
          direction: MoneyDirection.expense,
          content: '午餐',
          amount: 35,
          date: '2026-10-30',
          attachments: [attachment],
        ),
      ],
    );
    final packed = ZipDecoder().decodeBytes(await File(project.filePath).readAsBytes());
    expect(packed.files.any((file) => file.name.contains('xl/media/image')), isTrue);
    final sheet = packed.files.firstWhere((file) => file.name.contains('worksheets/sheet'));
    expect(utf8.decode(sheet.content as List<int>), contains('rIdDrawing'));
  });
}

bool _pdfInsideOle(List<int> raw) {
  const endOfChain = 0xFFFFFFFE;
  const sectorSize = 512;
  final bytes = Uint8List.fromList(raw);
  if (bytes.length < sectorSize) return false;
  final header = ByteData.sublistView(bytes);
  final fatCount = header.getUint32(0x2C, Endian.little);
  final dirStart = header.getUint32(0x30, Endian.little);
  final cutoff = header.getUint32(0x38, Endian.little);
  final miniFatStart = header.getUint32(0x3C, Endian.little);
  if (cutoff != 4096 || miniFatStart == endOfChain) return false;

  int at(int sector) => sectorSize * (1 + sector);
  final fat = <int>[];
  for (var index = 0; index < fatCount; index++) {
    final view = ByteData.sublistView(bytes, at(index), at(index) + sectorSize);
    for (var slot = 0; slot < 128; slot++) {
      fat.add(view.getUint32(slot * 4, Endian.little));
    }
  }

  Uint8List readChain(int start, int size) {
    final out = BytesBuilder();
    var sector = start;
    var guard = 0;
    while (sector != endOfChain && sector < fat.length && guard < 10000) {
      out.add(bytes.sublist(at(sector), at(sector) + sectorSize));
      sector = fat[sector];
      guard++;
    }
    final joined = out.toBytes();
    return Uint8List.sublistView(joined, 0, size);
  }

  ByteData entry(int index) => ByteData.sublistView(bytes, at(dirStart) + index * 128, at(dirStart) + (index + 1) * 128);
  String nameOf(int index) {
    final view = entry(index);
    final chars = (view.getUint16(64, Endian.little) ~/ 2) - 1;
    if (chars <= 0) return '';
    return String.fromCharCodes([for (var i = 0; i < chars; i++) view.getUint16(i * 2, Endian.little)]);
  }

  final root = entry(0);
  final miniStream = readChain(root.getUint32(0x74, Endian.little), root.getUint32(0x78, Endian.little));
  final miniFat = <int>[];
  var sector = miniFatStart;
  var guard = 0;
  while (sector != endOfChain && sector < fat.length && guard < 100) {
    final view = ByteData.sublistView(bytes, at(sector), at(sector) + sectorSize);
    for (var slot = 0; slot < 128; slot++) {
      miniFat.add(view.getUint32(slot * 4, Endian.little));
    }
    sector = fat[sector];
    guard++;
  }

  Uint8List readMini(int start, int size) {
    final out = BytesBuilder();
    var cursor = start;
    var steps = 0;
    while (cursor != endOfChain && cursor < miniFat.length && steps < 10000) {
      out.add(miniStream.sublist(cursor * 64, cursor * 64 + 64));
      cursor = miniFat[cursor];
      steps++;
    }
    return Uint8List.sublistView(out.toBytes(), 0, size);
  }

  for (var index = 1; index < 8; index++) {
    final name = nameOf(index);
    if (name.isEmpty) break;
    if (!name.contains('Ole10Native')) continue;
    final view = entry(index);
    final size = view.getUint32(0x78, Endian.little);
    final start = view.getUint32(0x74, Endian.little);
    final native = size < cutoff ? readMini(start, size) : readChain(start, size);
    if (native.length < 4) return false;
    final declared = ByteData.sublistView(native).getUint32(0, Endian.little);
    return declared == native.length - 4 && latin1.decode(native, allowInvalid: true).contains('%PDF');
  }
  return false;
}
