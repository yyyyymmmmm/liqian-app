import 'package:flutter/material.dart';
import '../main.dart';
import '../models.dart';
import 'ledger_form.dart';
import 'ledger_detail.dart';

class LedgersPage extends StatelessWidget {
  const LedgersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final all = store.records;
        final recv = store.sumCents(all.where((r) => r.direction == '收礼'));
        final given = store.sumCents(all.where((r) => r.direction == '随礼'));
        return Scaffold(
          appBar: AppBar(title: const Text('礼钱账本')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LedgerForm())),
            icon: const Icon(Icons.add),
            label: const Text('新建礼簿'),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: const Color(0xFFB03A2E),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _stat('累计收礼', fmtMoney(recv), Colors.white),
                      _stat('累计随礼', fmtMoney(given), Colors.white),
                      _stat('礼簿', '${store.ledgers.length} 本', Colors.white),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (store.ledgers.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Center(child: Text('还没有礼簿\n点右下角「新建礼簿」，从最近一场事开始记', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54, height: 1.6))),
                ),
              ...store.ledgers.map((l) {
                final rs = store.recordsOfLedger(l.id);
                final r1 = store.sumCents(rs.where((r) => r.direction == '收礼'));
                final r2 = store.sumCents(rs.where((r) => r.direction == '随礼'));
                final isBai = l.type == '白事';
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isBai ? Colors.grey.shade300 : const Color(0xFFF6E3DF),
                      child: Text(l.type.characters.first, style: TextStyle(color: isBai ? Colors.black54 : const Color(0xFFB03A2E))),
                    ),
                    title: Text(l.title),
                    subtitle: Text('${l.date} · ${rs.length} 笔 · 收 ${fmtMoney(r1)} · 随 ${fmtMoney(r2)}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LedgerDetail(ledgerId: l.id))),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _stat(String label, String value, Color c) => Column(
        children: [
          Text(value, style: TextStyle(color: c, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: c.withOpacity(0.85), fontSize: 12)),
        ],
      );
}
