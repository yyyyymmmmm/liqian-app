import XCTest
import PDFKit
import UIKit
@testable import LiqianCore

// MARK: - 印刷版装配口径（v5.11.5：封面重复修复＋補記页新口径）
//
// 这条 bug 是「代码看着对、产物才露馅」型：v5.11.4 及之前印刷版装配
// 循环从屏幕版第 0 页起全嵌，封面在展开图之外又原样出现一遍。本组
// 测试在三个层面钉死防回归：
//  ① 计划层：PrintBookSpec 是装配取页的唯一事实源（App 装配循环、
//     参数页内页数、书脊估算全消费它），在此断言取页不含封面、
//     页数口径一致；
//  ② 产物层：离线合成一份多页 PDF（每页纯色指纹，末页充補記页），
//     按与生产相同的装配计划（展开图占位＋内页嵌回＋参数页占位）
//     拼出印刷版，再逐页比对像素指纹——总页数对、第二页起无封面
//     指纹、内页顺序与源一致、補記指纹落在内页末位（参数页之前）。
//     生产装配的内页嵌回本身就是栅格化嵌回，模拟与生产同构；展开
//     图与参数页的绘制在 App target、测面够不着，以占位页替，断言
//     只落在内页序列这一回归病灶上；
//  ③ 源码守卫层：GiftBookPDF 的页序与補記开关在 App target、
//     LiqianCoreTests 不链 App 渲染不了，用调用序列守卫钉住——
//     封面只调用一次、補記调用被 includesSupplement 条件包住且位
//     于答谢之后祝福索引之前、各导出调用点显式传对开关。守卫读
//     不到源码文件时跳过并留痕（CI 日志须见本组用例 executed）。
final class PrintBookAssemblyTests: XCTestCase {

    // MARK: ① 计划层

    func testInteriorIndicesSkipCoverPage() {
        for count in [2, 3, 5, 9, 40] {
            let indices = PrintBookSpec.interiorSourceIndices(sourcePageCount: count)
            XCTAssertEqual(indices, Array(1..<count), "源 \(count) 页时内页应为 1..<\(count)")
            XCTAssertFalse(indices.contains(0), "封面页（第 0 页）绝不可再进内页")
            XCTAssertEqual(indices.count, count - 1)
        }
        XCTAssertEqual(PrintBookSpec.interiorSourceIndices(sourcePageCount: 0), [])
        XCTAssertEqual(PrintBookSpec.interiorSourceIndices(sourcePageCount: 1), [])
    }

    func testInteriorAndAssembledPageCounts() {
        XCTAssertEqual(PrintBookSpec.interiorPageCount(sourcePageCount: 0), 0)
        XCTAssertEqual(PrintBookSpec.interiorPageCount(sourcePageCount: 1), 0)
        XCTAssertEqual(PrintBookSpec.interiorPageCount(sourcePageCount: 2), 1)
        XCTAssertEqual(PrintBookSpec.interiorPageCount(sourcePageCount: 9), 8)
        // 印刷版总页数＝展开图 1＋内页（源页数−1）＋参数页 1
        XCTAssertEqual(PrintBookSpec.assembledPageCount(sourcePageCount: 0), 0)
        XCTAssertEqual(PrintBookSpec.assembledPageCount(sourcePageCount: 1), 2)
        XCTAssertEqual(PrintBookSpec.assembledPageCount(sourcePageCount: 9), 10)
        // 书脊估算随内页口径：同源页数下按内页计必比按全页数计更薄
        let byInterior = PrintBookSpec.spineWidthMM(
            pageCount: PrintBookSpec.interiorPageCount(sourcePageCount: 60)
        )
        let byFull = PrintBookSpec.spineWidthMM(pageCount: 60)
        XCTAssertLessThan(byInterior, byFull)
    }

    // MARK: ② 产物层（合成 PDF 指纹）

    private let pageSize = CGSize(width: 300, height: 424)

    private func solidPDFData(colors: [UIColor]) -> Data {
        let bounds = CGRect(origin: .zero, size: pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { context in
            for color in colors {
                context.beginPage()
                color.setFill()
                UIRectFill(bounds)
            }
        }
    }

    private func averageRGB(of page: PDFPage) -> (r: Double, g: Double, b: Double) {
        let thumb = page.thumbnail(of: CGSize(width: 40, height: 56), for: .mediaBox)
        var pixel: [UInt8] = [0, 0, 0, 0]
        let ctx = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        if let ctx, let cg = thumb.cgImage {
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return (Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
    }

    private func assertColor(
        _ actual: (r: Double, g: Double, b: Double),
        closeTo expected: (r: Double, g: Double, b: Double),
        _ message: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.r, expected.r, accuracy: 0.15, "\(message)（R）", file: file, line: line)
        XCTAssertEqual(actual.g, expected.g, accuracy: 0.15, "\(message)（G）", file: file, line: line)
        XCTAssertEqual(actual.b, expected.b, accuracy: 0.15, "\(message)（B）", file: file, line: line)
    }

    func testAssembledPrintPDFCoverOnceSupplementLastInterior() throws {
        // 源谱 5 页：第 0 页封面（纯红指纹）＋3 页内容＋末页補記（紫指纹）
        let cover: (r: Double, g: Double, b: Double) = (1, 0, 0)
        let green: (r: Double, g: Double, b: Double) = (0, 0.75, 0)
        let blue: (r: Double, g: Double, b: Double) = (0, 0, 1)
        let orange: (r: Double, g: Double, b: Double) = (1, 0.6, 0)
        let supplement: (r: Double, g: Double, b: Double) = (0.6, 0, 0.8)
        let sourceData = solidPDFData(colors: [
            UIColor(red: 1, green: 0, blue: 0, alpha: 1),
            UIColor(red: 0, green: 0.75, blue: 0, alpha: 1),
            UIColor(red: 0, green: 0, blue: 1, alpha: 1),
            UIColor(red: 1, green: 0.6, blue: 0, alpha: 1),
            UIColor(red: 0.6, green: 0, blue: 0.8, alpha: 1),
        ])
        let source = try XCTUnwrap(PDFDocument(data: sourceData))
        XCTAssertEqual(source.pageCount, 5)

        // 按生产同构装配：展开图占位（白）＋计划内页逐页栅格化嵌回＋参数页占位（白）
        let bounds = CGRect(origin: .zero, size: pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let assembledData = renderer.pdfData { context in
            context.beginPage()
            UIColor.white.setFill()
            UIRectFill(bounds)
            for index in PrintBookSpec.interiorSourceIndices(sourcePageCount: source.pageCount) {
                guard let page = source.page(at: index) else { continue }
                context.beginPage()
                page.thumbnail(of: pageSize, for: .mediaBox).draw(in: bounds)
            }
            context.beginPage()
            UIColor.white.setFill()
            UIRectFill(bounds)
        }
        let assembled = try XCTUnwrap(PDFDocument(data: assembledData))

        // 总页数＝展开图 1＋内页（5−1）＋参数页 1
        XCTAssertEqual(
            assembled.pageCount,
            PrintBookSpec.assembledPageCount(sourcePageCount: source.pageCount)
        )
        XCTAssertEqual(assembled.pageCount, 6)

        let fingerprints = (0..<assembled.pageCount).map { averageRGB(of: assembled.page(at: $0)!) }
        // 第二页起（下标 ≥1）任何一页都不许再出现封面指纹
        for i in 1..<assembled.pageCount {
            let f = fingerprints[i]
            let l1 = abs(f.r - cover.r) + abs(f.g - cover.g) + abs(f.b - cover.b)
            XCTAssertGreaterThan(l1, 0.45, "装配后第 \(i + 1) 页不应是封面（指纹与封面过近）")
        }
        // 内页顺序与源 1…4 页逐页对应
        assertColor(fingerprints[1], closeTo: green, "内页首页应为源第 1 页")
        assertColor(fingerprints[2], closeTo: blue, "内页第 2 页应为源第 2 页")
        assertColor(fingerprints[3], closeTo: orange, "内页第 3 页应为源第 3 页")
        // 補記（源末页）落在内页末位：参数页（末页）之前一页
        assertColor(fingerprints[assembled.pageCount - 2], closeTo: supplement, "補記应落在内页末位、参数页之前")
    }

    // MARK: ③ 源码守卫层

    private func repoSource(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("仓库源码不在预期路径，守卫跳过：\(relative)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testPrintAssemblyConsumesPlanAndSkipsCover() throws {
        let printSource = try repoSource("Sources/LiqianApp/GiftBookPrintPDF.swift")
        XCTAssertTrue(
            printSource.contains("interiorSourceIndices(sourcePageCount:"),
            "印刷装配循环必须走 PrintBookSpec 取页计划"
        )
        XCTAssertFalse(
            printSource.contains("0..<doc.pageCount"),
            "装配循环不许再从第 0 页（封面）起全嵌"
        )
        XCTAssertTrue(
            printSource.contains("interiorPageCount(sourcePageCount:"),
            "参数页内页数必须走 PrintBookSpec 内页口径"
        )
        let exportView = try repoSource("Sources/LiqianApp/LibuExportView.swift")
        XCTAssertTrue(
            exportView.contains("interiorPageCount(sourcePageCount:"),
            "书脊估算页数必须与参数页同口径（内页数）"
        )
    }

    func testBasePDFPageOrderAndSupplementSwitch() throws {
        let book = try repoSource("Sources/LiqianApp/GiftBookPDF.swift")
        let start = try XCTUnwrap(book.range(of: "static func makePDF")?.lowerBound)
        let end = try XCTUnwrap(book.range(of: "/// 落款显示名")?.lowerBound)
        let window = String(book[start..<end])

        // 封面在 makePDF 内只生成一次；页序：封面 → 答谢 → 補記 → 祝福索引
        XCTAssertEqual(window.components(separatedBy: "drawCover(").count - 1, 1, "基础版封面只能出现一次")
        let coverPos = try XCTUnwrap(window.range(of: "drawCover(")?.lowerBound)
        let thanksPos = try XCTUnwrap(window.range(of: "drawThanksPage(")?.lowerBound)
        let supplementPos = try XCTUnwrap(window.range(of: "drawSupplementPage(context")?.lowerBound)
        let blessingPos = try XCTUnwrap(window.range(of: "drawBlessingIndexPages(")?.lowerBound)
        XCTAssertLessThan(coverPos, thanksPos)
        XCTAssertLessThan(thanksPos, supplementPos)
        XCTAssertLessThan(supplementPos, blessingPos, "補記之后只许是祝福索引（末页为補記或索引）")

        // 補記调用必须被 includesSupplement 条件包住：条件出现在调用之前近旁
        let switchPos = try XCTUnwrap(window.range(of: "if includesSupplement")?.lowerBound)
        XCTAssertLessThan(switchPos, supplementPos, "補記必须按 includesSupplement 开关条件生成")
    }

    func testSupplementSwitchAtCallSites() throws {
        // 屏幕导出（导出页生成）不带、印刷源谱带、纪念版与汇册不带
        let exportView = try repoSource("Sources/LiqianApp/LibuExportView.swift")
        XCTAssertTrue(exportView.contains("includesSupplement: false"), "屏幕版生成必须传不带補記")
        XCTAssertTrue(exportView.contains("includesSupplement: true"), "印刷源谱生成必须传带補記")
        let handover = try repoSource("Sources/LiqianApp/HandoverView.swift")
        XCTAssertTrue(handover.contains("includesSupplement: false"), "纪念版必须传不带補記")
        let album = try repoSource("Sources/LiqianApp/FamilyAlbumPDF.swift")
        XCTAssertTrue(album.contains("includesSupplement: false"), "汇册各簿（屏幕管线）必须传不带補記")
    }
}
