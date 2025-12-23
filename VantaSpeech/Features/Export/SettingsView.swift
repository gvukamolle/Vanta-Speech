import SwiftUI

struct SettingsView: View {
    @AppStorage("serverURL") private var serverURL = ""
    @AppStorage("autoTranscribe") private var autoTranscribe = false
    @AppStorage("audioQuality") private var audioQualityRaw = AudioQuality.low.rawValue

    private var audioQuality: AudioQuality {
        get { AudioQuality(rawValue: audioQualityRaw) ?? .low }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Transcription Server URL", text: $serverURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)

                    Toggle("Auto-transcribe after recording", isOn: $autoTranscribe)
                }

                Section("Recording") {
                    Picker("Audio Quality", selection: $audioQualityRaw) {
                        ForEach(AudioQuality.allCases, id: \.rawValue) { quality in
                            Text(quality.displayName).tag(quality.rawValue)
                        }
                    }

                    Text(audioQuality.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Integrations") {
                    NavigationLink("Confluence") {
                        IntegrationSettingsView(service: "Confluence")
                    }

                    NavigationLink("Notion") {
                        IntegrationSettingsView(service: "Notion")
                    }

                    NavigationLink("Google Docs") {
                        IntegrationSettingsView(service: "Google Docs")
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://example.com/privacy")!) {
                        Text("Privacy Policy")
                    }

                    Link(destination: URL(string: "https://example.com/terms")!) {
                        Text("Terms of Service")
                    }
                }

                Section {
                    Button("Clear All Recordings", role: .destructive) {
                        // TODO: Implement clear all
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

struct IntegrationSettingsView: View {
    let service: String
    @State private var isConnected = false
    @State private var apiKey = ""

    var body: some View {
        Form {
            Section {
                if isConnected {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Connected")
                    }

                    Button("Disconnect", role: .destructive) {
                        isConnected = false
                        apiKey = ""
                    }
                } else {
                    SecureField("API Key", text: $apiKey)

                    Button("Connect") {
                        if !apiKey.isEmpty {
                            isConnected = true
                        }
                    }
                    .disabled(apiKey.isEmpty)
                }
            } header: {
                Text("\(service) Integration")
            } footer: {
                Text("Connect your \(service) account to export transcriptions and summaries directly.")
            }
        }
        .navigationTitle(service)
    }
}

#Preview {
    SettingsView()
}
