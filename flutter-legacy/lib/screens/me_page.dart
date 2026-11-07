import 'package:flutter/material.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';

class MePage extends StatelessWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final year = DateTime.now().year.toString();
        final ys = store.yearSummary(year);
        final pending = store.people().where((p) => p.hasPending).toList();
        final types = store.typeSummary().where((t) => t.count > 0).toList();
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: glassAppBar(),
          body: ListView(
            padding: EdgeInsets.fromLTRB(16, glassTopPad(context), 16, 120),
            children: [
              bigTitle('我的'),
              const SizedBox(height: 14),
              Container(
                decoration: flatCard(),
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$year 年往来',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 10),
                      Row(children: [
                        const Text('收礼 ', style: TextStyle(color: kStone)),
                        Text(fmtMoney(ys.recv),
                            style: moneyStyle(fontSize: 17, color: kCinnabar)),
                        const SizedBox(width: 16),
                        const Text('随礼 ', style: TextStyle(color: kStone)),
                        Text(fmtMoney(ys.given),
                            style: moneyStyle(fontSize: 17, color: kInk)),
                        const SizedBox(width: 16),
                        Text('共 ${ys.count} 笔',
                            style: const TextStyle(color: kStone)),
                      ]),
                      const SizedBox(height: 6),
                      Text(
                          '全部：${store.ledgers.length} 本礼簿 · ${store.records.length} 笔记录 · ${store.people().length} 位亲友',
                          style:
                              const TextStyle(color: kStone, fontSize: 12.5)),
                    ]),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: flatCard(),
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('还没回的礼',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 8),
                      if (pending.isEmpty)
                        const Text('没有欠着的人情，轻松。',
                            style: TextStyle(color: kStone)),
                      ...pending.map((p) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(children: [
                              Text(p.name),
                              const Spacer(),
                              Text(fmtMoney(p.pendingCents),
                                  style: moneyStyle(
                                      fontSize: 15, color: kCinnabar)),
                            ]),
                          )),
                      if (pending.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text('按「最近一次收礼之后还没送出」自动算的，不用手动标。',
                              style: TextStyle(color: kStone, fontSize: 12)),
                        ),
                    ]),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: flatCard(),
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('按事由',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 8),
                      if (types.isEmpty)
                        const Text('还没有记录', style: TextStyle(color: kStone)),
                      ...types.map((t) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(children: [
                              Text(t.type),
                              const SizedBox(width: 8),
                              Text('${t.count} 笔',
                                  style: const TextStyle(
                                      color: kStone, fontSize: 12.5)),
                              const Spacer(),
                              Text(
                                  '收 ${fmtMoney(t.received)} · 随 ${fmtMoney(t.given)}',
                                  style: moneyStyle(fontSize: 14, color: kInk)),
                            ]),
                          )),
                    ]),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: flatCard(),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(kRadiusCard)),
                  leading: const Icon(Icons.table_view_outlined),
                  title: const Text('导出 CSV'),
                  subtitle: const Text('全部记录导出成表格，Excel 能打开',
                      style: TextStyle(color: kStone)),
                  onTap: () async {
                    final f = await store.exportCsvFile();
                    if (context.mounted) {
                      showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                                title: const Text('已导出'),
                                content: Text(
                                    '文件已存为「礼钱账本导出.csv」。\n在 iPhone「文件」App 里打开本 App 的文件夹就能看到。\n\n路径：${f.path}'),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('好'))
                                ],
                              ));
                    }
                  },
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: flatCard(),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(kRadiusCard)),
                  leading: const Icon(Icons.save_outlined),
                  title: const Text('导出备份（JSON）'),
                  subtitle: const Text('全量备份：礼簿和记录都在，换手机靠它恢复',
                      style: TextStyle(color: kStone)),
                  onTap: () async {
                    final f = await store.exportJsonFile();
                    if (context.mounted) {
                      showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                                title: const Text('备份已存好'),
                                content: Text(
                                    '文件已存为「礼钱账本备份.json」，在本 App 的文件夹里。\n换手机前，把这个文件另外存一份到电脑或网盘。\n\n路径：${f.path}'),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('好'))
                                ],
                              ));
                    }
                  },
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: flatCard(),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(kRadiusCard)),
                  leading: const Icon(Icons.restore_outlined),
                  title: const Text('从备份恢复'),
                  subtitle: const Text('读取「礼钱账本备份.json」，覆盖现在的数据',
                      style: TextStyle(color: kStone)),
                  onTap: () => _restore(context),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: flatCard(),
                padding: const EdgeInsets.all(16),
                child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('关于',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      SizedBox(height: 8),
                      Text(
                          '礼钱账本 v0.3（试用版）\n数据只存在这台手机上，不联网、不上传。换手机前请先用上面的「导出备份」存一份。',
                          style: TextStyle(color: kStone, height: 1.6)),
                    ]),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Future<void> _restore(BuildContext context) async {
    final f = await store.backupFile();
    if (!await f.exists()) {
      if (context.mounted) {
        showDialog(
            context: context,
            builder: (_) => AlertDialog(
                  title: const Text('没找到备份文件'),
                  content: const Text(
                      '本 App 文件夹里没有「礼钱账本备份.json」。\n先把备份文件放进来（隔空投送/文件 App 都行），再来恢复。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('好'))
                  ],
                ));
      }
      return;
    }
    String content;
    ({int ledgers, int records}) counts;
    try {
      content = await f.readAsString();
      counts = store.countJson(content);
    } catch (_) {
      if (context.mounted) {
        showDialog(
            context: context,
            builder: (_) => AlertDialog(
                  title: const Text('备份文件有问题'),
                  content: const Text('这个文件读不了，或者不是礼钱账本的备份。数据没有动。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('好'))
                  ],
                ));
      }
      return;
    }
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              title: const Text('覆盖恢复？'),
              content: Text(
                  '备份里有 ${counts.ledgers} 本礼簿、${counts.records} 笔记录。\n现在手机里有 ${store.ledgers.length} 本礼簿、${store.records.length} 笔记录，恢复后会被全部覆盖，覆盖了就回不来了。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('覆盖恢复')),
              ],
            ));
    if (ok != true) return;
    try {
      await store.importJson(content);
      if (context.mounted) {
        showDialog(
            context: context,
            builder: (_) => AlertDialog(
                  title: const Text('恢复完成'),
                  content:
                      Text('已导入 ${counts.ledgers} 本礼簿、${counts.records} 笔记录。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('好'))
                  ],
                ));
      }
    } catch (_) {
      if (context.mounted) {
        showDialog(
            context: context,
            builder: (_) => AlertDialog(
                  title: const Text('恢复失败'),
                  content: const Text('导入时出错，数据没有改动。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('好'))
                  ],
                ));
      }
    }
  }
}
