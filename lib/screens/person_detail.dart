import 'package:flutter/material.dart';
import '../main.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
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
        final given = store
            .sumCents(rs.where((r) => r.direction == '随礼' && !r.isPendingSend));
        final balance = recv - given;
        PersonSummary? summary;
        for (final p in store.people()) {
          if (p.name == name) {
            summary = p;
            break;
          }
        }
        final pending = summary?.pendingCents ?? 0;
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: glassAppBar(title: name),
          body: ListView(
            padding: EdgeInsets.fromLTRB(16, glassTopPad(context), 16, 32),
            children: [
              Container(
                decoration: flatCard(),
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _s('他给我的', fmtMoney(recv)),
                        _s('我给他的', fmtMoney(given)),
                      ]),
                  const Divider(height: 24),
                  Text(
                    balance == 0
                        ? '往来两清'
                        : (balance > 0
                            ? '他多给 ${fmtMoney(balance)}，下次他办事记得回'
                            : '我多给 ${fmtMoney(-balance)}'),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  if (pending > 0) ...[
                    const SizedBox(height: 4),
                    Text('其中 ${fmtMoney(pending)} 是最近收下、还没回的',
                        style:
                            const TextStyle(fontSize: 12.5, color: kCinnabar)),
                  ],
                ]),
              ),
              const SizedBox(height: 12),
              ...rs.map((r) {
                final l = store.ledgerById(r.ledgerId);
                final isBai = l?.type == '白事';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    decoration: flatCard(bai: isBai),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(kRadiusCard)),
                      title: Row(children: [
                        Expanded(
                            child: Text('${l?.title ?? ''}（${l?.type ?? ''}）')),
                        directionTag(r.direction, bai: isBai),
                        if (r.isPendingSend) ...[
                          const SizedBox(width: 6),
                          outlineTag('待送出', bai: isBai),
                        ],
                      ]),
                      subtitle: Text(
                        '${r.date} · ${r.method}${r.note.isEmpty ? '' : ' · ${r.note}'}',
                        style: const TextStyle(color: kStone),
                      ),
                      trailing: Text(
                        '${r.direction == '收礼' ? '+' : '-'}${fmtMoney(r.amountCents)}',
                        style: moneyStyle(
                            fontSize: 16,
                            color: r.direction == '收礼'
                                ? (isBai ? kBaiInk : kCinnabar)
                                : kInk),
                      ),
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => RecordForm(
                                  ledgerId: r.ledgerId, existing: r))),
                    ),
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
        Text(value, style: serifStyle(fontSize: 18, color: kInk)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 12, color: kStone)),
      ]);
}
