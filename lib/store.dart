import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'models.dart';

// 本地优先存储：全部数据存应用文档目录的 data.json，不联网、不上云。
// 口径（v0.2）：待送出的随礼不计入差额与各项统计；「未回」按自动规则计算
// （见 people()），不再使用 v0.1 的手动 returned 标记。
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
    await f.writeAsString(exportJson());
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
  Future<void> addRecords(List<GiftRecord> rs) async {
    for (final r in rs.reversed) { records.insert(0, r); }
    await _save(); notifyListeners();
  }
  Future<void> updateRecord(GiftRecord r) async { await _save(); notifyListeners(); }
  Future<void> deleteRecord(String id) async { records.removeWhere((e) => e.id == id); await _save(); notifyListeners(); }

  List<GiftRecord> recordsOfLedger(String ledgerId) =>
      records.where((r) => r.ledgerId == ledgerId).toList();

  Ledger? ledgerById(String id) {
    for (final l in ledgers) { if (l.id == id) return l; }
    return null;
  }

  int sumCents(Iterable<GiftRecord> rs) => rs.fold(0, (a, r) => a + r.amountCents);

  // 按人聚合（跨账本）。
  // 差额：收礼全计；随礼只计已送出，待送出不计。
  // 未回（自动规则，FR-04.1）：把一个人的记录按时间正序排（日期升序，
  // 同日按创建时间近似——records 列表越靠前创建越晚，同日时序号大的更早），
  // 找到最后一笔「已送出」随礼，其后的收礼合计即待回金额。
  List<PersonSummary> people() {
    final map = <String, PersonSummary>{};
    final byPerson = <String, List<MapEntry<int, GiftRecord>>>{};
    for (var i = 0; i < records.length; i++) {
      final r = records[i];
      final p = map.putIfAbsent(r.person, () => PersonSummary(name: r.person));
      p.relation = r.relation;
      byPerson.putIfAbsent(r.person, () => []).add(MapEntry(i, r));
      if (r.date.compareTo(p.lastDate) > 0) p.lastDate = r.date;
      if (r.isPendingSend) continue; // 待送出只更新最近日期，不计金额与笔数
      if (r.direction == '收礼') {
        p.received += r.amountCents;
      } else {
        p.given += r.amountCents;
      }
      p.count++;
    }
    for (final entry in byPerson.entries) {
      final p = map[entry.key]!;
      final chrono = entry.value.toList()
        ..sort((a, b) {
          final d = a.value.date.compareTo(b.value.date);
          if (d != 0) return d;
          return b.key.compareTo(a.key); // 同日：列表序号大＝创建更早
        });
      var pending = 0;
      for (final e in chrono) {
        final r = e.value;
        if (r.direction == '随礼' && !r.isPendingSend) {
          pending = 0; // 已送出一次，之前的收礼视为已回
        } else if (r.direction == '收礼') {
          pending += r.amountCents;
        }
      }
      p.pendingCents = pending;
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

  // 某年收/随汇总（待送出不计）
  YearSummary yearSummary(String year) {
    var recv = 0, given = 0, count = 0;
    for (final r in records) {
      if (!r.date.startsWith(year) || r.isPendingSend) continue;
      if (r.direction == '收礼') {
        recv += r.amountCents;
      } else {
        given += r.amountCents;
      }
      count++;
    }
    return YearSummary(recv: recv, given: given, count: count);
  }

  // 按事由分布（待送出不计入随礼）
  List<TypeSummary> typeSummary() {
    final map = <String, TypeSummary>{};
    for (final l in ledgers) {
      map.putIfAbsent(l.type, () => TypeSummary(type: l.type));
    }
    for (final r in records) {
      final t = ledgerById(r.ledgerId)?.type;
      if (t == null) continue;
      final s = map.putIfAbsent(t, () => TypeSummary(type: t));
      if (r.isPendingSend) continue;
      if (r.direction == '收礼') {
        s.received += r.amountCents;
      } else {
        s.given += r.amountCents;
      }
      s.count++;
    }
    final list = map.values.toList();
    list.sort((a, b) => (b.received + b.given).compareTo(a.received + a.given));
    return list;
  }

  String exportCsv() {
    final sb = StringBuffer();
    sb.writeln('日期,账本,事由,姓名,关系,方向,金额(元),方式,状态,备注');
    String esc(String s) => '"${s.replaceAll('"', '""')}"';
    for (final r in records) {
      final l = ledgerById(r.ledgerId);
      sb.writeln([
        r.date, esc(l?.title ?? ''), esc(l?.type ?? ''), esc(r.person), esc(r.relation),
        r.direction, (r.amountCents / 100).toStringAsFixed(2), esc(r.method),
        r.direction == '随礼' ? r.status : '-', esc(r.note),
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

  // —— JSON 全量备份 / 恢复（FR-08）——
  String exportJson() => jsonEncode({
        'ledgers': ledgers.map((e) => e.toJson()).toList(),
        'records': records.map((e) => e.toJson()).toList(),
      });

  Future<File> backupFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/礼钱账本备份.json');
  }

  Future<File> exportJsonFile() async {
    final f = await backupFile();
    await f.writeAsString(exportJson());
    return f;
  }

  // 预览备份内容规模（导入确认前展示）
  ({int ledgers, int records}) countJson(String content) {
    final j = jsonDecode(content) as Map<String, dynamic>;
    return (
      ledgers: ((j['ledgers'] ?? []) as List).length,
      records: ((j['records'] ?? []) as List).length,
    );
  }

  // 整体导入（覆盖当前数据）。格式不对会抛异常，调用方提示用户。
  Future<void> importJson(String content) async {
    final j = jsonDecode(content) as Map<String, dynamic>;
    final ls = ((j['ledgers'] ?? []) as List).map((e) => Ledger.fromJson(e as Map<String, dynamic>)).toList();
    final rs = ((j['records'] ?? []) as List).map((e) => GiftRecord.fromJson(e as Map<String, dynamic>)).toList();
    ledgers = ls;
    records = rs;
    await _save();
    notifyListeners();
  }
}

class PersonSummary {
  final String name;
  String relation = '朋友';
  int received = 0; // 收礼合计（别人给我）
  int given = 0; // 随礼合计（我送出去，仅已送出）
  int pendingCents = 0; // 未回金额：最后一笔已送出之后收到的收礼合计（自动规则）
  int count = 0; // 笔数（不含待送出）
  String lastDate = '';
  PersonSummary({required this.name});
  int get balance => received - given; // 正数＝对方多给，我欠人情
  bool get hasPending => pendingCents > 0;
}

class YearSummary {
  final int recv;
  final int given;
  final int count;
  const YearSummary({required this.recv, required this.given, required this.count});
}

class TypeSummary {
  final String type;
  int received = 0;
  int given = 0;
  int count = 0;
  TypeSummary({required this.type});
}
