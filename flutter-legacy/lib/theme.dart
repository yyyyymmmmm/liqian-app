import 'dart:ui';
import 'package:flutter/material.dart';

// 「现代礼簿」设计系统（docs/DESIGN.md）：
// 内容层＝米纸底、墨字、朱砂红、描金细线、衬线标题（礼簿身份）；
// 外壳层＝ iOS 26 Liquid Glass：悬浮玻璃胶囊栏、玻璃顶栏、大圆角、全胶囊按钮。
// Flutter 无系统级材质，用 BackdropFilter 模糊 + 半透明 + 高光描边高保真模拟。

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

// —— iOS 26 外壳口径 ——
const double kRadiusCard = 18; // 主表面大圆角
const double kRadiusCover = 20; // 礼簿封面卡圆角
const double kGlassBlur = 18; // 玻璃模糊强度

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

// 无阴影卡面容器：卡面色 + 1px 描边 + 大圆角（iOS 26 外壳口径 18）
BoxDecoration flatCard(
    {bool bai = false, Color? color, double radius = kRadiusCard}) {
  return BoxDecoration(
    color: color ?? (bai ? kBaiCard : kCard),
    border: Border.all(color: bai ? kBaiLine : kHairline),
    borderRadius: BorderRadius.circular(radius),
  );
}

// —— Liquid Glass 胶囊 ——
// 半透明卡面色 + 背景模糊 + 1px 半透明白高光描边（顶部镜面感靠描边+内顶线）+ 轻投影。
// 外层 Container 只负责投影（不裁剪），内层 ClipRRect 裁剪后做 BackdropFilter。
class GlassCapsule extends StatelessWidget {
  final Widget child;
  final bool bai;
  final double radius;
  final EdgeInsetsGeometry? padding;
  const GlassCapsule(
      {super.key,
      required this.child,
      this.bai = false,
      this.radius = 30,
      this.padding});

  @override
  Widget build(BuildContext context) {
    final surface =
        (bai ? kBaiCard : kCard).withOpacity(bai ? 0.68 : 0.72);
    final edge = Colors.white.withOpacity(bai ? 0.5 : 0.65);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.13),
              blurRadius: 24,
              offset: const Offset(0, 10)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: kGlassBlur, sigmaY: kGlassBlur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: edge, width: 1),
            ),
            child: Stack(
              children: [
                child,
                // 顶部 1px 高光线：模拟玻璃镜面边缘
                Positioned(
                  top: 0,
                  left: 18,
                  right: 18,
                  child: Container(
                      height: 1, color: Colors.white.withOpacity(0.45)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// —— 玻璃顶栏 ——
// 透明 AppBar + flexibleSpace 模糊层；配合页面 extendBodyBehindAppBar: true，
// 滚动内容从栏下穿过。主 Tab 页可不给 title（页面内另有大标题）。
PreferredSizeWidget glassAppBar({
  String? title,
  List<Widget>? actions,
  Widget? leading,
  bool bai = false,
  Color? foreground,
}) {
  return AppBar(
    title: title == null ? null : Text(title),
    actions: actions,
    leading: leading,
    backgroundColor: Colors.transparent,
    foregroundColor: foreground ?? (bai ? kBaiInk : kInk),
    elevation: 0,
    scrolledUnderElevation: 0,
    flexibleSpace: ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: (bai ? kBaiCard : kCard).withOpacity(0.6),
            border: Border(
              bottom: BorderSide(
                  color: (bai ? kBaiLine : kHairline).withOpacity(0.85)),
            ),
          ),
        ),
      ),
    ),
  );
}

// 玻璃顶栏占位高度：状态栏 + 工具栏 + 一点呼吸
double glassTopPad(BuildContext context) =>
    MediaQuery.paddingOf(context).top + kToolbarHeight + 10;

// —— 页面大标题（iOS 26 大标题排版，衬线 28） ——
Widget bigTitle(String text, {bool bai = false}) {
  return Text(
    text,
    style: serifStyle(fontSize: 28, color: bai ? kBaiInk : kInk, height: 1.2),
  );
}

// 方向签：收礼＝朱砂底签（白事内用素灰蓝），随礼＝素蓝灰底签
Widget directionTag(String direction, {bool bai = false}) {
  final isRecv = direction == '收礼';
  final bg = isRecv ? (bai ? kBaiPrimary : kCinnabar) : kGivenTagBg;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration:
        BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
    child: Text(direction,
        style: const TextStyle(fontSize: 11, color: Colors.white, height: 1.2)),
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
    child: Text(text,
        style: TextStyle(
            fontSize: 11, color: bai ? kBaiPrimary : kStone, height: 1.2)),
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
      titleTextStyle:
          TextStyle(color: kInk, fontSize: 18, fontWeight: FontWeight.w600),
    ),
    cardTheme: CardTheme(
      color: kCard,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusCard),
        side: const BorderSide(color: kHairline),
      ),
    ),
    dividerTheme:
        const DividerThemeData(color: kHairline, thickness: 1, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kCinnabar,
        foregroundColor: Colors.white,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kCinnabar,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kInk,
        side: const BorderSide(color: kHairline),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: const StadiumBorder()),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      // 朱砂 0.92 alpha 半透明 + 胶囊形，近似玻璃感（无模糊，实色近似可接受）
      backgroundColor: kCinnabar.withOpacity(0.92),
      foregroundColor: Colors.white,
      elevation: 3,
      shape: const StadiumBorder(),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: kHairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: kHairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: kCinnabar),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? const Color(0xFFF3E2D8)
              : kCard,
        ),
        side: WidgetStateProperty.all(const BorderSide(color: kHairline)),
      ),
    ),
  );
}
