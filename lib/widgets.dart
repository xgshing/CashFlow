import 'package:flutter/material.dart';

import 'format.dart';
import 'models.dart';
import 'theme.dart';

void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Future<String?> pickLedgerDate(BuildContext context, String current) {
  final initial = DateTime.tryParse(current) ?? DateTime.now();
  return showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  ).then((picked) => picked == null ? null : formatDay(picked));
}

class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: AppColors.sub, fontSize: 14)),
        ],
      ),
    );
  }
}

class WhiteCard extends StatelessWidget {
  const WhiteCard({super.key, required this.child, this.onTap, this.padding});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding ?? const EdgeInsets.all(16),
      child: child,
    );
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFEEF2F7)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x141677E8),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: content,
        ),
      ),
    );
  }
}

class DirectionTag extends StatelessWidget {
  const DirectionTag({super.key, required this.direction});

  final MoneyDirection direction;

  @override
  Widget build(BuildContext context) {
    final income = direction == MoneyDirection.income;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: income ? AppColors.incomeSoft : AppColors.expenseSoft,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        direction.label,
        style: TextStyle(
          color: income ? AppColors.income : AppColors.expense,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class AmountText extends StatelessWidget {
  const AmountText({
    super.key,
    required this.amount,
    required this.direction,
    this.size = 20,
  });

  final double amount;
  final MoneyDirection? direction;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = switch (direction) {
      MoneyDirection.income => AppColors.income,
      MoneyDirection.expense => AppColors.expense,
      null => amount < 0 ? AppColors.expense : AppColors.income,
    };
    return Text(
      formatMoney(amount),
      style: TextStyle(
        color: color,
        fontSize: size,
        fontWeight: FontWeight.w800,
        height: 1.1,
      ),
    );
  }
}

class SummaryTrio extends StatelessWidget {
  const SummaryTrio({
    super.key,
    required this.income,
    required this.expense,
    required this.balance,
  });

  final double income;
  final double expense;
  final double balance;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _cell('收入', income, AppColors.income)),
        Expanded(child: _cell('支出', expense, AppColors.expense)),
        Expanded(child: _cell('结余', balance, balance < 0 ? AppColors.expense : AppColors.income)),
      ],
    );
  }

  Widget _cell(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.sub, fontSize: 12)),
        const SizedBox(height: 2),
        Text(
          formatMoney(value),
          style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ],
    );
  }
}

class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 42, color: const Color(0xFFB8C4D6)),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.sub, height: 1.5)),
        ],
      ),
    );
  }
}

class CategoryChips extends StatelessWidget {
  const CategoryChips({super.key, required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final category in categorySuggestions)
          ActionChip(
            label: Text(category),
            visualDensity: VisualDensity.compact,
            backgroundColor: AppColors.primarySoft,
            side: BorderSide.none,
            labelStyle: const TextStyle(color: AppColors.primary, fontSize: 12),
            onPressed: () => onSelected(category),
          ),
      ],
    );
  }
}

class DirectionSwitch extends StatelessWidget {
  const DirectionSwitch({super.key, required this.value, required this.onChanged});

  final MoneyDirection value;
  final ValueChanged<MoneyDirection> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _button(MoneyDirection.expense),
        const SizedBox(width: 8),
        _button(MoneyDirection.income),
      ],
    );
  }

  Widget _button(MoneyDirection direction) {
    final selected = value == direction;
    final color = direction == MoneyDirection.income ? AppColors.income : AppColors.expense;
    return Expanded(
      child: Material(
        color: selected ? color : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onChanged(direction),
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? color : AppColors.line),
            ),
            child: Text(
              direction.label,
              style: TextStyle(
                color: selected ? Colors.white : color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
