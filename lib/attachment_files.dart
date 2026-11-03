import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'models.dart';

const attachmentByteLimit = 30 * 1024 * 1024;

const _allowedExtensions = {
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.gif',
  '.heic',
  '.heif',
  '.pdf',
};

class AttachmentFiles {
  static String encode(List<LedgerAttachment> items) {
    return jsonEncode([
      for (final item in items) {'name': item.name, 'path': item.relativePath},
    ]);
  }

  static List<LedgerAttachment> decode(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map && item['name'] is String && item['path'] is String)
            LedgerAttachment(name: item['name'] as String, relativePath: item['path'] as String),
      ];
    } catch (_) {
      return const [];
    }
  }

  static File resolve(Directory root, LedgerAttachment attachment) {
    return File(p.join(root.path, attachment.relativePath));
  }

  static LedgerAttachment importFile(
    Directory root,
    String sourcePath, {
    required String displayName,
  }) {
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw LedgerException('读不到所选文件');
    }
    final size = source.lengthSync();
    if (size > attachmentByteLimit) {
      throw LedgerException('单个附件不能超过 30MB');
    }
    final extension = _extensionOf(sourcePath, displayName);
    final relativePath = '${const Uuid().v4()}$extension';
    final destination = File(p.join(root.path, relativePath));
    destination.parent.createSync(recursive: true);
    source.copySync(destination.path);
    return LedgerAttachment(name: _safeName(displayName, extension), relativePath: relativePath);
  }

  static void delete(Directory root, LedgerAttachment attachment) {
    final file = resolve(root, attachment);
    if (file.existsSync()) file.deleteSync();
  }

  static void deleteAll(Directory root, List<LedgerAttachment> attachments) {
    for (final attachment in attachments) {
      delete(root, attachment);
    }
  }

  static void deleteRemoved(
    Directory root,
    List<LedgerAttachment> before,
    List<LedgerAttachment> after,
  ) {
    final kept = after.map((item) => item.relativePath).toSet();
    for (final attachment in before) {
      if (!kept.contains(attachment.relativePath)) delete(root, attachment);
    }
  }

  static String _extensionOf(String sourcePath, String displayName) {
    var extension = p.extension(sourcePath).toLowerCase();
    if (!_allowedExtensions.contains(extension)) {
      extension = p.extension(displayName).toLowerCase();
    }
    if (!_allowedExtensions.contains(extension)) {
      throw LedgerException('只能添加图片或 PDF');
    }
    return extension;
  }

  static String _safeName(String displayName, String extension) {
    final name = p.basename(displayName).trim();
    if (name.isEmpty) return '附件$extension';
    return name;
  }
}
