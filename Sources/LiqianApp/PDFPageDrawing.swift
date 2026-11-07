import Foundation
import UIKit

/// 成书类 PDF 的共享绘制助手（v5）：印刷版礼谱与家族汇册的新页型共用。
/// 色值与 GiftBookPDF 的印刷色板同源同值（PDF 是留存物，只用浅色定版，
/// 不读 App 主题）；GiftBookPDF 内部色是 private，这里按同值复刻并注明。
enum PDFPageDrawing {
    static let paper = uiColor(0xFAF9F6)
    static let ink = uiColor(0x262520)
    static let stone = uiColor(0x6F6C64)
    static let cinnabar = uiColor(0xA62B1F)
    static let cinnabarDeep = uiColor(0x8E241B)
    static let baiPaper = uiColor(0xECEEF0)
    static let baiInk = uiColor(0x33383B)
    static let baiDeep = uiColor(0x47525A)

    static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    static func fillPage(_ rect: CGRect, bai: Bool, in cg: CGContext) {
        cg.setFillColor((bai ? baiPaper : paper).cgColor)
        cg.fill(rect)
    }

    /// 版框（汇册自制页口径）：红事朱砂双线、白事素蓝单线，与礼谱版框同族
    static func drawFrame(in rect: CGRect, bai: Bool, cg: CGContext) {
        let outer = rect.insetBy(dx: 48, dy: 55)
        let color = bai ? baiDeep : cinnabar
        cg.setStrokeColor(color.cgColor)
        cg.setLineWidth(bai ? 1 : 1.6)
        cg.stroke(outer)
        if !bai {
            cg.setLineWidth(0.6)
            cg.stroke(outer.insetBy(dx: 5, dy: 5))
        }
    }

    /// 楷体（与 GiftBookPDF 同口径的字体回退链）
    static func kaiti(size: CGFloat, bold: Bool = true) -> UIFont {
        for name in ["Kaiti SC", "STKaiti"] {
            if let font = UIFont(name: name, size: size) { return font }
        }
        return UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    /// 竖排文字：逐字自上而下堆叠（礼谱成品口径，衬线）
    static func drawVerticalText(
        _ text: String, centerX: CGFloat, topY: CGFloat,
        fontSize: CGFloat, color: UIColor, cg: CGContext, bold: Bool = true
    ) {
        let font = kaiti(size: fontSize, bold: bold)
        var y = topY
        for ch in text {
            let s = NSAttributedString(
                string: String(ch),
                attributes: [.font: font, .foregroundColor: color]
            )
            let size = s.size()
            s.draw(at: CGPoint(x: centerX - size.width / 2, y: y))
            y += fontSize * 1.18
        }
    }

    /// 横排段落（印刷参数页等说明性页面用系统字，不上衬线题字口径）
    static func drawParagraph(
        _ text: String, in rect: CGRect,
        fontSize: CGFloat, color: UIColor, bold: Bool = false, lineSpacing: CGFloat = 6,
        alignment: NSTextAlignment = .left, serif: Bool = false
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.alignment = alignment
        let font = serif
            ? kaiti(size: fontSize, bold: bold)
            : UIFont.systemFont(ofSize: fontSize, weight: bold ? .bold : .regular)
        let s = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph,
            ]
        )
        s.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }

    /// 方印：朱砂（白事素蓝）圆角方印＋白字衬线单字，与 App 内印章同造型
    static func drawSeal(char: String, center: CGPoint, size: CGFloat, bai: Bool, cg: CGContext) {
        let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: size * 0.14)
        (bai ? baiDeep : cinnabar).setFill()
        path.fill()
        let font = kaiti(size: size * 0.58)
        let s = NSAttributedString(
            string: char,
            attributes: [.font: font, .foregroundColor: UIColor.white]
        )
        let textSize = s.size()
        s.draw(at: CGPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2))
    }
}
