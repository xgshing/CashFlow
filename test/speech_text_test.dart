import 'package:cashflow/speech_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('speech text becomes parser-friendly Chinese amounts', () {
    expect(tidySpeech('午 饭 三 十 五 元'), '午饭35元');
    expect(tidySpeech('买菜十元，打车一百二十三点五元'), '买菜10元，打车123.5元');
    expect(tidySpeech('服务费 两 千 块钱'), '服务费2000块钱');
    expect(tidySpeech('鼠标 89 元'), '鼠标89元');
  });
}
