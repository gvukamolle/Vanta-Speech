import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage("serverURL") private var serverURL = ""
    @AppStorage("autoTranscribe") private var autoTranscribe = false
    @AppStorage("audioQuality") private var audioQuality = AudioQuality.low.rawValue

    var body: some View {
        TabView {
            GeneralSettingsView(
                serverURL: $serverURL,
                autoTranscribe: $autoTranscribe,
                audioQuality: $audioQuality
            )
            .tabItem {
                Label("General", systemImage: "gear")
            }

            IntegrationsSettingsView()
                .tabItem {
                    Label("Integrations", systemImage: "link")
                }

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 300)
    }
}

struct GeneralSettingsView: View {
    @Binding var serverURL: String
    @Binding var autoTranscribe: Bool
    @Binding var audioQuality: String

    var body: some View {
        Form {
            Section("Server Configuration") {
                TextField("Server URL", text: $serverURL, prompt: Text("https://your-server.com"))
                    .textFieldStyle(.roundedBorder)

                Toggle("Auto-transcribe after recording", isOn: $autoTranscribe)
            }

            Section("Audio Quality") {
                Picker("Recording Quality", selection: $audioQuality) {
                    ForEach(AudioQuality.allCases) { quality in
                        Text(quality.label).tag(quality.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct IntegrationsSettingsView: View {
    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Confluence")
                            .font(.headline)
                        Text("Export transcriptions to Confluence")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("Not connected")
                        .foregroundColor(.secondary)
                }

                HStack {
                    VStack(alignment: .leading) {
                        Text("Notion")
                            .font(.headline)
                        Text("Export transcriptions to Notion")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("Not connected")
                        .foregroundColor(.secondary)
                }

                HStack {
                    VStack(alignment: .leading) {
                        Text("Google Docs")
                            .font(.headline)
                        Text("Export transcriptions to Google Docs")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("Not connected")
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Vanta Speech")
                .font(.title)
                .fontWeight(.semibold)

            Text("Version 1.0.0")
                .foregroundColor(.secondary)

            Text("Meeting recorder with AI-powered transcription")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            HStack(spacing: 20) {
                Link("Privacy Policy", destination: URL(string: "https://example.com/privacy")!)
                Link("Terms of Service", destination: URL(string: "https://example.com/terms")!)
            }
            .font(.caption)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView()
}
