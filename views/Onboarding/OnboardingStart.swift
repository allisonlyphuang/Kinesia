//
//  OnboardingStart.swift
//  Kinesia
//
//  Created by Amanda Hon on 8/11/26.
//

import SwiftUI

struct OnboardingStart: View {
    var body: some View {
        VStack {
            Text("Kinesia")
                .font(.system(size: 54, weight: .regular, design: .serif))
                .foregroundStyle(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255))
            Text("A calm daily check-in that helps you and your care team make decisions, smarter.")
                .multilineTextAlignment(.center)
                .padding(.horizontal, 60)
                .padding(.top, 0)
                .foregroundStyle(Color(.sRGB, red: 57/255, green: 66/255, blue: 57/255))
            ZStack {
                Capsule(style: .continuous)
                    .fill(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255))
                Text("Get started")
                    .font(.system(.title, weight: .light))
                    .foregroundStyle(.white)
            }
            .frame(height: 100)
            .clipped()
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .background {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(.sRGB, red: 255/255, green: 253/255, blue: 248/255))
        }
    }
}



#Preview {
    OnboardingStart()
}
