import 'package:flutter/material.dart';

import '../app.dart';
import '../format.dart';
import '../ledger_store.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'compose_screen.dart';
import 'project_name_dialog.dart';
import 'records_screen.dart';

Future<CashProject?> createProjectFlow(BuildContext context, LedgerStore store) async {
  final name = await showProjectNameDialog(
    context,
    title: '新建记账项目',
    confirm: '创建',
    validate: store.nameError,
  );
  if (name == null) return null;
  try {
    return await store.createProject(name);
  } on LedgerException catch (error) {
    if (context.mounted) showMessage(context, error.message);
    return null;
  }
}

Future<void> startNewEntry(BuildContext context) async {
  final store = LedgerScope.of(context);
  final CashProject? project;
  if (store.snapshots.isEmpty) {
    project = await createProjectFlow(context, store);
  } else {
    project = await showModalBottomSheet<CashProject>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final current = LedgerScope.of(sheetContext);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  '选择记账项目',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined, color: AppColors.primary),
                title: const Text('新建项目'),
                onTap: () async {
                  final created = await createProjectFlow(sheetContext, current);
                  if (created != null && sheetContext.mounted) {
                    Navigator.pop(sheetContext, created);
                  }
                },
              ),
              for (final snapshot in current.snapshots)
                ListTile(
                  leading: const Icon(Icons.folder_outlined, color: AppColors.primary),
                  title: Text(snapshot.project.name),
                  subtitle: Text('结余 ${formatMoney(snapshot.balance)}'),
                  onTap: () => Navigator.pop(sheetContext, snapshot.project),
                ),
            ],
          ),
        );
      },
    );
  }
  if (project == null || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => ComposeScreen(projectId: project!.id)),
  );
}

void openRecords(BuildContext context, String projectId) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => RecordsScreen(projectId: projectId)),
  );
}
