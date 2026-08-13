//
//  typographyTokens.swift
//  Kinesia
//
//  Created by Allison Huang on 8/9/26.
//

import SwiftUI

extension Font {
    // Headings
    static let displayLarge  = Font.system(.largeTitle, weight: .bold)    // 34pt
    static let displayMedium = Font.system(.title, weight: .bold)         // 28pt
    static let heading       = Font.system(.title2, weight: .semibold)    // 22pt
    static let subheading    = Font.system(.headline)                     // 17pt semibold

    // Body
    static let body   = Font.system(.body)                                // 17pt
    static let button = Font.system(.title3)                              // 20pt
    static let label  = Font.system(.footnote, weight: .medium)           // 13pt
}
