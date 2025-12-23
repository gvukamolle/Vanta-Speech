using System.Text.Json.Serialization;

namespace VantaSpeech.Models;

public class TranscriptionResult
{
    [JsonPropertyName("transcription")]
    public string Transcription { get; set; } = string.Empty;

    [JsonPropertyName("summary")]
    public string? Summary { get; set; }

    [JsonPropertyName("language")]
    public string? Language { get; set; }

    [JsonPropertyName("duration")]
    public double? Duration { get; set; }
}

public class TranscriptionError
{
    [JsonPropertyName("error")]
    public string Error { get; set; } = string.Empty;

    [JsonPropertyName("code")]
    public string? Code { get; set; }
}
