import 'package:flutter/material.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import 'ledger_form.dart';
import 'record_form.dart';
import 'batch_entry_page.dart';

class LedgerDetail extends StatelessWidget {
  final String ledgerId;
  const LedgerDetail({super.key, required this.ledgerId});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final ledger = store.ledgerById(ledgerId);
        if (ledger == null)
          return const Scaffold(body: Center(child: Text('礼簿不存在')));
        final rs = store.recordsOfLedger(ledgerId);
        final recv = store.sumCents(rs.where((r) => r.direction == '收礼'));
        final given = store
            .sumCents(rs.where((r) => r.direction == '随礼' && !r.isPendingSend));
        final isBai = ledger.type == '白事';
        final ink = isBai ? kBaiInk : kInk;
        final accent = isBai ? kBaiPrimary : kCinnabar;
        return Scaffold(
          backgroundColor: isBai ? kBaiPaper : null,
          extendBodyBehindAppBar: true,
          appBar: glassAppBar(
            title: ledger.title,
            bai: isBai,
            actions: [
              IconButton(
                icon: const Icon(Icons.playlist_add),
                tooltip: '批量补录',
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => BatchEntryPage(ledgerId: ledgerId))),
              ),
              IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => LedgerForm(existing: ledger)))),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: isBai ? kBaiPrimary : null,
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => RecordForm(ledgerId: ledgerId))),
            icon: const Icon(Icons.add),
            label: const Text('记一笔'),
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(16, glassTopPad(context), 16, 96),
            children: [
              Container(
                decoration: flatCard(bai: isBai),
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _s('收礼', fmtMoney(recv),
                          rs.where((r) => r.direction == '收礼').length, accent),
                      _s(
                          '随礼',
                          fmtMoney(given),
                          rs
                              .where((r) =>
                                  r.direction == '随礼' && !r.isPendingSend)
                              .length,
                          ink),
                      _s('人数', '${rs.map((r) => r.person).toSet().length}',
                          null, ink),
                    ]),
              ),
              const SizedBox(height: 12),
              if (rs.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Column(children: [
                    Text('这本礼簿还空着，记第一笔吧。',
                        style: TextStyle(
                            color: isBai ? kBaiPrimary : kStone, fontSize: 15)),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => RecordForm(ledgerId: ledgerId))),
                      child: Text('记一笔', style: TextStyle(color: accent)),
                    ),
                  ]),
                ),
              ...rs.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      decoration: flatCard(bai: isBai),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(kRadiusCard)),
                        title: Row(children: [
                          Text(r.person, style: TextStyle(color: ink)),
                          const SizedBox(width: 8),
                          directionTag(r.direction, bai: isBai),
                          if (r.isPendingSend) ...[
                            const SizedBox(width: 6),
                            outlineTag('待送出', bai: isBai),
                          ],
                        ]),
                        subtitle: Text(
                          '${r.relation} · ${r.method} · ${r.date}${r.note.isEmpty ? '' : ' · ${r.note}'}',
                          style: TextStyle(color: isBai ? kBaiPrimary : kStone),
                        ),
                        trailing: Text(
                          fmtMoney(r.amountCents),
                          style: moneyStyle(
                              fontSize: 16,
                              color: r.direction == '收礼' ? accent : ink),
                        ),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => RecordForm(
                                    ledgerId: ledgerId, existing: r))),
                      ),
                    ),
                  )),
            ],
          ),
        );
      },
    );
  }

  Widget _s(String label, String value, int? count, Color c) =>
      Column(children: [
        Text(value, style: serifStyle(fontSize: 18, color: c)),
        const SizedBox(height: 2),
        Text(count == null ? label : '$label · $count 笔',
            style: const TextStyle(fontSize: 12, color: kStone)),
      ]);
}
