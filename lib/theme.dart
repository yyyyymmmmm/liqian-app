import 'package:flutter/material.dart';

// 「现代礼簿」设计系统（docs/DESIGN.md）：
// 米纸底、墨字、朱砂红、描金细线。信息靠线条与留白分层，卡片无投影、只有描边。
// 唯一的记忆点是礼簿封面，其余界面安静克制。

// —— 红事色板 ——
const Color kPaper = Color(0xFFF6F1E7); // 纸：全局背景
const Color kInk = Color(0xFF2B2620); // 墨：主文字
const Color kCinnabar = Color(0xFFA62B1F); // 朱砂：主色
const Color kGold = Color(0xFFB98A2F); // 描金：细线点缀
const Color kStone = Color(0xFF7A7264); // 次文字
const Color kCard = Color(0xFFFFFDF8); // 卡面
const Color kHairline = Color(0xFFE3DCCB); // 描边线

// —— 白事色板（白事账本内整页切换：无红、无金） ——
const Color kBaiPaper = Color(0xFFECEEF0);
const Color kBaiInk = Color(0xFF33383B);
const Color kBaiPrimary = Color(0xFF5B6770); // 素灰蓝
const Color kBaiLine = Color(0xFFD5D9DC);
const Color kBaiCard = Color(0xFFF7F8F9);

// 随礼方向签底色（素蓝灰，红白事通用）
const Color kGivenTagBg = Color(0xFF5B6770);

// 衬线：标题与金额用。iOS 走 Songti SC，安卓回退 Noto Serif SC / serif。
const String kSerifFamily = 'Songti SC';
const List<String> kSerifFallback = ['Noto Serif SC', 'serif'];

TextStyle serifStyle({
  double? fontSize,
  FontWeight fontWeight = FontWeight.bold,
  Color? color,
  double? height,
}) {
  return TextStyle(
    fontFamily: kSerifFamily,
    fontFamilyFallback: kSerifFallback,
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
  );
}

// 金额文本：衬线加粗
TextStyle moneyStyle({double fontSize = 16, Color? color}) =>
    serifStyle(fontSize: fontSize, color: color);

// 无阴影卡面容器：卡面色 + 1px 描边 + 圆角 10
BoxDecoration flatCard({bool bai = false, Color? color}) {
  return BoxDecoration(
    color: color ?? (bai ? kBaiCard : kCard),
    border: Border.all(color: bai ? kBaiLine : kHairline),
    borderRadius: BorderRadius.circular(10),
  );
}

// 方向签：收礼＝朱砂底签（白事内用素灰蓝），随礼＝素蓝灰底签
Widget directionTag(String direction, {bool bai = false}) {
  final isRecv = direction == '收礼';
  final bg = isRecv ? (bai ? kBaiPrimary : kCinnabar) : kGivenTagBg;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
    child: Text(direction, style: const TextStyle(fontSize: 11, color: Colors.white, height: 1.2)),
  );
}

// 状态小签（待送出等）：描边素签
Widget outlineTag(String text, {bool bai = false}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      border: Border.all(color: bai ? kBaiPrimary : kStone),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(text, style: TextStyle(fontSize: 11, color: bai ? kBaiPrimary : kStone, height: 1.2)),
  );
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kCinnabar,
    surface: kCard,
    onSurface: kInk,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kPaper,
    appBarTheme: const AppBarTheme(
      backgroundColor: kPaper,
      foregroundColor: kInk,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(color: kInk, fontSize: 18, fontWeight: FontWeight.w600),
    ),
    cardTheme: CardTheme(
      color: kCard,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: kHairline),
      ),
    ),
    dividerTheme: const DividerThemeData(color: kHairline, thickness: 1, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kCinnabar,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kInk,
        side: const BorderSide(color: kHairline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kCinnabar,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kCard,
      indicatorColor: const Color(0xFFF3E2D8),
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kHairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kHairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kCinnabar),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? const Color(0xFFF3E2D8) : kCard,
        ),
        side: WidgetStateProperty.all(const BorderSide(color: kHairline)),
      ),
    ),
  );
}
