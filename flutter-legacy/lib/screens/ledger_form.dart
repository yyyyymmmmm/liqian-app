import 'package:flutter/material.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';

class LedgerForm extends StatefulWidget {
  final Ledger? existing;
  const LedgerForm({super.key, this.existing});
  @override
  State<LedgerForm> createState() => _LedgerFormState();
}

class _LedgerFormState extends State<LedgerForm> {
  late final TextEditingController _title;
  late String _type;
  late String _date;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _type = e?.type ?? '婚礼';
    _date = e?.date ?? todayStr();
    _note = TextEditingController(text: e?.note ?? '');
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
        context: context,
        initialDate: DateTime.tryParse(_date) ?? DateTime.now(),
        firstDate: DateTime(1990),
        lastDate: DateTime(2100));
    if (d != null) {
      setState(() => _date =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('先给礼簿起个名，如「我的婚礼」')));
      return;
    }
    if (widget.existing == null) {
      await store.addLedger(Ledger(
          id: store.newId(),
          title: _title.text.trim(),
          type: _type,
          date: _date,
          note: _note.text.trim()));
    } else {
      final e = widget.existing!;
      e.title = _title.text.trim();
      e.type = _type;
      e.date = _date;
      e.note = _note.text.trim();
      await store.updateLedger(e);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: glassAppBar(title: widget.existing == null ? '新建礼簿' : '编辑礼簿'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, glassTopPad(context), 16, 32),
        children: [
          TextField(
              controller: _title,
              decoration: const InputDecoration(
                  labelText: '礼簿名称',
                  hintText: '如：我的婚礼 / 爸爸六十大寿',
                  border: OutlineInputBorder())),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: const InputDecoration(
                labelText: '事由', border: OutlineInputBorder()),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _type,
                isExpanded: true,
                items: kLedgerTypes
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() => _type = v!),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            shape: RoundedRectangleBorder(
                side: const BorderSide(color: Colors.black26),
                borderRadius: BorderRadius.circular(4)),
            title: const Text('日期'),
            trailing: Text(_date),
            onTap: _pickDate,
          ),
          const SizedBox(height: 16),
          TextField(
              controller: _note,
              decoration: const InputDecoration(
                  labelText: '备注（可选）', border: OutlineInputBorder())),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('保存')),
          if (widget.existing != null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                          title: const Text('删除这本礼簿？'),
                          content: const Text('礼簿里的记录会一并删除，删了恢复不了。'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('取消')),
                            TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('删除')),
                          ],
                        ));
                if (ok == true) {
                  await store.deleteLedger(widget.existing!.id);
                  if (mounted) {
                    Navigator.pop(context);
                    Navigator.pop(context);
                  }
                }
              },
              child: const Text('删除礼簿', style: TextStyle(color: Colors.red)),
            ),
          ],
        ],
      ),
    );
  }
}
