import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'models.dart';

// 本地优先存储：全部数据存应用文档目录的 data.json，不联网、不上云。
class Store extends ChangeNotifier {
  List<Ledger> ledgers = [];
  List<GiftRecord> records = [];
  bool loaded = false;

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/liqian_data.json');
  }

  Future<void> load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        ledgers = ((j['ledgers'] ?? []) as List).map((e) => Ledger.fromJson(e as Map<String, dynamic>)).toList();
        records = ((j['records'] ?? []) as List).map((e) => GiftRecord.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {
      ledgers = [];
      records = [];
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final f = await _file();
    await f.writeAsString(jsonEncode({
      'ledgers': ledgers.map((e) => e.toJson()).toList(),
      'records': records.map((e) => e.toJson()).toList(),
    }));
  }

  String newId() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<void> addLedger(Ledger l) async { ledgers.insert(0, l); await _save(); notifyListeners(); }
  Future<void> updateLedger(Ledger l) async { await _save(); notifyListeners(); }
  Future<void> deleteLedger(String id) async {
    ledgers.removeWhere((e) => e.id == id);
    records.removeWhere((e) => e.ledgerId == id);
    await _save(); notifyListeners();
  }

  Future<void> addRecord(GiftRecord r) async { records.insert(0, r); await _save(); notifyListeners(); }
  Future<void> updateRecord(GiftRecord r) async { await _save(); notifyListeners(); }
  Future<void> deleteRecord(String id) async { records.removeWhere((e) => e.id == id); await _save(); notifyListeners(); }
  Future<void> toggleReturned(GiftRecord r) async { r.returned = !r.returned; await _save(); notifyListeners(); }

  List<GiftRecord> recordsOfLedger(String ledgerId) =>
      records.where((r) => r.ledgerId == ledgerId).toList();

  Ledger? ledgerById(String id) {
    for (final l in ledgers) { if (l.id == id) return l; }
    return null;
  }

  int sumCents(Iterable<GiftRecord> rs) => rs.fold(0, (a, r) => a + r.amountCents);

  // 按人聚合
  List<PersonSummary> people() {
    final map = <String, PersonSummary>{};
    for (final r in records) {
      final p = map.putIfAbsent(r.person, () => PersonSummary(name: r.person));
      p.relation = r.relation;
      if (r.direction == '收礼') {
        p.received += r.amountCents;
        if (!r.returned) p.pendingReturn += r.amountCents;
      } else {
        p.given += r.amountCents;
      }
      if (r.date.compareTo(p.lastDate) > 0) p.lastDate = r.date;
      p.count++;
    }
    final list = map.values.toList();
    list.sort((a, b) => b.lastDate.compareTo(a.lastDate));
    return list;
  }

  List<GiftRecord> recordsOfPerson(String name) {
    final list = records.where((r) => r.person == name).toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  String exportCsv() {
    final sb = StringBuffer();
    sb.writeln('日期,账本,事由,姓名,关系,方向,金额(元),方式,已回礼,备注');
    String esc(String s) => '"${s.replaceAll('"', '""')}"';
    for (final r in records) {
      final l = ledgerById(r.ledgerId);
      sb.writeln([
        r.date, esc(l?.title ?? ''), esc(l?.type ?? ''), esc(r.person), esc(r.relation),
        r.direction, (r.amountCents / 100).toStringAsFixed(2), esc(r.method),
        r.direction == '收礼' ? (r.returned ? '是' : '否') : '-', esc(r.note),
      ].join(','));
    }
    return sb.toString();
  }

  Future<File> exportCsvFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/礼钱账本导出.csv');
    await f.writeAsString(exportCsv());
    return f;
  }
}

class PersonSummary {
  final String name;
  String relation = '朋友';
  int received = 0; // 收礼合计（别人给我）
  int given = 0; // 随礼合计（我送出去）
  int pendingReturn = 0; // 未回礼的收礼合计
  int count = 0;
  String lastDate = '';
  PersonSummary({required this.name});
  int get balance => received - given; // 正数＝对方多给，我欠人情
}
