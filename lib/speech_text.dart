/// Turns streaming recognizer text into a line the ledger parser can read.
String tidySpeech(String raw) {
  final compact = raw.replaceAll(RegExp(r'\s+'), '');
  return compact.replaceAllMapped(
    RegExp('[零〇一二两三四五六七八九十百千万点]+(?=元|块钱|块|圆)'),
    (match) {
      final value = chineseNumber(match.group(0)!);
      if (value == null) return match.group(0)!;
      if (value == value.roundToDouble()) return value.round().toString();
      return value.toString();
    },
  );
}

double? chineseNumber(String text) {
  const digits = {
    '零': 0,
    '〇': 0,
    '一': 1,
    '二': 2,
    '两': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
  };
  const smallUnits = {'十': 10, '百': 100, '千': 1000};
  var total = 0;
  var section = 0;
  var number = 0;
  var decimal = '';
  var inDecimal = false;
  for (final char in text.split('')) {
    if (char == '点') {
      if (inDecimal) return null;
      inDecimal = true;
      continue;
    }
    if (inDecimal) {
      final digit = digits[char];
      if (digit == null) return null;
      decimal += '$digit';
      continue;
    }
    final digit = digits[char];
    if (digit != null) {
      number = digit;
      continue;
    }
    final unit = smallUnits[char];
    if (unit != null) {
      if (number == 0) number = 1;
      section += number * unit;
      number = 0;
      continue;
    }
    if (char == '万') {
      total += (section + number) * 10000;
      section = 0;
      number = 0;
      continue;
    }
    return null;
  }
  final whole = total + section + number;
  if (decimal.isEmpty) return whole.toDouble();
  return double.tryParse('$whole.$decimal');
}
