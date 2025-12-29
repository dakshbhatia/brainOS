//
//  UserProfileSetupView.swift
//  BrainOS
//
//  User profile setup for personalizing the AI experience
//

import SwiftUI
import AppKit

struct UserProfileSetupView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var age: String = ""
    @State private var location: String = ""
    @State private var bio: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.blue)
                }
                
                Text("Set Up Your Profile")
                    .font(.system(size: 20, weight: .semibold))
                
                Text("Help BrainOS understand you better for personalized assistance")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            .padding(.top, 30)
            .padding(.bottom, 24)
            
            // Form
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.system(size: 13, weight: .semibold))
                        
                        TextField("Your name", text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .padding(10)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Age")
                            .font(.system(size: 13, weight: .semibold))
                        
                        TextField("Optional", text: $age)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .padding(10)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Location")
                            .font(.system(size: 13, weight: .semibold))
                        
                        TextField("City, Country (optional)", text: $location)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .padding(10)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About You")
                            .font(.system(size: 13, weight: .semibold))
                        
                        TextEditor(text: $bio)
                            .font(.system(size: 14))
                            .frame(height: 80)
                            .padding(6)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        
                        Text("Occupation, interests, goals, etc. (optional)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 40)
            }
            
            // Actions
            VStack(spacing: 12) {
                Button(action: saveProfile) {
                    Text("Save Profile")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(name.isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                        )
                }
                .buttonStyle(.plain)
                .disabled(name.isEmpty)
                
                Button(action: { dismiss() }) {
                    Text("Skip for now")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
        }
        .frame(width: 480, height: 550)
        .onAppear {
            // Load existing profile if any
            name = UserDefaults.standard.string(forKey: "userName") ?? NSFullUserName()
            if let savedAge = UserDefaults.standard.object(forKey: "userAge") as? Int, savedAge > 0 {
                age = String(savedAge)
            }
            location = UserDefaults.standard.string(forKey: "userLocation") ?? ""
            bio = UserDefaults.standard.string(forKey: "userBio") ?? ""
        }
    }
    
    private func saveProfile() {
        UserDefaults.standard.set(name, forKey: "userName")
        
        if let ageInt = Int(age), ageInt > 0 {
            UserDefaults.standard.set(ageInt, forKey: "userAge")
        }
        
        if !location.isEmpty {
            UserDefaults.standard.set(location, forKey: "userLocation")
        }
        
        if !bio.isEmpty {
            UserDefaults.standard.set(bio, forKey: "userBio")
        }
        
        UserDefaults.standard.set(true, forKey: "hasCompletedProfileSetup")
        
        dismiss()
    }
}

#Preview {
    UserProfileSetupView()
}
