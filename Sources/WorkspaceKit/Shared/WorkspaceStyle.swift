import AppKit
import SwiftUI

enum WorkspaceStyle {
  static let accent = adaptive(light: 0x137B76, dark: 0x6AD5C5)
  static let background = adaptive(light: 0xF4F3EF, dark: 0x181D24)
  static let surface = adaptive(light: 0xFFFFFF, dark: 0x222A34)
  static let inset = adaptive(light: 0xECEFEA, dark: 0x2B3540)
  static let ink = adaptive(light: 0x1B3044, dark: 0xE5EDF3)
  static let secondary = adaptive(light: 0x526373, dark: 0xB0BFCC)
  static let border = adaptive(light: 0xDCE1E0, dark: 0x3B4652)

  private static func adaptive(light: UInt32, dark: UInt32) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        return NSColor(
          red: CGFloat((value >> 16) & 255) / 255,
          green: CGFloat((value >> 8) & 255) / 255,
          blue: CGFloat(value & 255) / 255, alpha: 1
        )
      })
  }
}

struct PreviewBadge: View {
  var text = "Sample"
  var body: some View {
    Text(text).font(.system(size: 10, weight: .semibold))
      .foregroundStyle(WorkspaceStyle.secondary)
      .padding(.horizontal, 7).padding(.vertical, 4)
      .background(WorkspaceStyle.inset, in: Capsule())
  }
}

struct PlannedButton: View {
  let title: String
  let systemImage: String
  var body: some View {
    Button {
    } label: {
      Label(title, systemImage: systemImage)
    }
    .disabled(true)
    .help("\(title) is planned for a later milestone.")
    .accessibilityLabel("\(title), planned")
  }
}

extension View {
  func workspaceCard() -> some View {
    self.padding(16)
      .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(WorkspaceStyle.border, lineWidth: 1))
  }
}
