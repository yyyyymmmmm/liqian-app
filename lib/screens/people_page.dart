import 'package:flutter/material.dart';
import '../main.dart';
import '../models.dart';
import 'person_detail.dart';

class PeoplePage extends StatefulWidget {
  const PeoplePage({super.key});
  @override
  State<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<PeoplePage> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        var people = store.people();
        if (_q.isNotEmpty) people = people.where((p) => p.name.contains(_q)).toList();
        return Scaffold(
          appBar: AppBar(title: const Text('人情往来')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '搜姓名，回礼前先查他', border: OutlineInputBorder()),
                onChanged: (v) => setState(() => _q = v.trim()),
              ),
              const SizedBox(height: 12),
              if (people.isEmpty)
                const Padding(padding: EdgeInsets.only(top: 48), child: Center(child: Text('还没有往来记录', style: TextStyle(color: Colors.black54)))),
              ...people.map((p) => Card(
                    child: ListTile(
                      title: Text(p.name),
                      subtitle: Text('${p.relation} · ${p.count} 笔 · 最近 ${p.lastDate}'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            p.balance == 0 ? '两清' : (p.balance > 0 ? '他多给 ${fmtMoney(p.balance)}' : '我多给 ${fmtMoney(-p.balance)}'),
                            style: TextStyle(fontWeight: FontWeight.bold, color: p.balance > 0 ? const Color(0xFFB03A2E) : Colors.black87),
                          ),
                          if (p.pendingReturn > 0) Text('未回礼 ${fmtMoney(p.pendingReturn)}', style: const TextStyle(fontSize: 11, color: Colors.orange)),
                        ],
                      ),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PersonDetail(name: p.name))),
                    ),
                  )),
            ],
          ),
        );
      },
    );
  }
}
