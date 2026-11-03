import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import 'attachment_files.dart';
import 'models.dart';
import 'theme.dart';
import 'widgets.dart';

class AttachmentField extends StatelessWidget {
  const AttachmentField({
    super.key,
    required this.attachments,
    required this.root,
    required this.onChanged,
  });

  final List<LedgerAttachment> attachments;
  final Directory root;
  final ValueChanged<List<LedgerAttachment>> onChanged;

  Future<void> _pick(BuildContext context, {required bool images}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: images ? FileType.image : FileType.custom,
        allowedExtensions: images ? null : const ['pdf'],
      );
      if (result == null) return;
      final imported = <LedgerAttachment>[];
      for (final file in result.files) {
        final path = file.path;
        if (path == null) {
          throw LedgerException('读不到「${file.name}」');
        }
        imported.add(AttachmentFiles.importFile(root, path, displayName: file.name));
      }
      if (imported.isEmpty) return;
      onChanged([...attachments, ...imported]);
    } on LedgerException catch (error) {
      if (context.mounted) showMessage(context, error.message);
    } catch (_) {
      if (context.mounted) showMessage(context, '没有选到文件，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('附件', style: TextStyle(color: AppColors.sub, fontSize: 13)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pick(context, images: true),
                icon: const Icon(Icons.image_outlined, size: 18),
                label: const Text('添加图片'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pick(context, images: false),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('添加 PDF'),
              ),
            ),
          ],
        ),
        if (attachments.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('可添加发票、收据等图片或 PDF，每个不超过 30MB', style: TextStyle(color: AppColors.sub, fontSize: 12)),
          )
        else
          ...attachments.map(
            (attachment) => _AttachmentTile(
              attachment: attachment,
              root: root,
              onDelete: () {
                onChanged([
                  for (final item in attachments)
                    if (item.relativePath != attachment.relativePath) item,
                ]);
              },
            ),
          ),
      ],
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.attachment,
    required this.root,
    required this.onDelete,
  });

  final LedgerAttachment attachment;
  final Directory root;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final file = AttachmentFiles.resolve(root, attachment);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => openAttachment(context, root, attachment),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
            child: Row(
              children: [
                _Thumbnail(attachment: attachment, file: file),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    attachment.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: '移除附件',
                  onPressed: onDelete,
                  icon: const Icon(Icons.close_rounded, color: AppColors.sub),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.attachment, required this.file});

  final LedgerAttachment attachment;
  final File file;

  @override
  Widget build(BuildContext context) {
    if (!attachment.canPreview || !file.existsSync()) {
      return Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
        child: Icon(
          attachment.isPdf ? Icons.picture_as_pdf_outlined : Icons.insert_drive_file_outlined,
          color: AppColors.primary,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(
        file,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: 48,
          height: 48,
          color: Colors.white,
          child: const Icon(Icons.image_outlined, color: AppColors.primary),
        ),
      ),
    );
  }
}

Future<void> openAttachment(BuildContext context, Directory root, LedgerAttachment attachment) async {
  final file = AttachmentFiles.resolve(root, attachment);
  if (!file.existsSync()) {
    showMessage(context, '这个附件文件不在了');
    return;
  }
  if (attachment.canPreview) {
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            SizedBox(
              height: 360,
              width: double.infinity,
              child: InteractiveViewer(
                child: Image.file(file, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    return;
  }
  final result = await OpenFilex.open(file.path, type: attachment.isPdf ? 'application/pdf' : null);
  if (result.type != ResultType.done && context.mounted) {
    showMessage(context, '没有可以打开这个文件的应用');
  }
}
