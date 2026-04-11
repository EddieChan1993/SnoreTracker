import SwiftUI

// MARK: - AppTheme

struct AppTheme: Identifiable, Equatable {
    let id: String
    let displayName: String
    let sfIcon: String

    // ── Backgrounds ──
    let bgColors: [Color]           // 正常状态
    let bgSnoringColors: [Color]    // 呼噜中状态

    // ── Accents ──
    let accent: Color               // 主强调色（默认蓝 / 果冻粉）
    let accentLight: Color          // 次强调色（浅蓝 / 薄荷绿）
    let snoringAccent: Color        // 呼噜状态色（橙 / 珊瑚红）
    let liveIndicator: Color        // 后台监测绿点色

    // ── Tab Bar ──
    let tabBarBackground: UIColor

    // ── Cards ──
    let cardOpacity: Double

    // MARK: - 主题预设

    static let dark = AppTheme(
        id: "dark",
        displayName: "深夜星空",
        sfIcon: "moon.stars.fill",
        bgColors: [
            Color(hex: "0A0F1E"),
            Color(hex: "111827"),
            Color(hex: "0A0F1E")
        ],
        bgSnoringColors: [
            Color(hex: "1A0D00"),
            Color(hex: "2A1500"),
            Color(hex: "1A0D00")
        ],
        accent:         Color(hex: "6B9FFF"),
        accentLight:    Color(hex: "A8C8FF"),
        snoringAccent:  .orange,
        liveIndicator:  Color(hex: "4CAF50"),
        tabBarBackground: UIColor(red: 0.06, green: 0.08, blue: 0.15, alpha: 1),
        cardOpacity: 0.07
    )

    static let fruitJelly = AppTheme(
        id: "fruitJelly",
        displayName: "水果果冻",
        sfIcon: "leaf.circle.fill",
        bgColors: [
            Color(hex: "100024"),
            Color(hex: "1C0038"),
            Color(hex: "100024")
        ],
        bgSnoringColors: [
            Color(hex: "2C001A"),
            Color(hex: "3E002A"),
            Color(hex: "2C001A")
        ],
        accent:         Color(hex: "FF6EC7"),   // 草莓粉
        accentLight:    Color(hex: "00E5B0"),   // 猕猴桃薄荷
        snoringAccent:  Color(hex: "FF9F43"),   // 芒果橙
        liveIndicator:  Color(hex: "A8FF3E"),   // 青柠绿
        tabBarBackground: UIColor(red: 0.07, green: 0.00, blue: 0.15, alpha: 1),
        cardOpacity: 0.09
    )

    static let all: [AppTheme] = [.dark, .fruitJelly]
}
