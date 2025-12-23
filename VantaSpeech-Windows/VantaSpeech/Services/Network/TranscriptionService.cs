using System.Net.Http.Headers;
using System.Text.Json;
using VantaSpeech.Models;

namespace VantaSpeech.Services.Network;

public interface ITranscriptionService
{
    string BaseUrl { get; set; }
    Task<TranscriptionResult?> TranscribeAsync(string audioFilePath);
}

public class TranscriptionService : ITranscriptionService, IDisposable
{
    private HttpClient _httpClient;
    private string _baseUrl = "http://localhost:8080/";

    public string BaseUrl
    {
        get => _baseUrl;
        set
        {
            var normalizedUrl = value.EndsWith("/") ? value : value + "/";
            if (_baseUrl != normalizedUrl)
            {
                _baseUrl = normalizedUrl;
                ConfigureHttpClient();
            }
        }
    }

    public TranscriptionService()
    {
        _httpClient = new HttpClient();
        ConfigureHttpClient();
    }

    private void ConfigureHttpClient()
    {
        _httpClient.BaseAddress = new Uri(_baseUrl);
        _httpClient.Timeout = TimeSpan.FromMinutes(10);
    }

    public async Task<TranscriptionResult?> TranscribeAsync(string audioFilePath)
    {
        if (!File.Exists(audioFilePath))
        {
            throw new FileNotFoundException("Audio file not found", audioFilePath);
        }

        try
        {
            using var content = new MultipartFormDataContent();
            using var fileStream = File.OpenRead(audioFilePath);
            using var streamContent = new StreamContent(fileStream);

            var mimeType = GetMimeType(Path.GetExtension(audioFilePath));
            streamContent.Headers.ContentType = new MediaTypeHeaderValue(mimeType);

            content.Add(streamContent, "file", Path.GetFileName(audioFilePath));

            var response = await _httpClient.PostAsync("transcribe", content);
            response.EnsureSuccessStatusCode();

            var json = await response.Content.ReadAsStringAsync();
            return JsonSerializer.Deserialize<TranscriptionResult>(json);
        }
        catch (HttpRequestException ex)
        {
            throw new Exception($"Network error: {ex.Message}", ex);
        }
        catch (TaskCanceledException)
        {
            throw new Exception("Request timed out");
        }
    }

    private static string GetMimeType(string extension)
    {
        return extension.ToLowerInvariant() switch
        {
            ".m4a" => "audio/mp4",
            ".ogg" or ".opus" => "audio/ogg",
            ".mp3" => "audio/mpeg",
            ".wav" => "audio/wav",
            ".aac" => "audio/aac",
            _ => "audio/*"
        };
    }

    public void Dispose()
    {
        _httpClient.Dispose();
        GC.SuppressFinalize(this);
    }
}
