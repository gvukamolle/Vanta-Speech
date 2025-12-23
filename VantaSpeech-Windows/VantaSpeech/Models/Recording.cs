using System.ComponentModel.DataAnnotations;

namespace VantaSpeech.Models;

public class Recording
{
    [Key]
    public Guid Id { get; set; } = Guid.NewGuid();

    [Required]
    public string Title { get; set; } = string.Empty;

    public DateTime CreatedAt { get; set; } = DateTime.Now;

    public TimeSpan Duration { get; set; } = TimeSpan.Zero;

    [Required]
    public string AudioFilePath { get; set; } = string.Empty;

    public string? TranscriptionText { get; set; }

    public string? SummaryText { get; set; }

    public bool IsTranscribed { get; set; }

    public bool IsUploading { get; set; }

    // Computed properties
    public string FormattedDuration
    {
        get
        {
            if (Duration.TotalHours >= 1)
            {
                return $"{(int)Duration.TotalHours}:{Duration.Minutes:D2}:{Duration.Seconds:D2}";
            }
            return $"{Duration.Minutes}:{Duration.Seconds:D2}";
        }
    }

    public string FormattedDate
    {
        get
        {
            var now = DateTime.Now;
            if (CreatedAt.Date == now.Date)
            {
                return $"Today, {CreatedAt:HH:mm}";
            }
            if (CreatedAt.Date == now.AddDays(-1).Date)
            {
                return $"Yesterday, {CreatedAt:HH:mm}";
            }
            return CreatedAt.ToString("MMM d, yyyy");
        }
    }

    public string? TranscriptionPreview
    {
        get
        {
            if (string.IsNullOrEmpty(TranscriptionText)) return null;
            return TranscriptionText.Length > 150
                ? TranscriptionText[..150] + "..."
                : TranscriptionText;
        }
    }
}

public enum AudioQuality
{
    Low = 64,
    Medium = 96,
    High = 128
}

public static class AudioQualityExtensions
{
    public static string GetLabel(this AudioQuality quality) => quality switch
    {
        AudioQuality.Low => "Low (64 kbps)",
        AudioQuality.Medium => "Medium (96 kbps)",
        AudioQuality.High => "High (128 kbps)",
        _ => "Unknown"
    };
}
