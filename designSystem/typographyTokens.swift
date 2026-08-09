//
//  typographyTokens.swift
//  Kinesia
//
//  Created by Allison Huang on 8/9/26.
//

import SwiftUI

extension Font {
    // Headings
    static let displayLarge  = Font.system(size: 34, weight: .bold)
    static let displayMedium = Font.system(size: 28, weight: .bold)
    static let heading       = Font.system(size: 22, weight: .semibold)
    static let subheading    = Font.system(size: 17, weight: .semibold)

    // Body
    static let body  = Font.system(size: 17, weight: .regular)
    static let button = Font.system(size: 20, weight: .regular)
    static let label      = Font.system(size: 13, weight: .medium)
}
