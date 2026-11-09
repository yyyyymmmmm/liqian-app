import Foundation

// MARK: - 金额输入文本净化（v5.14）

/// 金额输入框的文本净化：v5.14 删自绘金额键盘、改系统 decimalPad 后，
/// 旧键盘在输入侧把守的合法性约束改由本纯函数在 onChange 里承接——
/// 约束与旧键盘逐条对齐（keypadInput 旧口径）：
/// · 只留数字与至多一个小数点（粘贴进来的杂字直接滤掉）
/// · 小数至多两位；整数部分至多 7 位（¥9,999,999，现场记账足够）
/// · 整数部分不留前导零（不出现 05、00；单独一个 0 合法）
/// · 以小数点开头时补 0（"." → "0."，与旧键盘首键 "." 的行为一致）
/// 保存侧校验（Double 解析＋>0）不变，本函数只管输入形态。
public enum AmountInputText {
    public static func sanitized(_ raw: String) -> String {
        var intDigits = ""
        var fracDigits = ""
        var seenDot = false
        for ch in raw {
            if ch == "." {
                if !seenDot { seenDot = true }
            } else if ch >= "0" && ch <= "9" {
                if seenDot {
                    if fracDigits.count < 2 { fracDigits.append(ch) }
                } else {
                    intDigits.append(ch)
                }
            }
        }
        // 整数部分：去前导零（全零则留一个 0），再按 7 位封顶
        let stripped = intDigits.drop(while: { $0 == "0" })
        var intPart = stripped.isEmpty ? (intDigits.isEmpty ? "" : "0") : String(stripped)
        if intPart.count > 7 { intPart = String(intPart.prefix(7)) }
        if seenDot {
            if intPart.isEmpty { intPart = "0" }
            return intPart + "." + fracDigits
        }
        return intPart
    }
}
