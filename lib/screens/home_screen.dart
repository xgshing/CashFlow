import 'package:flutter/material.dart';

import '../app.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'edit_entry_screen.dart';
import 'project_flow.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = LedgerScope.of(context);
    final latest = store.latestEntry;
    final projects = store.snapshots;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const PageHeader(title: '记账', subtitle: '记录每一笔，让生活更清晰'),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: WhiteCard(
            onTap: latest == null
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => EditEntryScreen(entryId: latest.id)),
                    );
                  },
            child: latest == null
                ? const Row(
                    children: [
                      _RecentIcon(),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('最近记账', style: TextStyle(color: AppColors.sub, fontSize: 13)),
                            SizedBox(height: 4),
                            Text('还没有记账', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                            Text('点下方按钮记第一笔', style: TextStyle(color: AppColors.sub)),
                          ],
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      const _RecentIcon(),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('最近记账', style: TextStyle(color: AppColors.sub, fontSize: 13)),
                            const SizedBox(height: 4),
                            Text(
                              latest.category.isEmpty ? latest.content : '${latest.content} · ${latest.category}',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.text),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${latest.date} · ${store.projectNameOf(latest.projectId) ?? ''}',
                              style: const TextStyle(color: AppColors.sub, fontSize: 13),
                            ),
                            if (latest.attachments.isNotEmpty)
                              Text(
                                '附件 ${latest.attachments.length} 个',
                                style: const TextStyle(color: AppColors.primary, fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      AmountText(amount: latest.amount, direction: latest.direction, size: 18),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FilledButton.icon(
            key: const Key('add-entry-button'),
            onPressed: () => startNewEntry(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('新增记账内容'),
          ),
        ),
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '我的记账项目',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text),
                ),
              ),
              Text(
                projects.isEmpty ? '还没有项目' : '共 ${projects.length} 个项目',
                style: const TextStyle(color: AppColors.sub, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (projects.isEmpty)
          const EmptyHint(icon: Icons.folder_open_rounded, text: '还没有记账项目\n点上方按钮新建并开始记账')
        else
          for (final snapshot in projects)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _ProjectSummaryCard(snapshot: snapshot),
            ),
      ],
    );
  }
}

class _RecentIcon extends StatelessWidget {
  const _RecentIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.receipt_long_rounded, color: AppColors.primary),
    );
  }
}

class _ProjectSummaryCard extends StatelessWidget {
  const _ProjectSummaryCard({required this.snapshot});

  final ProjectSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final latest = snapshot.latest;
    return WhiteCard(
      onTap: () => openRecords(context, snapshot.project.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.folder_rounded, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  snapshot.project.name,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('结余', style: TextStyle(color: AppColors.sub, fontSize: 12)),
                  AmountText(amount: snapshot.balance, direction: null, size: 18),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '收入 ${formatMoney(snapshot.income, symbol: false)}    支出 ${formatMoney(snapshot.expense, symbol: false)}',
            style: const TextStyle(color: AppColors.sub, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            latest == null
                ? '还没有记账'
                : '最近：${latest.content}  ${latest.date}  ${formatMoney(latest.amount)}${latest.attachments.isEmpty ? '' : '  附件'}',
            style: const TextStyle(color: AppColors.text, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
