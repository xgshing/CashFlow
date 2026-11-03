import 'package:cashflow/models.dart';
import 'package:cashflow/parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 10, 30);

  test('splits one paste into income and expense rows', () {
    final drafts = LedgerParser.parse(
      '''
今天购买办公用品：
1. 打印纸 268元
2. 文件夹 45元
另外，项目服务费 5000元。
日期：2026-10-30
''',
      now: today,
    );

    expect(drafts, hasLength(3));
    expect(drafts[0].content, '打印纸');
    expect(drafts[0].amount, 268);
    expect(drafts[0].direction, MoneyDirection.expense);
    expect(drafts[0].category, '办公用品');
    expect(drafts[0].date, '2026-10-30');

    expect(drafts[1].content, '文件夹');
    expect(drafts[1].amount, 45);
    expect(drafts[1].direction, MoneyDirection.expense);
    expect(drafts[1].category, '办公用品');

    expect(drafts[2].content, '项目服务费');
    expect(drafts[2].amount, 5000);
    expect(drafts[2].direction, MoneyDirection.income);
    expect(drafts[2].category, '项目收入');
    expect(drafts[2].date, '2026-10-30');
  });

  test('splits a spoken sentence into two purchases', () {
    final drafts = LedgerParser.parse('今天买了一个鼠标，89元，购买了一个键盘，199元。', now: today);
    expect(drafts.map((draft) => draft.content), ['鼠标', '键盘']);
    expect(drafts.map((draft) => draft.amount), [89, 199]);
    expect(drafts.every((draft) => draft.direction == MoneyDirection.expense), isTrue);
    expect(drafts.every((draft) => draft.category == '设备采购'), isTrue);
    expect(drafts.every((draft) => draft.date == '2026-10-30'), isTrue);
  });

  test('understands relative dates, wages, and large amounts', () {
    final lunch = LedgerParser.parse('昨天午餐35元', now: today).single;
    expect(lunch.date, '2026-10-29');
    expect(lunch.content, '午餐');
    expect(lunch.category, '餐饮');
    expect(lunch.direction, MoneyDirection.expense);

    final wage = LedgerParser.parse('工资 8,000元', now: today).single;
    expect(wage.direction, MoneyDirection.income);
    expect(wage.amount, 8000);
    expect(wage.category, '工资');

    final bonus = LedgerParser.parse('奖金1.2万元', now: today).single;
    expect(bonus.amount, 12000);
    expect(bonus.direction, MoneyDirection.income);

    final paid = LedgerParser.parse('支付服务费 300元', now: today).single;
    expect(paid.direction, MoneyDirection.expense);
    expect(paid.content, '服务费');
    expect(paid.category, isEmpty);
  });

  test('reads currency symbols and fullwidth digits', () {
    final drafts = LedgerParser.parse('咖啡￥18，打印纸２６８元', now: today);
    expect(drafts.map((draft) => draft.amount), [18, 268]);
  });

  test('returns nothing when no amount is present', () {
    expect(LedgerParser.parse('今天只是记一笔备忘', now: today), isEmpty);
    expect(LedgerParser.parse('1. 打印纸', now: today), isEmpty);
    expect(LedgerParser.parse('   ', now: today), isEmpty);
  });
}
