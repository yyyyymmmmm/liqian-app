import 'package:flutter/material.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';

// 批量补录（FR-02.1）：照着纸质旧礼簿一行行搬进来。
// 每行只填姓名+金额，关系默认「朋友」、方式默认「现金」、日期默认今天，
// 记完后可在单笔里再改。随礼按已送出记（补录的都是已经发生的事）。
class BatchEntryPage extends StatefulWidget {
  final String ledgerId;
  const BatchEntryPage({super.key, required this.ledgerId});
  @override
  State<BatchEntryPage> createState() => _BatchEntryPageState();
}

class _Row {
  final TextEditingController person = TextEditingController();
  final TextEditingController amount = TextEditingController();
}

class _BatchEntryPageState extends State<BatchEntryPage> {
  String _direction = '收礼';
  final List<_Row> _rows = [_Row(), _Row(), _Row(), _Row()];

  @override
  void dispose() {
    for (final r in _rows) {
      r.person.dispose();
      r.amount.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final out = <GiftRecord>[];
    for (var i = 0; i < _rows.length; i++) {
      final name = _rows[i].person.text.trim();
      final amtText = _rows[i].amount.text.trim();
      if (name.isEmpty && amtText.isEmpty) continue; // 空行跳过
      if (name.isEmpty || amtText.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('第 ${i + 1} 行没填完整，姓名和金额都要有')));
        return;
      }
      final v = double.tryParse(amtText);
      if (v == null || v <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('第 ${i + 1} 行金额不对')));
        return;
      }
      out.add(GiftRecord(
        id: '${store.newId()}-$i',
        ledgerId: widget.ledgerId,
        person: name,
        amountCents: (v * 100).round(),
        direction: _direction,
        date: todayStr(),
      ));
    }
    if (out.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('一行都没填，先填几笔再保存')));
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    await store.addRecords(out);
    if (!mounted) return;
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(content: Text('共记 ${out.length} 笔')));
  }

  @override
  Widget build(BuildContext context) {
    final isBai = store.ledgerById(widget.ledgerId)?.type == '白事';
    return Scaffold(
      backgroundColor: isBai ? kBaiPaper : null,
      appBar: AppBar(backgroundColor: isBai ? kBaiPaper : null, title: const Text('批量补录')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: '收礼', label: Text('收礼（别人给我）')),
              ButtonSegment(value: '随礼', label: Text('随礼（我送出去）')),
            ],
            selected: {_direction},
            onSelectionChanged: (s) => setState(() => _direction = s.first),
          ),
          const SizedBox(height: 8),
          const Text('照着旧礼簿一行行填就行。关系先按「朋友」、方式先按「现金」记，日期是今天，记完点开单笔可以再改。', style: TextStyle(fontSize: 12.5, color: kStone, height: 1.5)),
          const SizedBox(height: 16),
          ..._rows.asMap().entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  SizedBox(
                    width: 28,
                    child: Text('${e.key + 1}', style: const TextStyle(color: kStone)),
                  ),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: e.value.person,
                      decoration: const InputDecoration(hintText: '姓名 / 称呼', isDense: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: e.value.amount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(hintText: '金额（元）', isDense: true),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                    color: kStone,
                    onPressed: _rows.length <= 1
                        ? null
                        : () => setState(() {
                              final r = _rows.removeAt(e.key);
                              r.person.dispose();
                              r.amount.dispose();
                            }),
                  ),
                ]),
              )),
          OutlinedButton.icon(
            onPressed: () => setState(() => _rows.add(_Row())),
            icon: const Icon(Icons.add),
            label: const Text('加一行'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            style: isBai ? FilledButton.styleFrom(backgroundColor: kBaiPrimary) : null,
            onPressed: _save,
            child: const Text('保存全部'),
          ),
        ],
      ),
    );
  }
}
