//
//  spacingTokens.swift
//  Kinesia
//
//  Created by Allison Huang on 8/9/26.
//

import CoreFoundation

struct Spacing {
    static let xxs: CGFloat = 4
    static let xs:  CGFloat = 8
    static let sm:  CGFloat = 12
    static let md:  CGFloat = 16   // base unit — most padding uses this
    static let lg:  CGFloat = 24
    static let xl:  CGFloat = 32
    static let xxl: CGFloat = 48
}

struct Radius {
    static let primary: CGFloat = 20
    static let secondary: CGFloat = 30
    static let full: CGFloat = 999  // fully rounded / pill shape
}
