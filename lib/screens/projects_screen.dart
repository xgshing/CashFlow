import 'package:flutter/material.dart';

import '../app.dart';
import '../excel_actions.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'project_flow.dart';
import 'project_name_dialog.dart';

class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = LedgerScope.of(context);
    final projects = store.snapshots;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const PageHeader(title: '项目', subtitle: '新建、重命名、删除、选择项目，或分享到微信'),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FilledButton.icon(
            onPressed: () => createProjectFlow(context, store),
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('新建项目'),
          ),
        ),
        const SizedBox(height: 16),
        if (projects.isEmpty)
          const EmptyHint(icon: Icons.folder_open_rounded, text: '还没有记账项目')
        else
          for (final snapshot in projects)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: WhiteCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      snapshot.project.name,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    SummaryTrio(
                      income: snapshot.income,
                      expense: snapshot.expense,
                      balance: snapshot.balance,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      snapshot.latest == null
                          ? '还没有记账'
                          : '最近：${snapshot.latest!.content} · ${snapshot.latest!.date} · ${formatMoney(snapshot.latest!.amount)}',
                      style: const TextStyle(color: AppColors.sub, fontSize: 13),
                    ),
                    const Divider(height: 20),
                    Row(
                      children: [
                        _action('选择', () => openRecords(context, snapshot.project.id)),
                        _action('重命名', () => _rename(context, snapshot.project)),
                        _action('分享微信', () => ExcelActions.share(context, snapshot.project)),
                        _action('删除', () => _delete(context, snapshot.project), danger: true),
                      ],
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Widget _action(String label, VoidCallback onTap, {bool danger = false}) {
    return Expanded(
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
        child: Text(
          label,
          style: TextStyle(color: danger ? AppColors.expense : AppColors.primary, fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context, CashProject project) async {
    final store = LedgerScope.of(context);
    final name = await showProjectNameDialog(
      context,
      title: '重命名项目',
      confirm: '保存',
      initial: project.name,
      validate: (value) => store.nameError(value, exceptId: project.id),
    );
    if (name == null) return;
    try {
      await store.renameProject(project.id, name);
    } on LedgerException catch (error) {
      if (context.mounted) showMessage(context, error.message);
    }
  }

  Future<void> _delete(BuildContext context, CashProject project) async {
    final store = LedgerScope.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除项目'),
        content: Text('确认删除「${project.name}」？\n账目和 Excel 文件会一起删除，且无法恢复。'),
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
    if (confirmed != true) return;
    await store.deleteProject(project.id);
  }
}
