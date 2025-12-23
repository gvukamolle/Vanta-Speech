using VantaSpeech.Models;
using Windows.Storage;

namespace VantaSpeech.Services.Storage;

public interface ISettingsService
{
    string ServerUrl { get; set; }
    bool AutoTranscribe { get; set; }
    AudioQuality AudioQuality { get; set; }
}

public class SettingsService : ISettingsService
{
    private readonly ApplicationDataContainer _localSettings;

    public SettingsService()
    {
        _localSettings = ApplicationData.Current.LocalSettings;
    }

    public string ServerUrl
    {
        get => _localSettings.Values["ServerUrl"] as string ?? "";
        set => _localSettings.Values["ServerUrl"] = value;
    }

    public bool AutoTranscribe
    {
        get => _localSettings.Values["AutoTranscribe"] is bool value && value;
        set => _localSettings.Values["AutoTranscribe"] = value;
    }

    public AudioQuality AudioQuality
    {
        get
        {
            if (_localSettings.Values["AudioQuality"] is int quality)
            {
                return (AudioQuality)quality;
            }
            return AudioQuality.Low;
        }
        set => _localSettings.Values["AudioQuality"] = (int)value;
    }
}
