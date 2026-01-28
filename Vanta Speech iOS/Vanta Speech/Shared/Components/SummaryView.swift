import SwiftUI

/// View для отображения саммари записи
struct SummaryView: View {
    let recording: Recording
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ContentSheetView(
            title: "Саммари",
            icon: "doc.text",
            content: recording.summaryText ?? "",
            recording: recording,
            onCheckboxToggle: { lineIndex in
                guard let currentText = recording.summaryText else { return }
                recording.summaryText = MarkdownCheckboxToggler.toggleCheckbox(in: currentText, at: lineIndex)
            },
            isEditable: true,
            onContentChange: { newContent in
                recording.summaryText = newContent
            },
            onRegenerateSummary: recording.isTranscribed && recording.summaryText != nil ? {
                Task {
                    await RecordingCoordinator.shared.generateSummary(for: recording)
                }
            } : nil
        )
    }
}

#Preview {
    SummaryView(recording: Recording(
        title: "Тестовая запись",
        duration: 120,
        audioFileURL: "/test.ogg",
        transcriptionText: "Транскрипция...",
        summaryText: "## Основные моменты\n\n- [ ] Первый пункт\n- [x] Второй пункт",
        isTranscribed: true
    ))
}
