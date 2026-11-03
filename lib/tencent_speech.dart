import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'speech_text.dart';
import 'tencent_asr.dart';

/// Records while the finger is down, then sends the audio to Tencent.
///
/// Constructing this class does not open the microphone.
class TencentSpeech {
  AudioRecorder? _recorder;
  String? _path;
  bool _open = false;
  String? lastError;
  void Function(String text)? _onText;

  AudioRecorder get _audio => _recorder ??= AudioRecorder();

  /// `ok` means audio is being recorded. `granted` means the permission dialog
  /// just closed and this gesture must not start recording.
  Future<String> begin({
    required bool Function() stillHolding,
    required void Function(String text) onText,
  }) async {
    lastError = null;
    _onText = onText;
    if (!Platform.isAndroid && !Platform.isIOS) return 'failed';
    final alreadyAllowed = await _audio.hasPermission(request: false);
    if (!alreadyAllowed) {
      final allowed = await _audio.hasPermission();
      return allowed ? 'granted' : 'denied';
    }
    if (!stillHolding()) return 'idle';
    final dir = await getTemporaryDirectory();
    final path = p.join(dir.path, 'speech-${DateTime.now().microsecondsSinceEpoch}.pcm');
    try {
      await _audio.start(
        const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1),
        path: path,
      );
    } catch (_) {
      lastError = '麦克风没有打开，请检查系统权限后重试。';
      return 'failed';
    }
    if (!stillHolding()) {
      await _stopAndDelete(path);
      return 'idle';
    }
    _path = path;
    _open = true;
    return 'ok';
  }

  Future<String> finish() async {
    if (!_open) return '';
    _open = false;
    final path = _path;
    _path = null;
    String? stopped;
    try {
      stopped = await _audio.stop();
    } catch (_) {}
    final file = File(stopped ?? path ?? '');
    if (!await file.exists()) {
      lastError = '没有听清，请按住重说。';
      return '';
    }
    final bytes = await file.readAsBytes();
    try {
      await file.delete();
    } catch (_) {}
    if (bytes.length < 3200) {
      lastError = '没有听清，请按住重说。';
      return '';
    }
    if (bytes.length > 3 * 1024 * 1024) {
      lastError = '这句话太长了，请分成几句来说。';
      return '';
    }
    try {
      final text = tidySpeech(await recognizeSentence(bytes));
      if (text.isEmpty) {
        lastError = '没有听清，请按住重说。';
      } else {
        _onText?.call(text);
      }
      return text;
    } on TencentSpeechException catch (error) {
      lastError = error.message;
      return '';
    } catch (_) {
      lastError = '语音识别需要联网，请检查网络后再按住说。';
      return '';
    }
  }

  Future<void> cancel() async {
    lastError = null;
    _open = false;
    final path = _path;
    _path = null;
    await _stopAndDelete(path);
  }

  Future<void> close() => cancel();

  Future<void> _stopAndDelete(String? path) async {
    final recorder = _recorder;
    if (recorder != null) {
      try {
        if (await recorder.isRecording()) await recorder.stop();
      } catch (_) {}
    }
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }
}
