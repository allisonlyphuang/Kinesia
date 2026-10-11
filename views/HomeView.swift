//
//  Home.swift
//  MyProject
//
//  Designed in DetailsPro
//  Copyright © (My Organization). All rights reserved.
//

import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading) {
                // Top bar
                HStack {
                    Image(systemName: "leaf.circle.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)
                        .foregroundStyle(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255))
                    Spacer()
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(.sRGB, red: 168/255, green: 179/255, blue: 160/255))
                            .frame(width: 150, height: 50)
                            .clipped()
                            .padding(.horizontal, 0)
                        Image(systemName: "gearshape")
                            .imageScale(.large)
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 24)
                // Greeting
                VStack(alignment: .leading) {
                    // greeting
                    Text("Good morning, Name")
                        .font(.system(size: 28, weight: .semibold, design: .default))
                        .foregroundStyle(Color(.sRGB, red: 57/255, green: 66/255, blue: 57/255))
                    Spacer()
                        .frame(height: 5)
                        .clipped()
                    Text("Monday, January 1")
                        .font(.system(size: 17, weight: .medium, design: .default))
                        .foregroundStyle(Color(.sRGB, red: 57/255, green: 66/255, blue: 57/255))
                }
                .padding(.vertical)
                // Placeholder for the garden artwork.
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.sRGB, red: 232/255, green: 228/255, blue: 218/255))
                    .frame(maxWidth: .infinity, maxHeight: 180, alignment: .center)
                    .clipped()
                // streak
                HStack {
                    Text("Day # | #-day streak")
                        .foregroundStyle(Color(.sRGB, red: 57/255, green: 66/255, blue: 57/255))
                        .font(.system(size: 13, weight: .regular, design: .default))
                    Spacer(minLength: 50)
                    Text("Tap to view garden")
                        .foregroundStyle(Color(.sRGB, red: 57/255, green: 66/255, blue: 57/255))
                        .font(.system(size: 13, weight: .regular, design: .default))
                }
                .padding(.bottom, 8)
                // Log medicine
                ZStack {
                    // Log button
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.sRGB, red: 59/255, green: 84/255, blue: 101/255))
                        .frame(maxWidth: .infinity, maxHeight: 110)
                        .clipped()
                        .padding(.bottom, 0)
                    HStack {
                        Image(systemName: "pills.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 32)
                            .foregroundStyle(.white)
                        Text("Log medicine")
                            .foregroundStyle(.white)
                            .font(.system(size: 28, weight: .regular, design: .default))
                    }
                }
                // Today's check in
                VStack(alignment: .leading) {
                    Text("Today’s check-in")
                        .font(.system(size: 28, weight: .medium, design: .default))
                        .foregroundStyle(Color(.sRGB, red: 57/255, green: 66/255, blue: 57/255))
                        .padding(.top, 8)
                    Spacer()
                        .frame(height: 10)
                        .clipped()
                    // Task list
                    VStack(alignment: .leading) {
                        HStack {
                            Image(systemName: "leaf")
                                .imageScale(.small)
                                .symbolRenderingMode(.monochrome)
                            Text("Lily pads")
                                .foregroundStyle(Color(.sRGB, red: 57/255, green: 66/255, blue: 57/255))
                        }
                        NavigationLink {
                            AkinesiaTestView()
                        } label: {
                            HStack {
                                Image(systemName: "light.max")
                                    .imageScale(.small)
                                    .symbolRenderingMode(.monochrome)
                                Text("Fireflies")
                                    .font(.body)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .imageScale(.small)
                            }
                            .foregroundStyle(Color(.sRGB, red: 57/255, green: 66/255, blue: 57/255))
                        }
                        .buttonStyle(.plain)
                        HStack {
                            Image(systemName: "star")
                                .imageScale(.small)
                                .symbolRenderingMode(.monochrome)
                            Text("Constellation")
                                .foregroundStyle(Color(.sRGB, red: 57/255, green: 66/255, blue: 57/255))
                        }
                        NavigationLink {
                            BradykinesiaTestView()
                        } label: {
                            HStack {
                                Image(systemName: "hand.tap")
                                    .imageScale(.small)
                                Text("Bradykinesia Test")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .imageScale(.small)
                            }
                            .foregroundStyle(Color(.sRGB, red: 57/255, green: 66/255, blue: 57/255))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.leading, 8)
                    // Check-in button
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255))
                            .padding(.bottom, 0)
                            .frame(height: 60)
                            .clipped()
                        Text("Begin check-in")
                            .font(.system(size: 22, weight: .medium, design: .default))
                            .foregroundStyle(.white)
                    }
                    .padding(6)
                }
                .padding(.horizontal, 24)
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color(.sRGB, red: 232/255, green: 228/255, blue: 218/255), lineWidth: 3)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white))
                }
                // Switch tab
                ZStack(alignment: .leading) {
                    // Clear capsule to hold shape
                    Capsule(style: .continuous)
                        .fill(.clear)
                        .frame(width: 290, height: 75, alignment: .leading)
                        .clipped()
                        .padding()
                    Capsule(style: .continuous)
                        .fill(Color(.sRGB, red: 255/255, green: 253/255, blue: 248/255))
                        .frame(width: 140, height: 50, alignment: .leading)
                        .clipped()
                        .padding(24)
                    HStack {
                        Spacer()
                        Text("Garden")
                            .font(.system(size: 17, weight: .regular, design: .default))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("Insights")
                            .font(.system(size: 17, weight: .regular, design: .default))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                }
                .padding(16)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color(.sRGB, red: 86/255, green: 96/255, blue: 84/255))
                        .frame(maxWidth: .infinity, maxHeight: 75)
                        .padding(24)
                }
            }
            .padding(24)
            .frame(maxHeight: .infinity)
            .clipped()
        }
        .background {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(.sRGB, red: 255/255, green: 253/255, blue: 248/255))
        }
        }
    }
}



#Preview {
    HomeView()
}
