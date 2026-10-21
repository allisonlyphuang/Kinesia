//
//  colors.swift
//  Kinesia
//
//  Created by Allison Huang on 8/9/26.
//

import SwiftUI

// The project defaults declarations to the main actor. These are Sendable constants and the
// chart tokens read them from a nonisolated context, so they are declared nonisolated here.
nonisolated extension Color {
    // Brand
    static let primaryColor   = Color("moss")
    static let secondaryColor = Color("sage")

    // Backgrounds
    static let bgPrimaryColor   = Color("cream")
    static let bgSecondaryColor = Color("mist")

    // Text
    static let textLight   = Color("cream")
    static let textMedium = Color("sage")
    static let textDark = Color("pine")

    // Status
    static let accentBlue = Color("pond")
}

