import SwiftUI

enum Palette {
    static let background = Color(red: 0.063, green: 0.082, blue: 0.078)
    static let sidebar = Color(red: 0.082, green: 0.105, blue: 0.098)
    static let panel = Color(red: 0.105, green: 0.129, blue: 0.122)
    static let line = Color.white.opacity(0.075)
    static let muted = Color(red: 0.59, green: 0.65, blue: 0.62)
    static let mint = Color(red: 0.72, green: 0.91, blue: 0.64)
    static let blue = Color(red: 0.57, green: 0.72, blue: 0.92)
    static let amber = Color(red: 0.92, green: 0.73, blue: 0.45)
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Palette.background)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(Palette.mint.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 10))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Color.white.opacity(configuration.isPressed ? 0.10 : 0.045), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.line))
    }
}

extension View {
    func panel() -> some View {
        background(Palette.panel, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line))
    }
}
