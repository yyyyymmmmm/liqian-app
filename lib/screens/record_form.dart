import 'package:flutter/material.dart';
import '../main.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';

class RecordForm extends StatefulWidget {
  final String ledgerId;
  final GiftRecord? existing;
  const RecordForm({super.key, required this.ledgerId, this.existing});
  @override
  State<RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends State<RecordForm> {
  late final TextEditingController _person;
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late String _relation;
  late String _direction;
  late String _method;
  late String _date;
  late String _status; // 仅随礼：已送出 / 待送出

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _person = TextEditingController(text: e?.person ?? '');
    _person.addListener(() {
      if (mounted) setState(() {});
    });
    _amount = TextEditingController(
        text: e == null
            ? ''
            : (e.amountCents % 100 == 0
                ? (e.amountCents ~/ 100).toString()
                : (e.amountCents / 100).toStringAsFixed(2)));
    _note = TextEditingController(text: e?.note ?? '');
    _relation = e?.relation ?? '朋友';
    _direction = e?.direction ?? '收礼';
    _method = e?.method ?? '现金';
    _date = e?.date ?? todayStr();
    _status = e?.status ?? '已送出';
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
        context: context,
        initialDate: DateTime.tryParse(_date) ?? DateTime.now(),
        firstDate: DateTime(1990),
        lastDate: DateTime(2100));
    if (d != null)
      setState(() => _date =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
  }

  int? _parseCents() {
    final v = double.tryParse(_amount.text.trim());
    if (v == null || v <= 0) return null;
    return (v * 100).round();
  }

  // 历史人物联想：名字里出现过的就提示，选中带入上次用的关系
  List<PersonSummary> get _suggestions {
    final q = _person.text.trim();
    if (q.isEmpty) return [];
    return store
        .people()
        .where((p) => p.name.contains(q) && p.name != q)
        .take(5)
        .toList();
  }

  // 同人提示：这个名字在本账本已有的笔数（编辑时不算自己这笔）
  int get _sameLedgerCount {
    final q = _person.text.trim();
    if (q.isEmpty) return 0;
    return store.records
        .where((r) =>
            r.ledgerId == widget.ledgerId &&
            r.person == q &&
            r.id != widget.existing?.id)
        .length;
  }

  Future<bool> _save() async {
    final cents = _parseCents();
    if (_person.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('姓名还没填')));
      return false;
    }
    if (cents == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('金额不对，检查一下')));
      return false;
    }
    final status = _direction == '随礼' ? _status : '已送出';
    if (widget.existing == null) {
      await store.addRecord(GiftRecord(
        id: store.newId(),
        ledgerId: widget.ledgerId,
        person: _person.text.trim(),
        relation: _relation,
        amountCents: cents,
        direction: _direction,
        method: _method,
        note: _note.text.trim(),
        date: _date,
        status: status,
      ));
    } else {
      final e = widget.existing!;
      e.person = _person.text.trim();
      e.relation = _relation;
      e.amountCents = cents;
      e.direction = _direction;
      e.method = _method;
      e.note = _note.text.trim();
      e.date = _date;
      e.status = status;
      await store.updateRecord(e);
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestions;
    final sameCount = _sameLedgerCount;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: glassAppBar(title: widget.existing == null ? '记一笔' : '编辑记录'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, glassTopPad(context), 16, 32),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: '收礼', label: Text('收礼（别人给我）')),
              ButtonSegment(value: '随礼', label: Text('随礼（我送出去）')),
            ],
            selected: {_direction},
            onSelectionChanged: (s) => setState(() => _direction = s.first),
          ),
          if (_direction == '随礼') ...[
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: '已送出', label: Text('已送出')),
                ButtonSegment(value: '待送出', label: Text('待送出（先记着）')),
              ],
              selected: {_status},
              onSelectionChanged: (s) => setState(() => _status = s.first),
            ),
            if (_status == '待送出')
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('待送出的先记着，不算进往来差额，送出去后改成「已送出」。',
                    style: TextStyle(fontSize: 12.5, color: kStone)),
              ),
          ],
          const SizedBox(height: 16),
          TextField(
              controller: _person,
              decoration: const InputDecoration(
                  labelText: '姓名 / 称呼',
                  hintText: '如：大舅、二姨、张三',
                  border: OutlineInputBorder())),
          if (suggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: flatCard(),
              child: Column(
                children: suggestions
                    .map((p) => ListTile(
                          dense: true,
                          title: Text(p.name),
                          subtitle: Text('${p.relation} · 共 ${p.count} 笔往来'),
                          onTap: () {
                            _person.text = p.name;
                            _person.selection =
                                TextSelection.collapsed(offset: p.name.length);
                            if (kRelations.contains(p.relation))
                              setState(() => _relation = p.relation);
                          },
                        ))
                    .toList(),
              ),
            ),
          if (sameCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('此人在本账本已有 $sameCount 笔，再记一笔会并列保存。',
                  style: const TextStyle(fontSize: 12.5, color: kStone)),
            ),
          const SizedBox(height: 16),
          TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: '金额（元）',
                  hintText: '如：500',
                  border: OutlineInputBorder())),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
                child: _drop('关系', _relation, kRelations,
                    (v) => setState(() => _relation = v))),
            const SizedBox(width: 12),
            Expanded(
                child: _drop('方式', _method, kMethods,
                    (v) => setState(() => _method = v))),
          ]),
          const SizedBox(height: 16),
          ListTile(
            shape: RoundedRectangleBorder(
                side: const BorderSide(color: kHairline),
                borderRadius: BorderRadius.circular(10)),
            tileColor: kCard,
            title: const Text('日期'),
            trailing: Text(_date),
            onTap: _pickDate,
          ),
          const SizedBox(height: 16),
          TextField(
              controller: _note,
              decoration: const InputDecoration(
                  labelText: '备注（可选）',
                  hintText: '实物礼写这里，如：两瓶酒',
                  border: OutlineInputBorder())),
          const SizedBox(height: 24),
          FilledButton(
              onPressed: () async {
                if (await _save() && mounted) Navigator.pop(context);
              },
              child: const Text('保存')),
          if (widget.existing == null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () async {
                if (await _save()) {
                  setState(() {
                    _person.clear();
                    _amount.clear();
                    _note.clear();
                  });
                  if (mounted)
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已保存，继续记下一笔')));
                }
              },
              child: const Text('保存并继续记'),
            ),
          ],
          if (widget.existing != null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: () async {
                await store.deleteRecord(widget.existing!.id);
                if (mounted) Navigator.pop(context);
              },
              child: const Text('删除这笔', style: TextStyle(color: kCinnabar)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _drop(String label, String value, List<String> items,
      ValueChanged<String> onChanged) {
    return InputDecorator(
      decoration:
          InputDecoration(labelText: label, border: const OutlineInputBorder()),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          items: items
              .map((t) => DropdownMenuItem(value: t, child: Text(t)))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
