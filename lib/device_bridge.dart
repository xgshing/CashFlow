import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Phone-only helpers. Tests run on the computer, where these calls are skipped.
class DeviceBridge {
  static const _channel = MethodChannel('cashflow/device');

  static Future<void> shareToWeChat(String path, String fileName) {
    return _channel.invokeMethod<void>('shareToWeChat', {
      'path': path,
      'name': fileName,
    });
  }

  static Future<Uint8List?> fileIcon(String label) async {
    if (!Platform.isAndroid) return null;
    try {
      final result = await _channel.invokeMethod<Uint8List>('fileIcon', {'label': label});
      if (result == null || result.isEmpty) return null;
      return result;
    } catch (_) {
      return null;
    }
  }
}
