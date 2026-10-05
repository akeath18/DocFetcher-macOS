import Foundation
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @AppStorage("fuzzySearch") var fuzzySearch = false
    @AppStorage("ocrEnabled") var ocrEnabled = true
    @AppStorage("maxResults") var maxResults = 200
}
