//
//  MedicationLogView.swift
//  Kinesia
//
//  Created by Amanda Hon on 8/11/26.
//


import SwiftUI

struct MedicationLogView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(.sRGB, red: 255/255, green: 253/255, blue: 248/255))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            VStack(alignment: .leading, spacing: 10) {
                // Instruction text
                VStack(alignment: .leading) {
                    Text("Log medication")
                        .font(.system(size: 40, weight: .semibold, design: .default))
                        .foregroundStyle(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255))
                    Text("Monday, January 1")
                        .font(.title)
                        .foregroundStyle(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255))
                }
                .padding()
                .padding(.vertical)
                // Medication options
                VStack {
                    HStack {
                        Image(systemName: "drop")
                            .imageScale(.large)
                            .symbolRenderingMode(.monochrome)
                        Text("8:00 AM")
                            .font(.title2)
                            .foregroundStyle(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255))
                        Spacer()
                            .frame(width: 130)
                            .clipped()
                        Image(systemName: "checkmark.circle")
                            .imageScale(.large)
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255))
                            .font(.system(size: 22, weight: .bold, design: .default))
                    }
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .padding(.horizontal)
                    Divider()
                        .frame(maxWidth: .infinity, maxHeight: 1)
                        .clipped()
                        .padding(.horizontal)
                    HStack {
                        Image(systemName: "drop")
                            .imageScale(.large)
                            .symbolRenderingMode(.monochrome)
                        Text("1:00 PM")
                            .font(.title2)
                            .foregroundStyle(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255))
                        Spacer()
                            .frame(width: 130)
                            .clipped()
                        Image(systemName: "checkmark.circle")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255))
                            .font(.system(size: 22, weight: .bold, design: .default))
                    }
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .padding(.horizontal)
                    Divider()
                        .frame(maxWidth: .infinity, maxHeight: 1)
                        .clipped()
                        .padding(.horizontal)
                    HStack {
                        Image(systemName: "drop")
                            .imageScale(.large)
                            .symbolRenderingMode(.monochrome)
                        Text("6:00 PM")
                            .font(.title2)
                            .foregroundStyle(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255))
                        Spacer()
                            .frame(width: 130)
                            .clipped()
                        Image(systemName: "checkmark.circle")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255))
                            .font(.system(size: 22, weight: .bold, design: .default))
                    }
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .padding(.horizontal)
                }
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255), lineWidth: 2)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white))
                        .frame(height: 190)
                }
                .frame(maxWidth: .infinity, maxHeight: 200)
                .padding(.horizontal)
                Text("Your next dose is at 1:00 PM.")
                    .font(.title2)
                    .foregroundStyle(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255))
                    .padding()
                    .frame(height: 50)
                    .clipped()
                Spacer()
                    .frame(maxHeight: .infinity)
                    .clipped()
                ZStack {
                    Capsule(style: .continuous)
                        .fill(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255))
                        .frame(height: 120)
                        .clipped()
                    HStack {
                        Image(systemName: "drop.fill")
                            .imageScale(.large)
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(.white)
                        Text("Log dose")
                            .foregroundStyle(.white)
                            .font(.largeTitle)
                            .padding()
                    }
                }
            }
            .background {
                Group {
                    
                }
            }
            .padding()
        }
    }
}



#Preview {
    MedicationLogView()
}
