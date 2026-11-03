import 'package:flutter/material.dart';

import '../app.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'compose_screen.dart';
import 'edit_entry_screen.dart';

class RecordsScreen extends StatelessWidget {
  const RecordsScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final store = LedgerScope.of(context);
    final snapshot = store.snapshotById(projectId);
    if (snapshot == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('项目不存在')));
    }
    return Scaffold(
      appBar: AppBar(title: Text(snapshot.project.name)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ComposeScreen(projectId: projectId)),
          );
        },
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.mic_rounded),
        label: const Text('记一笔'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          WhiteCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: SummaryTrio(
              income: snapshot.income,
              expense: snapshot.expense,
              balance: snapshot.balance,
            ),
          ),
          const SizedBox(height: 12),
          if (snapshot.entries.isEmpty)
            const EmptyHint(icon: Icons.receipt_long_outlined, text: '这个项目还没有记账')
          else
            for (final entry in snapshot.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: WhiteCard(
                  padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 42,
                        decoration: BoxDecoration(
                          color: entry.direction == MoneyDirection.income ? AppColors.income : AppColors.expense,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.content, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                            const SizedBox(height: 2),
                            Text(
                              '${entry.date}${entry.category.isEmpty ? '' : ' · ${entry.category}'}',
                              style: const TextStyle(color: AppColors.sub, fontSize: 13),
                            ),
                            if (entry.attachments.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                '附件 ${entry.attachments.map((item) => item.name).join('、')}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: AppColors.primary, fontSize: 12),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Text(
                        formatMoney(entry.amount),
                        style: TextStyle(
                          color: entry.direction == MoneyDirection.income ? AppColors.income : AppColors.expense,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      IconButton(
                        tooltip: '修改',
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => EditEntryScreen(entryId: entry.id)),
                          );
                        },
                        icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
                      ),
                      IconButton(
                        tooltip: '删除',
                        onPressed: () => _delete(context, entry),
                        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.expense),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, LedgerEntry entry) async {
    final store = LedgerScope.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这笔账'),
        content: Text('确认删除「${entry.content}」？Excel 合计会一起更新。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.expense),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await store.deleteEntry(entry.id);
  }
}
