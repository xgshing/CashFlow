import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'tencent_secret.dart';

class TencentSpeechException implements Exception {
  const TencentSpeechException(this.message, {this.detail = ''});

  final String message;
  final String detail;
}

Future<String> recognizeSentence(List<int> pcmBytes) {
  return recognizeSentenceWith(
    pcmBytes,
    secretId: TencentSecret.secretId,
    secretKey: TencentSecret.secretKey,
  );
}

Future<String> recognizeSentenceWith(
  List<int> pcmBytes, {
  required String secretId,
  required String secretKey,
}) async {
  final payload = jsonEncode({
    'EngSerViceType': '16k_zh',
    'SourceType': 1,
    'VoiceFormat': 'pcm',
    'Data': base64Encode(pcmBytes),
    'DataLen': pcmBytes.length,
    'ConvertNumMode': 1,
  });
  final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final authorization = tencentAuthorization(
    secretId: secretId,
    secretKey: secretKey,
    service: 'asr',
    host: 'asr.tencentcloudapi.com',
    payload: payload,
    timestamp: timestamp,
  );
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.https('asr.tencentcloudapi.com', '/'));
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
    request.headers.set('Host', 'asr.tencentcloudapi.com');
    request.headers.set('X-TC-Action', 'SentenceRecognition');
    request.headers.set('X-TC-Version', '2019-06-14');
    request.headers.set('X-TC-Timestamp', '$timestamp');
    request.headers.set('X-TC-Region', 'ap-guangzhou');
    request.headers.set(HttpHeaders.authorizationHeader, authorization);
    request.add(utf8.encode(payload));
    final response = await request.close().timeout(const Duration(seconds: 20));
    final body = await response.transform(utf8.decoder).join();
    return _resultOf(body);
  } on TencentSpeechException {
    rethrow;
  } on SocketException {
    throw const TencentSpeechException('语音识别需要联网，请检查网络后再按住说。');
  } on HttpException {
    throw const TencentSpeechException('语音识别需要联网，请检查网络后再按住说。');
  } finally {
    client.close(force: true);
  }
}

String tencentAuthorization({
  required String secretId,
  required String secretKey,
  required String service,
  required String host,
  required String payload,
  required int timestamp,
}) {
  final day = _utcDay(timestamp);
  final hashedPayload = sha256.convert(utf8.encode(payload)).toString();
  final canonicalHeaders = 'content-type:application/json; charset=utf-8\nhost:$host\n';
  const signedHeaders = 'content-type;host';
  final canonicalRequest = 'POST\n/\n\n$canonicalHeaders\n$signedHeaders\n$hashedPayload';
  final scope = '$day/$service/tc3_request';
  final stringToSign = 'TC3-HMAC-SHA256\n$timestamp\n$scope\n${sha256.convert(utf8.encode(canonicalRequest))}';
  final secretDate = _hmac(utf8.encode('TC3$secretKey'), day);
  final secretService = _hmac(secretDate, service);
  final secretSigning = _hmac(secretService, 'tc3_request');
  final signature = _hmac(secretSigning, stringToSign);
  final hexSignature = signature.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return 'TC3-HMAC-SHA256 Credential=$secretId/$scope, SignedHeaders=$signedHeaders, Signature=$hexSignature';
}

List<int> _hmac(List<int> key, String message) {
  return Hmac(sha256, key).convert(utf8.encode(message)).bytes;
}

String _utcDay(int timestamp) {
  final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true);
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String _resultOf(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map) {
    throw const TencentSpeechException('腾讯云没有返回识别结果，请再按住说一次。');
  }
  final response = decoded['Response'];
  if (response is! Map) {
    throw const TencentSpeechException('腾讯云没有返回识别结果，请再按住说一次。');
  }
  final error = response['Error'];
  if (error is Map) {
    final code = '${error['Code'] ?? ''}';
    final message = '${error['Message'] ?? ''}';
    throw TencentSpeechException(_errorMessage(code, message), detail: '$code $message');
  }
  return '${response['Result'] ?? ''}'.trim();
}

String _errorMessage(String code, String message) {
  if (code.contains('SecretIdNotFound') || code.contains('SignatureFailure')) {
    return '腾讯云密钥校验失败，请核对密钥后重试。';
  }
  if (code.contains('UnauthorizedOperation') || code.contains('ResourceUnavailable') || message.contains('未开通') || message.contains('not authorized')) {
    return '请先在腾讯云开通「一句话识别」，并确认这个密钥有语音识别权限。';
  }
  if (code.contains('LimitExceeded') || message.contains('额度')) {
    return '腾讯云本月免费识别次数已用完。';
  }
  if (code.contains('Timeout') || message.contains('network')) {
    return '语音识别需要联网，请检查网络后再按住说。';
  }
  return '没有听清，请按住重说。';
}
