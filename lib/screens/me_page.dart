import 'package:flutter/material.dart';
import '../main.dart';
import '../models.dart';

class MePage extends StatelessWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final all = store.records;
        final year = DateTime.now().year.toString();
        final thisYear = all.where((r) => r.date.startsWith(year));
        final recvY = store.sumCents(thisYear.where((r) => r.direction == '收礼'));
        final givenY = store.sumCents(thisYear.where((r) => r.direction == '随礼'));
        final pending = store.people().where((p) => p.pendingReturn > 0).toList();
        return Scaffold(
          appBar: AppBar(title: const Text('我的')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('$year 年往来', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    Text('收礼 ${fmtMoney(recvY)} · 随礼 ${fmtMoney(givenY)} · 共 ${thisYear.length} 笔'),
                    const SizedBox(height: 4),
                    Text('全部：${store.ledgers.length} 本礼簿 · ${all.length} 笔记录 · ${store.people().length} 位亲友', style: const TextStyle(color: Colors.black54)),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('待回礼', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    if (pending.isEmpty) const Text('没有欠着的人情，轻松。', style: TextStyle(color: Colors.black54)),
                    ...pending.map((p) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text('${p.name}：未回礼 ${fmtMoney(p.pendingReturn)}'),
                        )),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('导出 CSV'),
                  subtitle: const Text('导出全部记录，可用 Excel 打开；文件在 App 文件里能找到'),
                  onTap: () async {
                    final f = await store.exportCsvFile();
                    if (context.mounted) {
                      showDialog(context: context, builder: (_) => AlertDialog(
                            title: const Text('已导出'),
                            content: Text('文件已存为「礼钱账本导出.csv」。\n在 iPhone「文件」App 里打开本 App 的文件夹就能看到。\n\n路径：${f.path}'),
                            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('好'))],
                          ));
                    }
                  },
                ),
              ),
              const SizedBox(height: 12),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('关于', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    SizedBox(height: 8),
                    Text('礼钱账本 v0.1（试用版）\n数据只存在这台手机上，不联网、不上传。换手机前请先导出 CSV 备份。', style: TextStyle(color: Colors.black54, height: 1.6)),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
