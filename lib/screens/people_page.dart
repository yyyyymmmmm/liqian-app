import 'package:flutter/material.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import 'person_detail.dart';
import 'ledger_detail.dart';

class PeoplePage extends StatefulWidget {
  const PeoplePage({super.key});
  @override
  State<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<PeoplePage> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final searching = _q.isNotEmpty;
        var people = store.people();
        if (searching) people = people.where((p) => p.name.contains(_q)).toList();
        final ledgers = searching
            ? store.ledgers.where((l) => l.title.contains(_q) || l.type.contains(_q)).toList()
            : <Ledger>[];
        return Scaffold(
          appBar: AppBar(title: const Text('人情往来')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '搜姓名，或者搜礼簿、事由', border: OutlineInputBorder()),
                onChanged: (v) => setState(() => _q = v.trim()),
              ),
              const SizedBox(height: 12),
              if (searching) _groupTitle('人物'),
              if (people.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 32),
                  child: Center(
                    child: Text(
                      searching ? '没有叫这个名字的人' : '还没有往来记录，先去礼簿里记一笔。',
                      style: const TextStyle(color: kStone, fontSize: 15),
                    ),
                  ),
                ),
              ...people.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      decoration: flatCard(),
                      child: ListTile(
                        title: Text(p.name),
                        subtitle: Text('${p.relation} · ${p.count} 笔 · 最近 ${p.lastDate}', style: const TextStyle(color: kStone)),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              p.balance == 0 ? '两清' : (p.balance > 0 ? '他多给 ${fmtMoney(p.balance)}' : '我多给 ${fmtMoney(-p.balance)}'),
                              style: moneyStyle(fontSize: 15, color: p.balance > 0 ? kCinnabar : kInk),
                            ),
                            if (p.hasPending) Text('还有 ${fmtMoney(p.pendingCents)} 没回', style: const TextStyle(fontSize: 11, color: kCinnabar)),
                          ],
                        ),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PersonDetail(name: p.name))),
                      ),
                    ),
                  )),
              if (searching) ...[
                const SizedBox(height: 8),
                _groupTitle('礼簿'),
                if (ledgers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Center(child: Text('没有对得上的礼簿', style: TextStyle(color: kStone, fontSize: 15))),
                  ),
                ...ledgers.map((l) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        decoration: flatCard(bai: l.type == '白事'),
                        child: ListTile(
                          leading: Container(
                            width: 30, height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: l.type == '白事' ? kBaiPrimary : kCinnabar,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(l.type.split('').join('\n'), style: serifStyle(fontSize: 12, color: Colors.white, height: 1.1)),
                          ),
                          title: Text(l.title),
                          subtitle: Text('${l.type} · ${l.date}', style: const TextStyle(color: kStone)),
                          trailing: const Icon(Icons.chevron_right, color: kStone, size: 20),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LedgerDetail(ledgerId: l.id))),
                        ),
                      ),
                    )),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _groupTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: serifStyle(fontSize: 15, color: kInk)),
      );
}
