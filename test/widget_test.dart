import 'dart:io';

import 'package:cashflow/app.dart';
import 'package:cashflow/memory_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('cashflow_widget');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  testWidgets('voice is the default entry mode and a handwritten row can be saved', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = MemoryLedgerRepository(Directory(p.join(root.path, 'excel')));
    await tester.pumpWidget(CashflowApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.text('新增记账内容'), findsOneWidget);
    expect(find.text('还没有记账'), findsOneWidget);
    expect(find.text('设置'), findsNothing);

    await tester.tap(find.byKey(const Key('add-entry-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('project-name-field')), '家庭日常');
    await tester.tap(find.byKey(const Key('project-name-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('按住 说话'), findsOneWidget);

    await tester.tap(find.byKey(const Key('mode-handwriting')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('manual-content')), '测试午餐');
    await tester.enterText(find.byKey(const Key('manual-amount')), '35');
    await tester.ensureVisible(find.byKey(const Key('add-draft-button')));
    await tester.tap(find.byKey(const Key('add-draft-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-entry-button')));
    await tester.pumpAndSettle();

    expect(find.text('新增记账内容'), findsOneWidget);
    expect(find.text('测试午餐'), findsWidgets);
    expect(find.text('家庭日常'), findsWidgets);
    expect(find.text('按住 说话'), findsNothing);

    await repository.close();
  });
}
