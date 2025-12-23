using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using VantaSpeech.Models;
using VantaSpeech.Services.Network;
using VantaSpeech.Services.Storage;

namespace VantaSpeech.ViewModels;

public partial class SettingsViewModel : ObservableObject
{
    private readonly ISettingsService _settingsService;
    private readonly ITranscriptionService _transcriptionService;
    private readonly IRecordingRepository _recordingRepository;

    [ObservableProperty]
    private string _serverUrl = string.Empty;

    [ObservableProperty]
    private bool _autoTranscribe;

    [ObservableProperty]
    private AudioQuality _audioQuality = AudioQuality.Low;

    public string AudioQualityLabel => AudioQuality.GetLabel();

    public SettingsViewModel(
        ISettingsService settingsService,
        ITranscriptionService transcriptionService,
        IRecordingRepository recordingRepository)
    {
        _settingsService = settingsService;
        _transcriptionService = transcriptionService;
        _recordingRepository = recordingRepository;

        LoadSettings();
    }

    private void LoadSettings()
    {
        ServerUrl = _settingsService.ServerUrl;
        AutoTranscribe = _settingsService.AutoTranscribe;
        AudioQuality = _settingsService.AudioQuality;
    }

    partial void OnServerUrlChanged(string value)
    {
        _settingsService.ServerUrl = value;
        _transcriptionService.BaseUrl = value;
    }

    partial void OnAutoTranscribeChanged(bool value)
    {
        _settingsService.AutoTranscribe = value;
    }

    partial void OnAudioQualityChanged(AudioQuality value)
    {
        _settingsService.AudioQuality = value;
        OnPropertyChanged(nameof(AudioQualityLabel));
    }

    [RelayCommand]
    private void SetAudioQuality(AudioQuality quality)
    {
        AudioQuality = quality;
    }

    [RelayCommand]
    private async Task ClearAllRecordingsAsync()
    {
        // Delete all audio files
        var recordingsDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "VantaSpeech",
            "Recordings"
        );

        if (Directory.Exists(recordingsDir))
        {
            try
            {
                foreach (var file in Directory.GetFiles(recordingsDir))
                {
                    File.Delete(file);
                }
            }
            catch
            {
                // Ignore file deletion errors
            }
        }

        await _recordingRepository.DeleteAllRecordingsAsync();
    }
}
