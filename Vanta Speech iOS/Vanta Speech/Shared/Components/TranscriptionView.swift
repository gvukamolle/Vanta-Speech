import SwiftUI

/// View для отображения расшифровки записи
struct TranscriptionView: View {
    let recording: Recording
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ContentSheetView(
            title: "Расшифровка",
            icon: "text.bubble",
            content: recording.transcriptionText ?? "",
            recording: recording
        )
    }
}

#Preview {
    TranscriptionView(recording: Recording(
        title: "Тестовая запись",
        duration: 120,
        audioFileURL: "/test.ogg",
        transcriptionText: "Это тестовая расшифровка записи.",
        isTranscribed: true
    ))
}
