//
//  OnboardingMeds.swift
//  Kinesia
//
//  Created by Amanda Hon on 8/11/26.
//


import SwiftUI

struct OnboardingMeds: View {
    var body: some View {
        ZStack {
            // bg
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(Color(.sRGB, red: 255/255, green: 253/255, blue: 248/255))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            VStack(alignment: .leading) {
                // Instruction text
                VStack(alignment: .leading) {
                    Text("When do you take your medication?")
                        .font(.largeTitle)
                        .foregroundStyle(Color(.sRGB, red: 57/255, green: 66/255, blue: 57/255))
                        .padding(.top, 12)
                    Text("You can change this later.")
                        .font(.title2)
                        .foregroundStyle(Color(.sRGB, red: 57/255, green: 66/255, blue: 57/255))
                        .padding(.top, 0)
                }
                .padding()
                Spacer()
                    .frame(height: 20)
                    .clipped()
                // Medication times
                VStack {
                    // Medication time option
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color(.sRGB, red: 168/255, green: 179/255, blue: 160/255), lineWidth: 2)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white))
                            .frame(height: 90)
                            .padding(12)
                        HStack {
                            Image(systemName: "drop")
                                .imageScale(.large)
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(Color(.sRGB, red: 57/255, green: 66/255, blue: 57/255))
                            Spacer()
                                .frame(width: 30, height: 1)
                                .clipped()
                            Text("8:00 AM")
                                .font(.title)
                                .foregroundStyle(Color(.sRGB, red: 57/255, green: 66/255, blue: 57/255))
                            Spacer()
                                .frame(width: 100, height: 1)
                                .clipped()
                            Image(systemName: "xmark")
                                .imageScale(.large)
                                .symbolRenderingMode(.monochrome)
                                .font(.system(size: 24, weight: .regular, design: .default))
                                .foregroundStyle(Color(.sRGB, red: 168/255, green: 179/255, blue: 160/255))
                        }
                    }
                    // Medication time option
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color(.sRGB, red: 168/255, green: 179/255, blue: 160/255), lineWidth: 2)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white))
                            .frame(height: 90)
                            .padding(12)
                        HStack {
                            Image(systemName: "drop")
                                .imageScale(.large)
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(Color(.sRGB, red: 57/255, green: 66/255, blue: 57/255))
                            Spacer()
                                .frame(width: 30, height: 1)
                                .clipped()
                            Text("1:00 PM")
                                .font(.title)
                                .foregroundStyle(Color(.sRGB, red: 57/255, green: 66/255, blue: 57/255))
                            Spacer()
                                .frame(width: 100, height: 1)
                                .clipped()
                            Image(systemName: "xmark")
                                .imageScale(.large)
                                .symbolRenderingMode(.monochrome)
                                .font(.system(size: 24, weight: .regular, design: .default))
                                .foregroundStyle(Color(.sRGB, red: 168/255, green: 179/255, blue: 160/255))
                        }
                    }
                    // Medication time option
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color(.sRGB, red: 168/255, green: 179/255, blue: 160/255), lineWidth: 2)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white))
                            .frame(height: 90)
                            .padding(12)
                        HStack {
                            Image(systemName: "drop")
                                .imageScale(.large)
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(Color(.sRGB, red: 57/255, green: 66/255, blue: 57/255))
                            Spacer()
                                .frame(width: 30, height: 1)
                                .clipped()
                            Text("8:00 AM")
                                .font(.title)
                                .foregroundStyle(Color(.sRGB, red: 57/255, green: 66/255, blue: 57/255))
                            Spacer()
                                .frame(width: 100, height: 1)
                                .clipped()
                            Image(systemName: "xmark")
                                .imageScale(.large)
                                .symbolRenderingMode(.monochrome)
                                .font(.system(size: 24, weight: .regular, design: .default))
                                .foregroundStyle(Color(.sRGB, red: 168/255, green: 179/255, blue: 160/255))
                        }
                    }
                    // Medication time option
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color(.sRGB, red: 163/255, green: 184/255, blue: 160/255), lineWidth: 1)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.clear))
                            .frame(height: 90)
                            .padding(12)
                        HStack {
                            Image(systemName: "plus")
                                .imageScale(.large)
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255))
                            Text("Add a time")
                                .font(.title)
                                .foregroundStyle(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255))
                        }
                    }
                }
                Spacer()
                ZStack {
                    Capsule(style: .continuous)
                        .fill(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255))
                        .frame(height: 100)
                        .clipped()
                    Text("Continue")
                        .font(.title)
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .padding(20)
        }
    }
}



#Preview {
    OnboardingMeds()
}
