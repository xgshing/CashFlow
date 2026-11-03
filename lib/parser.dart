import 'format.dart';
import 'models.dart';

class LedgerParser {
  static List<DraftEntry> parse(String raw, {DateTime? now, int idStart = 1}) {
    final today = _dateOnly(now ?? DateTime.now());
    var text = _normalize(raw).trim();
    if (text.isEmpty) return const [];

    DateTime? labeledDate;
    final labeled = RegExp(
      r'日期\s*[:：]?\s*(\d{4}[-/.年]\d{1,2}[-/.月]\d{1,2}日?)',
    );
    final labeledMatch = labeled.firstMatch(text);
    if (labeledMatch != null) {
      labeledDate = _absoluteDate(labeledMatch.group(1)!, today);
      text = text.replaceAll(labeled, ' ');
    }

    while (RegExp(r'\d,\d{3}').hasMatch(text)) {
      text = text.replaceAllMapped(
        RegExp(r'(\d),(\d{3})'),
        (match) => '${match.group(1)}${match.group(2)}',
      );
    }

    final dateToken = RegExp(
      r'\d{4}[-/.年]\d{1,2}[-/.月]\d{1,2}日?|\d{1,2}月\d{1,2}日',
    );
    final masked = text.replaceAllMapped(
      dateToken,
      (match) => ' ' * match.group(0)!.length,
    );
    final amountPattern = RegExp(
      r'(?:¥|￥)\s*(\d+(?:\.\d{1,2})?)|(\d+(?:\.\d{1,2})?)\s*(万|千)?\s*(?:元|块钱|块|圆)',
    );
    final matches = amountPattern.allMatches(masked).toList();
    if (matches.isEmpty) return const [];

    final drafts = <DraftEntry>[];
    for (var i = 0; i < matches.length; i++) {
      final match = matches[i];
      final amount = _amountOf(match);
      if (amount == null || amount <= 0) continue;
      final start = i == 0 ? 0 : matches[i - 1].end;
      final span = text.substring(start, match.start);
      var content = _contentOf(span, dateToken);
      if (content.isEmpty) {
        final next = i + 1 < matches.length ? matches[i + 1].start : text.length;
        final after = text.substring(match.end, next).split(RegExp(r'[。！？\n,，;；]')).first;
        content = _contentOf(after, dateToken);
      }
      if (content.isEmpty) content = '未命名记账';
      final direction = _directionOf('$span $content');
      drafts.add(
        DraftEntry(
          localId: idStart + drafts.length,
          direction: direction,
          content: content,
          amount: roundMoney(amount),
          date: formatDay(
            _absoluteDate(span, today) ??
                labeledDate ??
                _relativeDate(span, today) ??
                _relativeDate(text, today) ??
                today,
          ),
          category: _categoryOf(content, span, direction),
          origin: DraftOrigin.parsed,
        ),
      );
    }
    return drafts;
  }

  static String _normalize(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune >= 0xFF10 && rune <= 0xFF19) {
        buffer.writeCharCode(rune - 0xFF10 + 0x30);
      } else if (rune == 0xFF0E) {
        buffer.write('.');
      } else if (rune == 0xFFE5) {
        buffer.write('¥');
      } else if (rune == 0x3000) {
        buffer.write(' ');
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  static double? _amountOf(RegExpMatch match) {
    final currency = match.group(1);
    if (currency != null) return double.tryParse(currency);
    final number = double.tryParse(match.group(2)!);
    if (number == null) return null;
    return switch (match.group(3)) {
      '万' => number * 10000,
      '千' => number * 1000,
      _ => number,
    };
  }

  static String _contentOf(String span, RegExp dateToken) {
    final lines = span
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    var text = lines.isEmpty ? '' : lines.last;
    final colon = RegExp(r'[:：]').allMatches(text);
    if (colon.isNotEmpty) {
      final after = text.substring(colon.last.end).trim();
      if (after.isNotEmpty) text = after;
    }
    text = text.replaceFirst(RegExp(r'^\d+[\.、\)\]]\s*'), '');
    text = text.replaceAll(dateToken, ' ');
    const fillers = [
      '购买了一个',
      '购买了个',
      '买了一个',
      '买了个',
      '购买了',
      '支付了',
      '消费了',
      '另外',
      '以及',
      '还有',
      '然后',
      '并且',
      '共计',
      '合计',
      '总共',
      '一共',
      '人民币',
      '今天',
      '今日',
      '昨天',
      '昨日',
      '前天',
      '购买',
      '买了',
      '支付',
      '花费',
      '花了',
      '消费',
    ];
    for (final word in fillers) {
      text = text.replaceAll(word, ' ');
    }
    text = text.replaceAll(RegExp(r'[。！？!,，;；、]+'), ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    text = text.replaceFirst(RegExp(r'^(一个|一件|一支|一盒|一份|一包|一袋|的|和|与)+'), '');
    return text.trim();
  }

  static MoneyDirection _directionOf(String text) {
    const strongIncome = ['收入', '入账', '到账', '收款', '工资', '薪资', '奖金', '红包', '退款', '回款'];
    const strongExpense = ['支出', '购买', '支付', '花费', '缴费', '消费', '房租', '水电', '水费', '电费'];
    const weakIncome = ['服务费', '项目款', '报酬', '劳务'];
    bool has(List<String> words) => words.any(text.contains);
    if (has(strongIncome)) return MoneyDirection.income;
    if (has(strongExpense)) return MoneyDirection.expense;
    if (has(weakIncome)) return MoneyDirection.income;
    return MoneyDirection.expense;
  }

  static String _categoryOf(String content, String span, MoneyDirection direction) {
    final explicit = RegExp(r'类别\s*[:：]\s*([^\s,，。;；]+)').firstMatch('$content $span');
    if (explicit != null) return explicit.group(1)!;
    return _matchCategory(content, direction) ?? _matchCategory(span, direction) ?? '';
  }

  static String? _matchCategory(String text, MoneyDirection direction) {
    if (text.isEmpty) return null;
    String? found;
    var length = 0;
    for (final rule in _categoryRules) {
      if (direction == MoneyDirection.expense && (rule.$1 == '工资' || rule.$1 == '项目收入')) {
        continue;
      }
      for (final keyword in rule.$2) {
        if (text.contains(keyword) && keyword.length > length) {
          found = rule.$1;
          length = keyword.length;
        }
      }
    }
    return found;
  }

  static DateTime? _absoluteDate(String text, DateTime today) {
    final full = RegExp(r'(\d{4})[-/.年](\d{1,2})[-/.月](\d{1,2})').firstMatch(text);
    if (full != null) {
      return _safeDate(
        int.parse(full.group(1)!),
        int.parse(full.group(2)!),
        int.parse(full.group(3)!),
      );
    }
    final monthDay = RegExp(r'(\d{1,2})月(\d{1,2})日').firstMatch(text);
    if (monthDay != null) {
      return _safeDate(today.year, int.parse(monthDay.group(1)!), int.parse(monthDay.group(2)!));
    }
    return null;
  }

  static DateTime? _relativeDate(String text, DateTime today) {
    if (text.contains('前天')) return today.subtract(const Duration(days: 2));
    if (text.contains('昨天') || text.contains('昨日')) {
      return today.subtract(const Duration(days: 1));
    }
    if (text.contains('今天') || text.contains('今日')) return today;
    return null;
  }

  static DateTime? _safeDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) return null;
    return date;
  }

  static DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);
}

const _categoryRules = <(String, List<String>)>[
  ('办公用品', ['打印纸', '墨盒', '文件夹', '文具', '办公用品', '办公']),
  ('生活用品', ['生活用品', '日用品', '纸巾', '洗衣液']),
  ('餐饮', ['早餐', '午餐', '晚餐', '餐饮', '外卖', '咖啡', '奶茶', '吃饭', '宵夜']),
  ('交通', ['交通费', '交通', '地铁', '公交', '打车', '滴滴', '加油', '油费', '高铁', '机票', '停车']),
  ('住房', ['房租', '水电费', '水电', '水费', '电费', '燃气', '物业', '住房']),
  ('医疗', ['医院', '挂号', '药品', '医药', '医疗']),
  ('设备采购', ['设备采购', '设备', '鼠标', '键盘', '电脑', '显示器']),
  ('工资', ['工资', '薪资', '奖金']),
  ('项目收入', ['项目服务费', '项目收入', '服务费', '项目款', '回款']),
  ('购物', ['购物', '淘宝', '京东']),
  ('娱乐', ['电影', '娱乐', '游戏']),
];
