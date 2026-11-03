import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'device_bridge.dart';
import 'models.dart';
import 'widgets.dart';

class ExcelActions {
  static Future<void> share(BuildContext context, CashProject project) async {
    final path = await _readyPath(context, project.id);
    if (path == null || !context.mounted) return;
    final name = path.replaceAll('\\', '/').split('/').last;
    try {
      await DeviceBridge.shareToWeChat(path, name);
    } on PlatformException catch (error) {
      if (!context.mounted) return;
      showMessage(context, error.code == 'no_wechat' ? '请先安装微信' : '分享失败：${error.message}');
    } catch (error) {
      if (context.mounted) showMessage(context, '分享失败：$error');
    }
  }

  static Future<String?> _readyPath(BuildContext context, String projectId) async {
    final store = LedgerScope.of(context);
    final project = store.projectById(projectId);
    if (project == null) {
      showMessage(context, '记账项目不存在');
      return null;
    }
    final written = await store.ensureExcel(projectId);
    if (!context.mounted) return null;
    if (!written) {
      showMessage(context, 'Excel 写入失败，请重试');
      return null;
    }
    return store.projectById(projectId)?.filePath;
  }
}
