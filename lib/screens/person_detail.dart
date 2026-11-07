import 'package:flutter/material.dart';
import '../main.dart';
import '../models.dart';
import 'record_form.dart';

class PersonDetail extends StatelessWidget {
  final String name;
  const PersonDetail({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final rs = store.recordsOfPerson(name);
        final recv = store.sumCents(rs.where((r) => r.direction == '收礼'));
        final given = store.sumCents(rs.where((r) => r.direction == '随礼'));
        final balance = recv - given;
        return Scaffold(
          appBar: AppBar(title: Text(name)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                      _s('他给我的', fmtMoney(recv)),
                      _s('我给他的', fmtMoney(given)),
                    ]),
                    const Divider(height: 24),
                    Text(
                      balance == 0 ? '往来两清' : (balance > 0 ? '他多给 ${fmtMoney(balance)}，下次他办事记得回' : '我多给 ${fmtMoney(-balance)}'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              ...rs.map((r) {
                final l = store.ledgerById(r.ledgerId);
                return Card(
                  child: ListTile(
                    title: Text('${l?.title ?? ''}（${l?.type ?? ''}）'),
                    subtitle: Text('${r.date} · ${r.method}${r.note.isEmpty ? '' : ' · ${r.note}'}${r.direction == '收礼' ? (r.returned ? ' · 已回礼' : ' · 未回礼') : ''}'),
                    trailing: Text('${r.direction == '收礼' ? '+' : '-'}${fmtMoney(r.amountCents)}',
                        style: TextStyle(fontWeight: FontWeight.bold, color: r.direction == '收礼' ? const Color(0xFFB03A2E) : Colors.blue.shade700)),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecordForm(ledgerId: r.ledgerId, existing: r))),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _s(String label, String value) => Column(children: [
        Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ]);
}
