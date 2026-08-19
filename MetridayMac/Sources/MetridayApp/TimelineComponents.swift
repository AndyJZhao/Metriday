import AppKit
import SwiftUI

enum TimelineMetrics {
    static let startMinute = 8 * 60
    static let endMinute = 20 * 60
    static let hourHeight: CGFloat = 64
    static let totalHeight = CGFloat((endMinute - startMinute) / 60) * hourHeight

    static func y(for minute: Int) -> CGFloat {
        CGFloat(minute - startMinute) / 60 * hourHeight
    }

    static func height(start: Int, end: Int) -> CGFloat {
        max(32, CGFloat(end - start) / 60 * hourHeight)
    }

    static func y(forSecond second: Int) -> CGFloat {
        CGFloat(second - startMinute * 60) / 3600 * hourHeight
    }

    static func height(startSecond: Int, endSecond: Int) -> CGFloat {
        max(0, CGFloat(endSecond - startSecond) / 3600 * hourHeight)
    }
}

struct TimelineGrid: View {
    var showLabels = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(8..<20, id: \.self) { hour in
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(MetridayTheme.line.opacity(0.72))
                        .frame(height: 1)
                    if showLabels {
                        Text(String(format: "%02d:00", hour))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MetridayTheme.secondary)
                            .padding(.leading, 6)
                            .padding(.top, 5)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: TimelineMetrics.hourHeight, maxHeight: TimelineMetrics.hourHeight, alignment: .topLeading)
            }
            Rectangle().fill(MetridayTheme.line.opacity(0.72)).frame(height: 1)
        }
        .frame(maxWidth: .infinity, minHeight: TimelineMetrics.totalHeight, maxHeight: TimelineMetrics.totalHeight, alignment: .top)
    }
}

struct TimelineColumnHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(subtitle).font(.system(size: 11)).foregroundStyle(MetridayTheme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .frame(height: 55)
    }
}

struct StaticTimelineBlock: View {
    let title: String
    let start: Int
    let end: Int
    var symbol = "doc.text"
    var isCurrent = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(TimeFormat.range(start: start, end: end)).font(.system(size: 11)).opacity(0.76)
            }
            Spacer()
        }
        .foregroundStyle(isCurrent ? .white : Color(red: 0.20, green: 0.23, blue: 0.42))
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(isCurrent ? MetridayTheme.accent : Color(red: 0.95, green: 0.955, blue: 1.0))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(isCurrent ? MetridayTheme.accentDeep : MetridayTheme.accent.opacity(0.17), lineWidth: 1))
        .frame(height: TimelineMetrics.height(start: start, end: end))
        .offset(y: TimelineMetrics.y(for: start))
    }
}

struct ActivityRow: View {
    let minutes: Int?
    let title: String
    let range: String
    let symbol: String?
    let bundleIdentifier: String?
    let relevance: ActivityRelevance
    let categoryColor: Color

    var body: some View {
        HStack(spacing: 9) {
            Text(minutes.map { "\($0)m" } ?? "")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(categoryColor)
                .frame(width: 40, alignment: .leading)
            AppIdentityIcon(symbol: symbol, bundleIdentifier: bundleIdentifier)
            Text(title).font(.system(size: 12, weight: .medium))
            Spacer()
            Text(range).font(.system(size: 10)).foregroundStyle(MetridayTheme.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(categoryColor.opacity(relevance == .distracted ? 0.055 : 0.035))
    }
}

private struct AppIdentityIcon: View {
    let symbol: String?
    let bundleIdentifier: String?

    private var appImage: NSImage? {
        guard let bundleIdentifier,
              !bundleIdentifier.isEmpty,
              bundleIdentifier != "com.metriday.idle",
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    var body: some View {
        Group {
            if let appImage {
                Image(nsImage: appImage)
                    .resizable()
                    .scaledToFit()
                    .padding(3)
            } else if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(MetridayTheme.graphite)
            } else {
                Color.clear
            }
        }
        .frame(width: 23, height: 23)
        .background(MetridayTheme.sidebar)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
