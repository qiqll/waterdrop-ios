import SwiftUI

// MARK: - WaterDrop Design System Colors
// Pixel-perfect match with Android colors.xml

enum AppColors {
    // MARK: Primary Palette
    static let primary = Color(hex: "5B7E6B")              // Mist Pine Green
    static let primaryVariant = Color(hex: "476256")        // Deep Pine Green (pressed)
    static let primaryLight = Color(hex: "E8F0EB")          // Mint Mist (subtle bg)
    static let onPrimary = Color.white

    // MARK: Secondary Palette
    static let secondary = Color(hex: "C4A882")             // Warm Sand Gold
    static let secondaryVariant = Color(hex: "A68B6A")      // Deep Sand Gold
    static let onSecondary = Color.white

    // MARK: Accent (FAB only)
    static let accent = Color(hex: "E8A87C")                // Apricot - FAB button
    static let accentVariant = Color(hex: "D4956B")         // Deep Apricot (pressed)
    static let onAccent = Color.white

    // MARK: Semantic Colors
    static let semanticSuccess = Color(hex: "5B9A6B")
    static let semanticWarning = Color(hex: "E5A84B")
    static let semanticError = Color(hex: "C75450")
    static let semanticInfo = Color(hex: "5B8EC7")
    static let semanticSuccessBg = Color(hex: "EDF5EF")
    static let semanticWarningBg = Color(hex: "FDF5E6")
    static let semanticErrorBg = Color(hex: "FAEDEC")
    static let semanticInfoBg = Color(hex: "EDF2F9")

    // MARK: Neutral Palette (warm gray, 10 steps)
    static let neutral0 = Color.white                       // Pure white
    static let neutral50 = Color(hex: "FAFAF8")             // Page background
    static let neutral100 = Color(hex: "F5F3F0")            // Subtle area bg
    static let neutral200 = Color(hex: "E8E5E1")            // Border, divider
    static let neutral300 = Color(hex: "D4D0CB")            // Disabled bg
    static let neutral400 = Color(hex: "B0ABA4")            // Placeholder text
    static let neutral500 = Color(hex: "8A847D")            // Secondary icon
    static let neutral600 = Color(hex: "6B665F")            // Secondary text
    static let neutral700 = Color(hex: "4A4640")            // Subtitle text
    static let neutral800 = Color(hex: "2D2A26")            // Primary text
    static let neutral900 = Color(hex: "1A1816")            // Deepest, rare use

    // MARK: Surface & Background
    static let background = Color(hex: "FAFAF8")            // Page background
    static let surface = Color.white                         // Card / sheet
    static let surfaceVariant = Color(hex: "F5F3F0")        // Input field bg
    static let divider = Color(hex: "E8E5E1")               // Same as neutral200

    // MARK: Recording State
    static let recordingActive = Color(hex: "C75450")       // FAB when recording
    static let recordingPulse = Color(hex: "C75450").opacity(0.2) // 20% opacity pulse ring
}
