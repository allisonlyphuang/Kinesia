//
//  OnboardingPDQ8.swift
//  Kinesia
//
//  Created by Amanda Hon on 8/11/26.
//


import SwiftUI

struct OnboardingPDQ8: View {
    var body: some View {
        ZStack {
            // bg
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(Color(.sRGB, red: 255/255, green: 253/255, blue: 248/255))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            VStack(alignment: .leading) {
                HStack {
                    Capsule(style: .continuous)
                        .fill(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255))
                        .frame(width: 30, height: 10)
                        .clipped()
                    Capsule(style: .continuous)
                        .stroke(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255), lineWidth: 1)
                        .background(Capsule(style: .continuous).fill(.clear))
                        .frame(width: 30, height: 10)
                    Capsule(style: .continuous)
                        .stroke(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255), lineWidth: 1)
                        .background(Capsule(style: .continuous).fill(.clear))
                        .frame(width: 30, height: 10)
                    Capsule(style: .continuous)
                        .stroke(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255), lineWidth: 1)
                        .background(Capsule(style: .continuous).fill(.clear))
                        .frame(width: 30, height: 10)
                    Capsule(style: .continuous)
                        .stroke(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255), lineWidth: 1)
                        .background(Capsule(style: .continuous).fill(.clear))
                        .frame(width: 30, height: 10)
                    Capsule(style: .continuous)
                        .stroke(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255), lineWidth: 1)
                        .background(Capsule(style: .continuous).fill(.clear))
                        .frame(width: 30, height: 10)
                    Capsule(style: .continuous)
                        .stroke(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255), lineWidth: 1)
                        .background(Capsule(style: .continuous).fill(.clear))
                        .frame(width: 30, height: 10)
                    Capsule(style: .continuous)
                        .stroke(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255), lineWidth: 1)
                        .background(Capsule(style: .continuous).fill(.clear))
                        .frame(width: 30, height: 10)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .clipped()
                // Instruction text
                VStack(alignment: .leading) {
                    Text("In the last month")
                        .font(.title2)
                        .foregroundStyle(Color(.sRGB, red: 57/255, green: 66/255, blue: 57/255))
                        .padding(.top, 0)
                    Text("Have you had difficulty getting around in public?")
                        .font(.largeTitle)
                        .foregroundStyle(Color(.sRGB, red: 57/255, green: 66/255, blue: 57/255))
                        .padding(.top, 0)
                }
                .padding()
                .frame(maxHeight: .infinity)
                .clipped()
                Spacer()
                    .frame(height: 20)
                    .clipped()
                // Answer options
                VStack {
                    // Never
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255), lineWidth: 2)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.clear))
                            .frame(height: 80)
                            .padding(5)
                        HStack {
                            Text("Never")
                                .font(.title)
                                .foregroundStyle(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255))
                        }
                    }
                    .frame(height: 80)
                    .padding(5)
                    // Occasionally
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255), lineWidth: 2)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.clear))
                            .frame(height: 80)
                            .padding(5)
                        HStack {
                            Text("Occasionally")
                                .font(.title)
                                .foregroundStyle(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255))
                        }
                    }
                    // Sometimes
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255), lineWidth: 2)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255)))
                            .frame(height: 80)
                            .padding(5)
                        HStack {
                            Text("Sometimes")
                                .font(.title)
                                .foregroundStyle(.white)
                            Spacer()
                                .frame(width: 100)
                                .clipped()
                            Image(systemName: "checkmark")
                                .imageScale(.large)
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(.white)
                                .font(.system(.body, weight: .bold))
                        }
                    }
                    // Often
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255), lineWidth: 2)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.clear))
                            .frame(height: 80)
                            .padding(5)
                        HStack {
                            Text("Often")
                                .font(.title)
                                .foregroundStyle(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255))
                        }
                    }
                    // Always
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255), lineWidth: 2)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.clear))
                            .frame(height: 80)
                            .padding(5)
                        HStack {
                            Text("Always")
                                .font(.title)
                                .foregroundStyle(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255))
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .padding(12)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .padding(20)
        }
    }
}



#Preview {
    OnboardingPDQ8()
}
