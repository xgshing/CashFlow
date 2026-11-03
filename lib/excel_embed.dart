import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:gbk_codec/gbk_codec.dart';

import 'attachment_files.dart';
import 'models.dart';

/// Keeps the original file name and its suffix, such as 发票.pdf.
String fileLabel(String name, String extension) {
  final suffix = extension.startsWith('.') ? extension.toLowerCase() : '.${extension.toLowerCase()}';
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '附件$suffix';
  return trimmed.toLowerCase().endsWith(suffix) ? trimmed : '$trimmed$suffix';
}

String pdfFileLabel(String name) => fileLabel(name, '.pdf');

/// Puts pictures and one embedded PDF file per attachment into an xlsx.
class ExcelBundle {
  static List<int> embed({
    required List<int> workbook,
    required List<LedgerEntry> entries,
    required Directory attachmentsDir,
    Map<String, Uint8List> fileIcons = const {},
  }) {
    final items = <_SheetFile>[];
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      final files = <_SheetFile>[];
      for (final attachment in entry.attachments) {
        final file = AttachmentFiles.resolve(attachmentsDir, attachment);
        if (!file.existsSync()) continue;
        final extension = _fileExtension(attachment.relativePath);
        final kind = _kindOf(attachment.relativePath);
        files.add(
          _SheetFile(
            row: index + 2,
            slot: files.length,
            slots: 0,
            points: 96,
            extension: extension,
            bytes: Uint8List.fromList(file.readAsBytesSync()),
            kind: kind,
            label: kind == _FileKind.package ? fileLabel(attachment.name, extension) : '',
          ),
        );
      }
      for (final item in files) {
        items.add(
          _SheetFile(
            row: item.row,
            slot: item.slot,
            slots: files.length,
            points: item.points,
            extension: item.extension,
            bytes: item.bytes,
            kind: item.kind,
            label: item.label,
          ),
        );
      }
    }
    if (items.isEmpty) return workbook;

    final archive = ZipDecoder().decodeBytes(workbook);
    final sheet = archive.files.cast<ArchiveFile?>().firstWhere(
      (file) => file != null && _isSheet(file.name),
      orElse: () => null,
    );
    if (sheet == null) return workbook;

    final pictures = items.where((item) => item.kind == _FileKind.image).toList();
    final packages = items.where((item) => item.kind == _FileKind.package).toList();
    final drawingRels = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..writeln('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
    final anchors = StringBuffer();
    var pictureId = 2;
    var rel = 1;

    for (final picture in pictures) {
      final extension = picture.extension;
      final mediaName = 'image$rel$extension';
      archive.addFile(ArchiveFile('xl/media/$mediaName', picture.bytes.length, picture.bytes));
      drawingRels.writeln(
        '<Relationship Id="rId$rel" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/$mediaName"/>',
      );
      anchors.write(_fitInCell(picture, pictureId, 'rId$rel', keepAspect: false));
      pictureId++;
      rel++;
    }

    final sheetRels = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..writeln('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
    final hasDrawing = pictures.isNotEmpty;
    if (hasDrawing) {
      sheetRels.writeln(
        '<Relationship Id="rIdDrawing" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/>',
      );
    }
    if (packages.isNotEmpty) {
      sheetRels.writeln(
        '<Relationship Id="rIdVml" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/vmlDrawing" Target="../drawings/vmlDrawing1.vml"/>',
      );
    }

    final oleXml = StringBuffer();
    final vmlRels = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..writeln('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
    final vmlShapes = StringBuffer();
    if (packages.isNotEmpty) oleXml.writeln('<oleObjects>');
    for (var index = 0; index < packages.length; index++) {
      final item = packages[index];
      final shapeId = 1025 + index;
      final oleBytes = _olePackage(item.label, item.bytes);
      final part = 'xl/embeddings/oleObject${index + 1}.bin';
      archive.addFile(ArchiveFile(part, oleBytes.length, oleBytes));
      final icon = fileIcons[item.label];
      final iconBytes = icon == null || icon.isEmpty ? _fallbackIcon : icon;
      final mediaName = 'ole-icon${index + 1}.png';
      archive.addFile(ArchiveFile('xl/media/$mediaName', iconBytes.length, iconBytes));
      sheetRels.writeln(
        '<Relationship Id="rIdOle${index + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/oleObject" Target="../embeddings/oleObject${index + 1}.bin"/>',
      );
      sheetRels.writeln(
        '<Relationship Id="rIdIcon${index + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/$mediaName"/>',
      );
      vmlRels.writeln(
        '<Relationship Id="rId${index + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/$mediaName"/>',
      );
      vmlShapes.write(_vmlOleShape(item, shapeId, 'rId${index + 1}'));
      oleXml.write(_embeddedPdf(item, shapeId, 'rIdOle${index + 1}', 'rIdIcon${index + 1}'));
    }
    if (packages.isNotEmpty) oleXml.writeln('</oleObjects>');
    vmlRels.writeln('</Relationships>');

    drawingRels.writeln('</Relationships>');
    sheetRels.writeln('</Relationships>');

    final drawing = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
${anchors.toString()}</xdr:wsDr>
''';
    if (hasDrawing) {
      archive.addFile(_xmlFile('xl/drawings/drawing1.xml', drawing));
      archive.addFile(_xmlFile('xl/drawings/_rels/drawing1.xml.rels', drawingRels.toString()));
    }
    if (packages.isNotEmpty) {
      archive.addFile(_xmlFile('xl/drawings/vmlDrawing1.vml', _vmlDocument(vmlShapes.toString())));
      archive.addFile(_xmlFile('xl/drawings/_rels/vmlDrawing1.vml.rels', vmlRels.toString()));
    }

    final sheetRelsName = _relsName(sheet.name);
    final existingRels = archive.files.cast<ArchiveFile?>().firstWhere(
      (file) => file != null && file.name.replaceAll('\\', '/') == sheetRelsName,
      orElse: () => null,
    );
    if (existingRels == null) {
      archive.addFile(_xmlFile(sheetRelsName, sheetRels.toString()));
    } else {
      var relsXml = utf8.decode(_bytes(existingRels));
      final extras = RegExp(r'<Relationship\b[^>]*/>').allMatches(sheetRels.toString()).map((match) => match.group(0)!).join();
      relsXml = relsXml.replaceFirst('</Relationships>', '$extras</Relationships>');
      archive.addFile(_xmlFile(existingRels.name, relsXml));
    }

    var sheetXml = _worksheetNamespaces(utf8.decode(_bytes(sheet)), packages.isNotEmpty);
    final drawingTag = hasDrawing ? '<drawing r:id="rIdDrawing"/>' : '';
    final legacyTag = packages.isNotEmpty ? '<legacyDrawing r:id="rIdVml"/>' : '';
    sheetXml = sheetXml.replaceFirst('</worksheet>', '$drawingTag$legacyTag${oleXml.toString()}</worksheet>');
    archive.addFile(_xmlFile(sheet.name, sheetXml));
    _ensureContentTypes(archive, pictures, packages.isNotEmpty, packages.isNotEmpty);

    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) return workbook;
    return encoded;
  }

  static void _ensureContentTypes(Archive archive, List<_SheetFile> pictures, bool hasPackage, bool hasIcon) {
    final types = archive.files.cast<ArchiveFile?>().firstWhere(
      (file) => file != null && file.name.replaceAll('\\', '/').endsWith('[Content_Types].xml'),
      orElse: () => null,
    );
    if (types == null) return;
    var xml = utf8.decode(_bytes(types));
    void addDefault(String extension, String contentType) {
      if (xml.contains('Extension="$extension"')) return;
      xml = xml.replaceFirst(
        '</Types>',
        '<Default Extension="$extension" ContentType="$contentType"/></Types>',
      );
    }

    for (final picture in pictures) {
      final extension = picture.extension.replaceFirst('.', '');
      addDefault(extension, _imageType(extension));
    }
    if (hasIcon || pictures.any((item) => item.extension.endsWith('png'))) {
      addDefault('png', 'image/png');
    }
    if (hasPackage) {
      addDefault('bin', 'application/vnd.openxmlformats-officedocument.oleObject');
      addDefault('vml', 'application/vnd.openxmlformats-officedocument.vmlDrawing');
    }
    if ((pictures.isNotEmpty || hasIcon) && !xml.contains('/xl/drawings/drawing1.xml')) {
      xml = xml.replaceFirst(
        '</Types>',
        '<Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/></Types>',
      );
    }
    archive.addFile(_xmlFile(types.name, xml));
  }
}

enum _FileKind { image, package }

class _SheetFile {
  const _SheetFile({
    required this.row,
    required this.slot,
    required this.slots,
    required this.points,
    required this.extension,
    required this.bytes,
    required this.kind,
    required this.label,
  });

  final int row;
  final int slot;
  final int slots;
  final int points;
  final String extension;
  final Uint8List bytes;
  final _FileKind kind;
  final String label;
}

String _worksheetNamespaces(String sheetXml, bool packages) {
  final match = RegExp(r'<worksheet\b[^>]*>').firstMatch(sheetXml);
  if (match == null) return sheetXml;
  var open = match.group(0)!;
  void add(String name, String value) {
    if (open.contains('$name=')) return;
    open = open.replaceFirst('>', ' $name="$value">');
  }

  add('xmlns:r', 'http://schemas.openxmlformats.org/officeDocument/2006/relationships');
  if (!packages) return sheetXml.replaceFirst(match.group(0)!, open);
  add('xmlns:mc', 'http://schemas.openxmlformats.org/markup-compatibility/2006');
  add('xmlns:x14', 'http://schemas.microsoft.com/office/spreadsheetml/2009/9/main');
  add('xmlns:xdr', 'http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing');
  if (!open.contains('mc:Ignorable')) open = open.replaceFirst('>', ' mc:Ignorable="x14">');
  return sheetXml.replaceFirst(match.group(0)!, open);
}

String _embeddedPdf(_SheetFile item, int shapeId, String oleRel, String iconRel) {
  const slot = 96 * 12700;
  final top = item.slot * slot + 40000;
  final bottom = top + 800000;
  return '''
<mc:AlternateContent xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006">
  <mc:Choice Requires="x14">
    <oleObject progId="Package" dvAspect="DVASPECT_ICON" shapeId="$shapeId" r:id="$oleRel">
      <objectPr r:id="$iconRel" defaultSize="0" autoPict="1">
        <anchor moveWithCells="1">
          <from><xdr:col>6</xdr:col><xdr:colOff>80000</xdr:colOff><xdr:row>${item.row}</xdr:row><xdr:rowOff>$top</xdr:rowOff></from>
          <to><xdr:col>6</xdr:col><xdr:colOff>1400000</xdr:colOff><xdr:row>${item.row}</xdr:row><xdr:rowOff>$bottom</xdr:rowOff></to>
        </anchor>
      </objectPr>
    </oleObject>
  </mc:Choice>
  <mc:Fallback>
    <oleObject progId="Package" dvAspect="DVASPECT_ICON" shapeId="$shapeId" r:id="$oleRel"/>
  </mc:Fallback>
</mc:AlternateContent>
''';
}

String _vmlOleShape(_SheetFile item, int shapeId, String relId) {
  const slot = 110;
  final top = 6 + item.slot * slot;
  final bottomRow = item.slot == item.slots - 1 ? item.row + 1 : item.row;
  final bottom = item.slot == item.slots - 1 ? 6 : top + slot;
  final title = _xmlText(item.label);
  return '''
<v:shape id="_x0000_s$shapeId" o:spid="_x0000_s$shapeId" type="#_x0000_t75" o:ole="t" filled="f" stroked="f" style="position:absolute;margin-left:0;margin-top:0;width:100pt;height:48pt;z-index:${item.slot + 1}">
  <v:imagedata o:relid="$relId" o:title="$title"/>
  <x:ClientData ObjectType="Pict">
    <x:MoveWithCells/>
    <x:SizeWithCells/>
    <x:Anchor>6,8,${item.row},$top,7,8,$bottomRow,$bottom</x:Anchor>
  </x:ClientData>
</v:shape>
''';
}

String _vmlDocument(String shapes) {
  return '''
<xml xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:excel">
  <o:shapelayout v:ext="edit"><o:idmap v:ext="edit" data="1"/></o:shapelayout>
  <v:shapetype id="_x0000_t75" coordsize="21600,21600" o:spt="75" o:preferrelative="t" path="m@4@5l@4@11@9@11@9@5xe" filled="f" stroked="f">
    <v:stroke joinstyle="miter"/>
    <v:formulas>
      <v:f eqn="if lineDrawn pixelLineWidth 0"/><v:f eqn="sum @0 1 0"/><v:f eqn="sum 0 0 @1"/>
      <v:f eqn="prod @2 1 2"/><v:f eqn="prod @3 21600 pixelWidth"/><v:f eqn="prod @3 21600 pixelHeight"/>
      <v:f eqn="sum @0 0 1"/><v:f eqn="prod @6 1 2"/><v:f eqn="prod @7 21600 pixelWidth"/>
      <v:f eqn="sum @8 21600 0"/><v:f eqn="prod @7 21600 pixelHeight"/><v:f eqn="sum @10 21600 0"/>
    </v:formulas>
    <v:path o:extrusionok="f" gradientshapeok="t" o:connecttype="rect"/>
    <o:lock v:ext="edit" aspectratio="t"/>
  </v:shapetype>
  $shapes
</xml>
''';
}

final Uint8List _fallbackIcon = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

_FileKind _kindOf(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.webp')) {
    return _FileKind.image;
  }
  return _FileKind.package;
}

String _fileExtension(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return '.bin';
  final extension = path.substring(dot).toLowerCase();
  if (!RegExp(r'^\.[a-z0-9]+$').hasMatch(extension)) return '.bin';
  return extension;
}

String _imageType(String extension) {
  return switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    _ => 'image/png',
  };
}

bool _isSheet(String name) {
  final normalized = name.replaceAll('\\', '/');
  return normalized.contains('xl/worksheets/sheet') &&
      normalized.endsWith('.xml') &&
      !normalized.contains('/_rels/');
}

String _relsName(String sheetName) {
  final normalized = sheetName.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  final folder = normalized.substring(0, slash);
  final file = normalized.substring(slash + 1);
  return '$folder/_rels/$file.rels';
}

ArchiveFile _xmlFile(String name, String xml) {
  final bytes = utf8.encode(xml);
  return ArchiveFile(name, bytes.length, bytes);
}

Uint8List _bytes(ArchiveFile file) {
  final content = file.content;
  if (content is Uint8List) return content;
  return Uint8List.fromList(content);
}

String _xmlText(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

String _fitInCell(_SheetFile item, int id, String relId, {required bool keepAspect, String name = ''}) {
  final slot = item.points * 12700;
  final top = item.slot * slot;
  final last = item.slot == item.slots - 1;
  final toRow = last ? item.row + 1 : item.row;
  final toOff = last ? 0 : top + slot;
  final aspect = keepAspect ? '1' : '0';
  final shapeName = _xmlText(name.isEmpty ? '附件$id' : name);
  return '''
<xdr:twoCellAnchor editAs="oneCell">
  <xdr:from><xdr:col>6</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>${item.row}</xdr:row><xdr:rowOff>$top</xdr:rowOff></xdr:from>
  <xdr:to><xdr:col>7</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>$toRow</xdr:row><xdr:rowOff>$toOff</xdr:rowOff></xdr:to>
  <xdr:pic>
    <xdr:nvPicPr><xdr:cNvPr id="$id" name="$shapeName"/><xdr:cNvPicPr><a:picLocks noChangeAspect="$aspect"/></xdr:cNvPicPr></xdr:nvPicPr>
    <xdr:blipFill><a:blip r:embed="$relId"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill>
    <xdr:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr>
  </xdr:pic>
  <xdr:clientData/>
</xdr:twoCellAnchor>
''';
}

Uint8List _olePackage(String fileName, Uint8List data) {
  final native = _ole10Native(fileName, data);
  return _compoundFile([
    _OleStream('\u0001Ole', _oleStream),
    _OleStream('\u0001CompObj', _compObj),
    _OleStream('\u0001Ole10Native', native),
  ]);
}

final Uint8List _oleStream = Uint8List.fromList([
  0x01, 0x00, 0x00, 0x02, // OLE version
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
]);

const List<int> _packageClsid = [
  0x0C, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00,
  0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46,
];

final Uint8List _compObj = Uint8List.fromList([
  0x01, 0x00, 0xFE, 0xFF,
  0x03, 0x0A, 0x00, 0x00,
  0xFF, 0xFF, 0xFF, 0xFF,
  ..._packageClsid,
  0x08, 0x00, 0x00, 0x00, 0x50, 0x61, 0x63, 0x6B, 0x61, 0x67, 0x65, 0x00,
  0x08, 0x00, 0x00, 0x00, 0x50, 0x61, 0x63, 0x6B, 0x61, 0x67, 0x65, 0x00,
  0xF4, 0x39, 0xB2, 0x71,
  0x08, 0x00, 0x00, 0x00,
  0x50, 0x00, 0x61, 0x00, 0x63, 0x00, 0x6B, 0x00, 0x61, 0x00, 0x67, 0x00, 0x65, 0x00, 0x00, 0x00,
  0x08, 0x00, 0x00, 0x00,
  0x50, 0x00, 0x61, 0x00, 0x63, 0x00, 0x6B, 0x00, 0x61, 0x00, 0x67, 0x00, 0x65, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
]);

List<int> _labelBytes(String fileName) {
  final named = fileName.replaceAll(RegExp(r'[\r\n\\/:*?"<>|]'), '_');
  try {
    return gbk.encode(named);
  } catch (_) {
    return ascii.encode('file.pdf');
  }
}

Uint8List _ole10Native(String fileName, Uint8List data) {
  final name = _labelBytes(fileName);
  final body = BytesBuilder();
  void u16(int value) => body.add([value & 0xff, (value >> 8) & 0xff]);
  void u32(int value) => body.add([
    value & 0xff,
    (value >> 8) & 0xff,
    (value >> 16) & 0xff,
    (value >> 24) & 0xff,
  ]);
  void text(List<int> bytes) {
    body.add(bytes);
    body.add([0]);
  }

  void utf16(String value) {
    final units = value.codeUnits;
    u32(units.length);
    for (final unit in units) {
      body.add([unit & 0xff, (unit >> 8) & 0xff]);
    }
  }

  u16(2);
  text(name);
  text(name);
  u16(0);
  u16(3);
  final command = <int>[...name, 0];
  u32(command.length);
  body.add(command);
  u32(data.length);
  body.add(data);
  utf16(fileName);
  utf16(fileName);
  utf16(fileName);
  final payload = body.toBytes();
  return Uint8List.fromList([
    payload.length & 0xff,
    (payload.length >> 8) & 0xff,
    (payload.length >> 16) & 0xff,
    (payload.length >> 24) & 0xff,
    ...payload,
  ]);
}

class _OleStream {
  const _OleStream(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
}

Uint8List _compoundFile(List<_OleStream> streams) {
  const sectorSize = 512;
  const miniSize = 64;
  const cutoff = 4096;
  const endOfChain = 0xFFFFFFFE;
  const fatSector = 0xFFFFFFFD;
  const difatSector = 0xFFFFFFFC;
  const freeSector = 0xFFFFFFFF;

  final miniStarts = List<int>.filled(streams.length, 0);
  final largeStarts = List<int>.filled(streams.length, endOfChain);
  final largeCounts = List<int>.filled(streams.length, 0);
  final miniBuffer = BytesBuilder();
  final miniFat = <int>[];
  var miniCursor = 0;
  for (var index = 0; index < streams.length; index++) {
    final length = streams[index].bytes.length;
    if (length >= cutoff) {
      largeCounts[index] = _sectors(length);
      continue;
    }
    miniStarts[index] = miniCursor;
    final count = length == 0 ? 1 : (length + miniSize - 1) ~/ miniSize;
    final padded = Uint8List(count * miniSize);
    padded.setRange(0, length, streams[index].bytes);
    miniBuffer.add(padded);
    for (var sector = 0; sector < count; sector++) {
      miniFat.add(sector == count - 1 ? endOfChain : miniCursor + sector + 1);
    }
    miniCursor += count;
  }
  final miniBytes = miniBuffer.toBytes();
  final miniStreamSectors = miniBytes.isEmpty ? 0 : _sectors(miniBytes.length);
  final miniFatSectors = miniFat.isEmpty ? 0 : (miniFat.length + 127) ~/ 128;
  final largeSectors = largeCounts.fold<int>(0, (sum, count) => sum + count);

  var fatCount = 1;
  var difatCount = 0;
  while (true) {
    final total = fatCount + difatCount + miniFatSectors + 1 + miniStreamSectors + largeSectors;
    final needFat = (total + 127) ~/ 128;
    final needDifat = needFat <= 109 ? 0 : ((needFat - 109) + 126) ~/ 127;
    if (needFat == fatCount && needDifat == difatCount) break;
    fatCount = needFat;
    difatCount = needDifat;
  }

  final difatStart = fatCount;
  final miniFatStart = fatCount + difatCount;
  final directoryStart = miniFatStart + miniFatSectors;
  final miniStreamStart = directoryStart + 1;
  var largeCursor = miniStreamStart + miniStreamSectors;
  for (var index = 0; index < streams.length; index++) {
    if (largeCounts[index] == 0) continue;
    largeStarts[index] = largeCursor;
    largeCursor += largeCounts[index];
  }
  final totalSectors = largeCursor;

  final fat = List<int>.filled(fatCount * 128, freeSector);
  for (var index = 0; index < fatCount; index++) {
    fat[index] = fatSector;
  }
  for (var index = 0; index < difatCount; index++) {
    fat[difatStart + index] = difatSector;
  }
  for (var index = 0; index < miniFatSectors; index++) {
    fat[miniFatStart + index] = index == miniFatSectors - 1 ? endOfChain : miniFatStart + index + 1;
  }
  fat[directoryStart] = endOfChain;
  for (var index = 0; index < miniStreamSectors; index++) {
    fat[miniStreamStart + index] = index == miniStreamSectors - 1 ? endOfChain : miniStreamStart + index + 1;
  }
  for (var index = 0; index < streams.length; index++) {
    final start = largeStarts[index];
    final count = largeCounts[index];
    for (var sector = 0; sector < count; sector++) {
      fat[start + sector] = sector == count - 1 ? endOfChain : start + sector + 1;
    }
  }

  final bytes = Uint8List(sectorSize * (1 + totalSectors));
  final header = ByteData.sublistView(bytes, 0, sectorSize);
  bytes.setRange(0, 8, const [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]);
  header.setUint16(0x18, 0x003E, Endian.little);
  header.setUint16(0x1A, 0x0003, Endian.little);
  header.setUint16(0x1C, 0xFFFE, Endian.little);
  header.setUint16(0x1E, 9, Endian.little);
  header.setUint16(0x20, 6, Endian.little);
  header.setUint32(0x2C, fatCount, Endian.little);
  header.setUint32(0x30, directoryStart, Endian.little);
  header.setUint32(0x38, cutoff, Endian.little);
  header.setUint32(0x3C, miniFatSectors == 0 ? endOfChain : miniFatStart, Endian.little);
  header.setUint32(0x40, miniFatSectors, Endian.little);
  header.setUint32(0x44, difatCount == 0 ? endOfChain : difatStart, Endian.little);
  header.setUint32(0x48, difatCount, Endian.little);

  final fatLocations = List<int>.generate(fatCount, (index) => index);
  for (var index = 0; index < 109; index++) {
    header.setUint32(0x4C + index * 4, index < fatLocations.length ? fatLocations[index] : freeSector, Endian.little);
  }
  var listed = 109;
  for (var index = 0; index < difatCount; index++) {
    final sector = ByteData.sublistView(bytes, sectorSize * (1 + difatStart + index), sectorSize * (2 + difatStart + index));
    for (var slot = 0; slot < 127; slot++) {
      final value = listed < fatLocations.length ? fatLocations[listed++] : freeSector;
      sector.setUint32(slot * 4, value, Endian.little);
    }
    final next = index == difatCount - 1 ? endOfChain : difatStart + index + 1;
    sector.setUint32(127 * 4, next, Endian.little);
  }

  for (var index = 0; index < miniFatSectors; index++) {
    final sector = ByteData.sublistView(bytes, sectorSize * (1 + miniFatStart + index), sectorSize * (2 + miniFatStart + index));
    for (var slot = 0; slot < 128; slot++) {
      final value = index * 128 + slot;
      sector.setUint32(slot * 4, value < miniFat.length ? miniFat[value] : freeSector, Endian.little);
    }
  }

  final fatBytes = ByteData.sublistView(bytes, sectorSize, sectorSize * (1 + fatCount));
  for (var index = 0; index < fat.length; index++) {
    fatBytes.setUint32(index * 4, fat[index], Endian.little);
  }

  final directory = ByteData.sublistView(
    bytes,
    sectorSize * (1 + directoryStart),
    sectorSize * (2 + directoryStart),
  );
  _writeDirectory(
    directory,
    0,
    'Root Entry',
    5,
    child: 1,
    start: miniStreamSectors == 0 ? endOfChain : miniStreamStart,
    size: miniBytes.length,
    clsid: _packageClsid,
  );
  for (var index = 0; index < streams.length; index++) {
    final small = largeCounts[index] == 0;
    _writeDirectory(
      directory,
      index + 1,
      streams[index].name,
      2,
      left: index == 0 ? 2 : 0xFFFFFFFF,
      right: index == 0 ? 3 : 0xFFFFFFFF,
      start: small ? miniStarts[index] : largeStarts[index],
      size: streams[index].bytes.length,
    );
  }

  if (miniBytes.isNotEmpty) {
    final offset = sectorSize * (1 + miniStreamStart);
    bytes.setRange(offset, offset + miniBytes.length, miniBytes);
  }
  for (var index = 0; index < streams.length; index++) {
    if (largeCounts[index] == 0) continue;
    final offset = sectorSize * (1 + largeStarts[index]);
    bytes.setRange(offset, offset + streams[index].bytes.length, streams[index].bytes);
  }
  return bytes;
}

int _sectors(int length) => (length + 511) ~/ 512;

void _writeDirectory(
  ByteData directory,
  int index,
  String name,
  int type, {
  int left = 0xFFFFFFFF,
  int right = 0xFFFFFFFF,
  int child = 0xFFFFFFFF,
  required int start,
  required int size,
  List<int>? clsid,
}) {
  final entry = ByteData.sublistView(directory, index * 128, (index + 1) * 128);
  if (clsid != null) {
    for (var i = 0; i < clsid.length && i < 16; i++) {
      entry.setUint8(0x50 + i, clsid[i]);
    }
  }
  final units = name.codeUnits;
  for (var i = 0; i < units.length && i < 31; i++) {
    entry.setUint16(i * 2, units[i], Endian.little);
  }
  entry.setUint16(64, (units.length + 1) * 2, Endian.little);
  entry.setUint8(0x42, type);
  entry.setUint8(0x43, 1);
  entry.setUint32(0x44, left, Endian.little);
  entry.setUint32(0x48, right, Endian.little);
  entry.setUint32(0x4C, child, Endian.little);
  entry.setUint32(0x74, start, Endian.little);
  entry.setUint32(0x78, size, Endian.little);
}
