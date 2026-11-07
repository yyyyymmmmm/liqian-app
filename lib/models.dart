// 数据模型：账本（Ledger）与往来记录（GiftRecord）
class Ledger {
  final String id;
  String title; // 账本名，如「我的婚礼」
  String type; // 事由：婚礼/满月/乔迁/生日/升学/白事/其他
  String date; // yyyy-MM-dd
  String note;
  Ledger({required this.id, required this.title, required this.type, required this.date, this.note = ''});

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'type': type, 'date': date, 'note': note};
  factory Ledger.fromJson(Map<String, dynamic> j) => Ledger(
        id: j['id'] as String,
        title: j['title'] as String,
        type: j['type'] as String,
        date: j['date'] as String,
        note: (j['note'] ?? '') as String,
      );
}

class GiftRecord {
  final String id;
  final String ledgerId;
  String person; // 姓名/称呼
  String relation; // 关系：亲戚/朋友/同事/同学/邻居/其他
  int amountCents; // 金额（分）
  String direction; // 收礼 / 随礼
  String method; // 现金/微信/支付宝/银行转账/实物
  String note;
  String date; // yyyy-MM-dd
  bool returned; // 仅收礼有意义：是否已回礼
  GiftRecord({
    required this.id,
    required this.ledgerId,
    required this.person,
    this.relation = '朋友',
    required this.amountCents,
    required this.direction,
    this.method = '现金',
    this.note = '',
    required this.date,
    this.returned = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id, 'ledgerId': ledgerId, 'person': person, 'relation': relation,
        'amountCents': amountCents, 'direction': direction, 'method': method,
        'note': note, 'date': date, 'returned': returned,
      };
  factory GiftRecord.fromJson(Map<String, dynamic> j) => GiftRecord(
        id: j['id'] as String,
        ledgerId: j['ledgerId'] as String,
        person: j['person'] as String,
        relation: (j['relation'] ?? '朋友') as String,
        amountCents: (j['amountCents'] as num).toInt(),
        direction: j['direction'] as String,
        method: (j['method'] ?? '现金') as String,
        note: (j['note'] ?? '') as String,
        date: j['date'] as String,
        returned: (j['returned'] ?? false) as bool,
      );
}

const kLedgerTypes = ['婚礼', '满月', '乔迁', '生日', '升学', '白事', '其他'];
const kRelations = ['亲戚', '朋友', '同事', '同学', '邻居', '其他'];
const kMethods = ['现金', '微信', '支付宝', '银行转账', '实物'];

String fmtMoney(int cents) {
  final yuan = cents / 100.0;
  if (cents % 100 == 0) return '¥${yuan.toInt()}';
  return '¥${yuan.toStringAsFixed(2)}';
}

String todayStr() {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}
