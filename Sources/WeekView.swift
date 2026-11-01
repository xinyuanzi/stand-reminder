import SwiftUI

/// 本周回顾。一周的账，用柱子和一句判断说完。
///
/// 设计上的取舍：
/// - **只画 7 根柱子**，不做折线、不做多指标叠加。这张图的作用是「一眼看出哪天最狠」，
///   不是数据分析工具。
/// - **缺数据的那天不画柱子**，标一个「—」。没开机和坐 0 分钟是两件事，
///   把它们画成一样高，这张图就开始骗人了。
/// - **底部必须有一句判断**。光给数字，人不会改行为；「周三最狠，坐了 9 小时 20 分」
///   会。这是回顾和统计的区别。
struct WeekView: View {
    let summary: WeekSummary
    /// 本周一，用来算日期标签
    let weekStart: Date
    /// 今天的 dayKey，用来高亮
    let todayKey: String
    /// 上周总坐；nil 表示没数据
    let lastWeekTotal: Double?

    private let accent = Color(red: 0.13, green: 0.44, blue: 0.90)
    private let ink = Color(red: 0.11, green: 0.11, blue: 0.12)
    private let muted = Color(red: 0.45, green: 0.45, blue: 0.47)
    private let faint = Color(red: 0.78, green: 0.79, blue: 0.81)
    private let card = Color(red: 0.998, green: 0.996, blue: 0.990)

    private var weekdays: [String] { ["一", "二", "三", "四", "五", "六", "日"] }

    /// 柱子的归一化基准。至少 1 小时，否则「某天只坐了 10 分钟」会被拉成满格。
    private var peak: Double { max(summary.perDay.compactMap { $0?.sitSeconds }.max() ?? 0, 3600) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 18)

            numbers
                .padding(.bottom, 22)

            if summary.daysWithData == 0 {
                emptyState
            } else {
                chart
                verdict.padding(.top, 20)
            }

            Spacer(minLength: 0)
        }
        .padding(26)
        .frame(width: 460, height: 412, alignment: .topLeading)
        .background(card)
    }

    // MARK: 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("本周")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(ink)
            Text(dateRange)
                .font(.system(size: 12))
                .foregroundColor(muted)
        }
    }

    private var dateRange: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return "\(f.string(from: weekStart)) – \(f.string(from: end))"
    }

    // MARK: 三个数字

    private var numbers: some View {
        // 一天数据都没有时三个数全给「—」。写 0m 就等于说「你坐了 0 分钟」，
        // 而事实是「我们什么都没看到」——这两个意思差得很远。
        let none = summary.daysWithData == 0
        return HStack(spacing: 0) {
            stat(none ? "—" : durationText(summary.totalSit), "总坐")
            divider
            stat(none ? "—" : durationText(summary.dailyAverage), "日均")
            divider
            stat(none || summary.longestStretch <= 0 ? "—" : durationText(summary.longestStretch),
                 "最长一段")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 22, weight: .semibold).monospacedDigit())
                .foregroundColor(ink)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.06))
            .frame(width: 1, height: 34)
            .padding(.horizontal, 10)
    }

    // MARK: 柱子

    private var chart: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(0..<7, id: \.self) { i in
                bar(index: i).frame(maxWidth: .infinity)
            }
        }
        .frame(height: 156, alignment: .bottom)
    }

    private func bar(index i: Int) -> some View {
        let record = summary.perDay[i]
        let isToday = record?.dayKey == todayKey
        let ratio = record.map { min(1.0, $0.sitSeconds / peak) } ?? 0
        // 有数据但几乎为 0 时留 3pt，让人看得出「这天有记录，只是没怎么坐」
        let height = record == nil ? 0 : max(3, CGFloat(ratio) * 132)

        return VStack(spacing: 6) {
            // 柱槽固定高度、柱子贴底。不这么干的话，柱子一高一矮会把下面的
            // 星期标签和次数顶到不同高度——图上就会看到某一天的标签单独往下掉。
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if record == nil {
                    // 缺数据：一条极浅的线，明确表示「这天没记录」，不参与比较
                    RoundedRectangle(cornerRadius: 1)
                        .fill(faint.opacity(0.55))
                        .frame(height: 2)
                } else {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isToday ? accent : accent.opacity(0.28))
                        .frame(height: height)
                }
            }
            .frame(height: 132)

            Text(weekdays[i])
                .font(.system(size: 11, weight: isToday ? .semibold : .regular))
                .foregroundColor(isToday ? ink : muted)

            Text(record.map { "\($0.breaks) 次" } ?? "—")
                .font(.system(size: 10).monospacedDigit())
                .foregroundColor(record == nil ? faint : muted)
        }
        .frame(height: 176)
    }

    // MARK: 空态

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("本周还没有记录")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(ink)
            Text("这个 app 只统计它看得见的：你坐着的时间、\n以及你确实离开座位的次数。")
                .font(.system(size: 12))
                .foregroundColor(muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }

    // MARK: 判断句

    /// 这张图的落点。没有这一句，上面全是数字，人不会因此站起来。
    private var verdict: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let hardest = hardestDay {
                Text("周\(weekdays[hardest.0])最狠，坐了 \(durationText(hardest.1.sitSeconds))")
                    .font(.system(size: 13))
                    .foregroundColor(ink)
            }
            if let line = comparison {
                Text(line)
                    .font(.system(size: 12))
                    .foregroundColor(muted)
            }
        }
    }

    /// 坐得最久的那一天。只有一天有数据时不评价（没有比较对象）。
    private var hardestDay: (Int, DayRecord)? {
        let pairs = summary.perDay.enumerated().compactMap { i, r in r.map { (i, $0) } }
        guard pairs.count >= 2 else { return nil }
        return pairs.max { $0.1.sitSeconds < $1.1.sitSeconds }
    }

    private var comparison: String? {
        guard let last = lastWeekTotal, last > 0 else { return nil }
        let diff = summary.totalSit - last
        if abs(diff) < 600 { return "和上周差不多" }
        return diff > 0
            ? "比上周多坐 \(durationText(diff))"
            : "比上周少坐 \(durationText(-diff))"
    }

    // MARK: 工具

    private func durationText(_ seconds: Double) -> String {
        let m = Int(seconds / 60)
        if m < 60 { return "\(m)m" }
        let h = m / 60, r = m % 60
        return r == 0 ? "\(h)h" : "\(h)h\(r)m"
    }
}
