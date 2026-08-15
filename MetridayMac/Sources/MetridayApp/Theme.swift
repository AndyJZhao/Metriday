import SwiftUI

enum MetridayTheme {
    static let accent = Color(red: 0.30, green: 0.38, blue: 0.93)
    static let accentDeep = Color(red: 0.22, green: 0.29, blue: 0.88)
    static let accentSoft = Color(red: 0.94, green: 0.95, blue: 1.00)
    static let canvas = Color(red: 0.985, green: 0.986, blue: 0.992)
    static let sidebar = Color(red: 0.975, green: 0.977, blue: 0.984)
    static let graphite = Color(red: 0.12, green: 0.13, blue: 0.16)
    static let secondary = Color(red: 0.39, green: 0.41, blue: 0.47)
    static let line = Color(red: 0.87, green: 0.88, blue: 0.91)
    static let success = Color(red: 0.22, green: 0.62, blue: 0.34)
    static let successSoft = Color(red: 0.94, green: 0.98, blue: 0.94)
    static let warning = Color(red: 0.89, green: 0.43, blue: 0.08)
    static let danger = Color(red: 0.84, green: 0.20, blue: 0.23)

    static func panelShape(radius: CGFloat = 12) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

struct PanelStyle: ViewModifier {
    var radius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .background(.white)
            .clipShape(MetridayTheme.panelShape(radius: radius))
            .overlay(MetridayTheme.panelShape(radius: radius).stroke(MetridayTheme.line, lineWidth: 1))
    }
}

extension View {
    func metridayPanel(radius: CGFloat = 12) -> some View {
        modifier(PanelStyle(radius: radius))
    }
}
