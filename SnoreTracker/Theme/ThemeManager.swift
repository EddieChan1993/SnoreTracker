import SwiftUI
import Combine

class ThemeManager: ObservableObject {

    @AppStorage("selectedThemeID") var selectedThemeID: String = "dark" {
        didSet { objectWillChange.send() }
    }

    var current: AppTheme {
        AppTheme.all.first { $0.id == selectedThemeID } ?? .dark
    }

    func select(_ theme: AppTheme) {
        selectedThemeID = theme.id
    }
}
