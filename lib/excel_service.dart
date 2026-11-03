import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'device_bridge.dart';
import 'excel_embed.dart';
import 'models.dart';

class ExcelService {
  static Future<List<int>> build({
    required String projectName,
    required List<LedgerEntry> entries,
    required Directory attachmentsDir,
  }) async {
    final fileIcons = await _fileIcons(entries);
    final excel = Excel.createExcel();
    excel.rename('Sheet1', _sheetName);
    final sheet = excel[_sheetName];

    final line = Border(
      borderStyle: BorderStyle.Thin,
      borderColorHex: ExcelColor.fromHexString('FF4B5563'),
    );
    final title = CellStyle(
      bold: true,
      fontSize: 16,
      fontColorHex: ExcelColor.fromHexString('FF1F2937'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    final header = _boxed(
      line,
      bold: true,
      font: ExcelColor.white,
      background: ExcelColor.fromHexString('FF1677E8'),
    );
    final text = _boxed(line);
    final income = _boxed(
      line,
      font: ExcelColor.fromHexString('FF067647'),
      numberFormat: NumFormat.standard_4,
    );
    final expense = _boxed(
      line,
      font: ExcelColor.fromHexString('FFE5484D'),
      numberFormat: NumFormat.standard_4,
    );
    final totalLabel = _boxed(line, bold: true);
    final totalNumber = _boxed(line, bold: true, numberFormat: NumFormat.standard_4);

    _put(sheet, 0, 0, TextCellValue('$projectName记账明细'), title);
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: 0),
    );
    sheet.setMergedCellStyle(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0), title);
    const headers = ['序号', '日期', '记账内容', '类别', '收入', '支出', '附件', '备注'];
    for (var column = 0; column < headers.length; column++) {
      _put(sheet, column, 1, TextCellValue(headers[column]), header);
    }
    _fillEmpty(sheet, 1, header);

    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      final row = index + 2;
      _put(sheet, 0, row, IntCellValue(index + 1), text);
      _put(sheet, 1, row, TextCellValue(entry.date), text);
      _put(sheet, 2, row, TextCellValue(entry.content), text);
      _put(sheet, 3, row, TextCellValue(entry.category), text);
      if (entry.direction == MoneyDirection.income) {
        _put(sheet, 4, row, DoubleCellValue(entry.amount), income);
      } else {
        _put(sheet, 5, row, DoubleCellValue(entry.amount), expense);
      }
      _put(sheet, 6, row, TextCellValue(''), text);
      _put(sheet, 7, row, TextCellValue(entry.note), text);
      if (entry.attachments.isNotEmpty) {
        sheet.setRowHeight(row, 96.0 * entry.attachments.length);
      }
      _fillEmpty(sheet, row, text);
    }

    final totalRow = entries.isEmpty ? 3 : entries.length + 3;
    if (entries.isEmpty) {
      _put(sheet, 2, totalRow, TextCellValue('收入合计'), totalLabel);
      _put(sheet, 4, totalRow, DoubleCellValue(0), totalNumber);
      _put(sheet, 2, totalRow + 1, TextCellValue('支出合计'), totalLabel);
      _put(sheet, 5, totalRow + 1, DoubleCellValue(0), totalNumber);
      _put(sheet, 2, totalRow + 2, TextCellValue('结余'), totalLabel);
      _put(sheet, 4, totalRow + 2, DoubleCellValue(0), totalNumber);
      _fillEmpty(sheet, totalRow, text);
      _fillEmpty(sheet, totalRow + 1, text);
      _fillEmpty(sheet, totalRow + 2, text);
    } else {
      final lastExcelRow = entries.length + 2;
      final incomeExcelRow = totalRow + 1;
      final expenseExcelRow = totalRow + 2;
      _put(sheet, 2, totalRow, TextCellValue('收入合计'), totalLabel);
      _put(
        sheet,
        4,
        totalRow,
        FormulaCellValue('SUM(E3:E$lastExcelRow)'),
        totalNumber,
      );
      _put(sheet, 2, totalRow + 1, TextCellValue('支出合计'), totalLabel);
      _put(
        sheet,
        5,
        totalRow + 1,
        FormulaCellValue('SUM(F3:F$lastExcelRow)'),
        totalNumber,
      );
      _put(sheet, 2, totalRow + 2, TextCellValue('结余'), totalLabel);
      _put(
        sheet,
        4,
        totalRow + 2,
        FormulaCellValue('E$incomeExcelRow-F$expenseExcelRow'),
        totalNumber,
      );
      _fillEmpty(sheet, totalRow, text);
      _fillEmpty(sheet, totalRow + 1, text);
      _fillEmpty(sheet, totalRow + 2, text);
    }

    sheet.setColumnWidth(0, 8);
    sheet.setColumnWidth(1, 14);
    sheet.setColumnWidth(2, 28);
    sheet.setColumnWidth(3, 14);
    sheet.setColumnWidth(4, 14);
    sheet.setColumnWidth(5, 14);
    sheet.setColumnWidth(6, 28);
    sheet.setColumnWidth(7, 22);

    final bytes = excel.encode();
    if (bytes == null) {
      throw StateError('无法生成 Excel');
    }
    return ExcelBundle.embed(
      workbook: bytes,
      entries: entries,
      attachmentsDir: attachmentsDir,
      fileIcons: fileIcons,
    );
  }

  static Future<Map<String, Uint8List>> _fileIcons(List<LedgerEntry> entries) async {
    final icons = <String, Uint8List>{};
    for (final entry in entries) {
      for (final attachment in entry.attachments) {
        if (!attachment.isPdf) continue;
        final label = pdfFileLabel(attachment.name);
        if (icons.containsKey(label)) continue;
        final icon = await DeviceBridge.fileIcon(label);
        if (icon != null && icon.isNotEmpty) icons[label] = icon;
      }
    }
    return icons;
  }

  static CellStyle _boxed(
    Border line, {
    bool bold = false,
    ExcelColor? font,
    ExcelColor? background,
    NumFormat? numberFormat,
  }) {
    return CellStyle(
      bold: bold,
      fontColorHex: font ?? ExcelColor.fromHexString('FF1F2937'),
      backgroundColorHex: background ?? ExcelColor.none,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      leftBorder: line,
      rightBorder: line,
      topBorder: line,
      bottomBorder: line,
      numberFormat: numberFormat ?? NumFormat.standard_0,
    );
  }

  static void _fillEmpty(Sheet sheet, int row, CellStyle style) {
    for (var column = 0; column < 8; column++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row));
      if (cell.value == null) {
        cell.value = TextCellValue('');
        cell.cellStyle = style;
      }
    }
  }

  static void _put(Sheet sheet, int column, int row, CellValue value, CellStyle style) {
    final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row));
    cell.value = value;
    cell.cellStyle = style;
  }
}

const excelSheetName = _sheetName;
const _sheetName = '记账明细';
