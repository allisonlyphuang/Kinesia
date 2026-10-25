//
//  typographyTokens.swift
//  Kinesia
//
//  Created by Allison Huang on 8/9/26.
//

import SwiftUI

// The scale the dashboard sets, applied app-wide.
//
// Sizes come from the system text styles, so every one of these scales with
// Dynamic Type. The weights are deliberately lighter than a default iOS kit:
// the dashboard's largest text is medium rather than bold, and nothing below a
// title is heavier than semibold.
extension Font {
    // Headings
    static let displayLarge  = Font.system(.largeTitle, weight: .semibold)  // 34pt
    static let displayMedium = Font.system(.title, weight: .medium)         // 28pt — the greeting
    static let heading       = Font.system(.title3, weight: .medium)        // 20pt
    static let subheading    = Font.system(.headline)                       // 17pt semibold

    // Body
    static let body   = Font.system(.body)                                  // 17pt
    static let button = Font.system(.headline)                              // 17pt semibold
    static let label  = Font.system(.footnote, weight: .medium)             // 13pt
}

// The small all-caps heading that separates sections on the dashboard. Tracking and
// casing are part of the style, so it is a modifier rather than a Font.
struct SectionLabelStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption2)
            .fontWeight(.semibold)
            .tracking(1.6)
            .textCase(.uppercase)
    }
}

extension View {
    func sectionLabelStyle() -> some View {
        modifier(SectionLabelStyle())
    }
}
