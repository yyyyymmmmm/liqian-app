import 'package:flutter/material.dart';
import '../main.dart';
import '../models.dart';
import 'ledger_form.dart';
import 'record_form.dart';

class LedgerDetail extends StatelessWidget {
  final String ledgerId;
  const LedgerDetail({super.key, required this.ledgerId});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final ledger = store.ledgerById(ledgerId);
        if (ledger == null) return const Scaffold(body: Center(child: Text('礼簿不存在')));
        final rs = store.recordsOfLedger(ledgerId);
        final recv = store.sumCents(rs.where((r) => r.direction == '收礼'));
        final given = store.sumCents(rs.where((r) => r.direction == '随礼'));
        final isBai = ledger.type == '白事';
        return Scaffold(
          appBar: AppBar(
            title: Text(ledger.title),
            actions: [
              IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LedgerForm(existing: ledger)))),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecordForm(ledgerId: ledgerId))),
            icon: const Icon(Icons.add),
            label: const Text('记一笔'),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: isBai ? Colors.grey.shade200 : const Color(0xFFF6E3DF),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                    _s('收礼', fmtMoney(recv), rs.where((r) => r.direction == '收礼').length),
                    _s('随礼', fmtMoney(given), rs.where((r) => r.direction == '随礼').length),
                    _s('人数', '${rs.map((r) => r.person).toSet().length}', null),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              if (rs.isEmpty)
                const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Text('还没有记录，点右下角「记一笔」', style: TextStyle(color: Colors.black54)))),
              ...rs.map((r) => Card(
                    child: ListTile(
                      title: Row(children: [
                        Text(r.person),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: r.direction == '收礼' ? const Color(0xFFF6E3DF) : Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
                          child: Text(r.direction, style: const TextStyle(fontSize: 11)),
                        ),
                        if (r.direction == '收礼' && r.returned)
                          const Padding(padding: EdgeInsets.only(left: 6), child: Text('已回礼', style: TextStyle(fontSize: 11, color: Colors.green))),
                      ]),
                      subtitle: Text('${r.relation} · ${r.method} · ${r.date}${r.note.isEmpty ? '' : ' · ${r.note}'}'),
                      trailing: Text(fmtMoney(r.amountCents), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecordForm(ledgerId: ledgerId, existing: r))),
                      onLongPress: r.direction == '收礼' ? () => store.toggleReturned(r) : null,
                    ),
                  )),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('提示：长按一笔「收礼」可标记 / 取消「已回礼」', textAlign: TextAlign.center, style: TextStyle(color: Colors.black38, fontSize: 12)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _s(String label, String value, int? count) => Column(children: [
        Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(count == null ? label : '$label · $count 笔', style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ]);
}
