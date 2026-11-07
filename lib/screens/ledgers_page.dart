import 'package:flutter/material.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
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
        final given = store.sumCents(
            all.where((r) => r.direction == '随礼' && !r.isPendingSend));
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: glassAppBar(),
          floatingActionButton: Padding(
            // 抬高到悬浮玻璃底栏之上
            padding: const EdgeInsets.only(bottom: 86),
            child: FloatingActionButton.extended(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const LedgerForm())),
              icon: const Icon(Icons.add),
              label: const Text('新建礼簿'),
            ),
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(16, glassTopPad(context), 16, 120),
            children: [
              bigTitle('礼簿'),
              const SizedBox(height: 14),
              Container(
                decoration: flatCard(),
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stat('累计收礼', fmtMoney(recv), kCinnabar),
                    _stat('累计随礼', fmtMoney(given), kInk),
                    _stat('礼簿', '${store.ledgers.length} 本', kInk),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (store.ledgers.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Column(children: [
                    const Text('还没有礼簿，从最近一场事开始记。',
                        style: TextStyle(color: kStone, fontSize: 15)),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const LedgerForm())),
                      child: const Text('新建第一本礼簿',
                          style: TextStyle(color: kCinnabar)),
                    ),
                  ]),
                ),
              ...store.ledgers.map((l) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _coverCard(context, l),
                  )),
            ],
          ),
        );
      },
    );
  }

  Widget _stat(String label, String value, Color c) => Column(
        children: [
          Text(value, style: serifStyle(fontSize: 22, color: c)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: kStone, fontSize: 12)),
        ],
      );

  // 「礼簿封面」卡：朱砂封面块（白事素灰蓝）+ 竖排事由 + 描金细边，右侧是账目信息
  Widget _coverCard(BuildContext context, Ledger l) {
    final rs = store.recordsOfLedger(l.id);
    final r1 = store.sumCents(rs.where((r) => r.direction == '收礼'));
    final r2 = store
        .sumCents(rs.where((r) => r.direction == '随礼' && !r.isPendingSend));
    final isBai = l.type == '白事';
    final coverBase = isBai ? kBaiPrimary : kCinnabar;
    return Container(
      decoration: flatCard(bai: isBai, radius: kRadiusCover),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadiusCover),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => LedgerDetail(ledgerId: l.id))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            // 封面块：顶部渐变亮面 + 1px 高光线，模拟玻璃镜面边缘
            Container(
              width: 56,
              height: 92,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.alphaBlend(
                        Colors.white.withOpacity(0.28), coverBase),
                    coverBase,
                  ],
                  stops: const [0, 0.38],
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isBai ? kBaiLine : kGold, width: 1),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: 3,
                    left: 9,
                    right: 9,
                    child: Container(
                        height: 1, color: Colors.white.withOpacity(0.4)),
                  ),
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          l.type.split('').join('\n'),
                          textAlign: TextAlign.center,
                          style: serifStyle(
                              fontSize: 20, color: Colors.white, height: 1.15),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: isBai ? kBaiLine : const Color(0xFFF6F1E7),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.title,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: kInk)),
                  const SizedBox(height: 4),
                  Text(
                    '${l.date}${l.note.isEmpty ? '' : ' · ${l.note}'}',
                    style: const TextStyle(fontSize: 12.5, color: kStone),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    const Text('收 ',
                        style: TextStyle(fontSize: 12.5, color: kStone)),
                    Text(fmtMoney(r1),
                        style: moneyStyle(
                            fontSize: 15, color: isBai ? kBaiInk : kCinnabar)),
                    const SizedBox(width: 14),
                    const Text('随 ',
                        style: TextStyle(fontSize: 12.5, color: kStone)),
                    Text(fmtMoney(r2),
                        style: moneyStyle(fontSize: 15, color: kInk)),
                    const Spacer(),
                    Text('${rs.length} 笔',
                        style: const TextStyle(fontSize: 12.5, color: kStone)),
                  ]),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: kStone, size: 20),
          ]),
        ),
      ),
    );
  }
}
