using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using VantaSpeech.Models;
using VantaSpeech.Services.Audio;
using VantaSpeech.Services.Storage;

namespace VantaSpeech.ViewModels;

public partial class RecordingViewModel : ObservableObject
{
    private readonly IAudioRecorder _audioRecorder;
    private readonly IRecordingRepository _recordingRepository;
    private string? _currentRecordingPath;

    [ObservableProperty]
    private RecordingState _state = RecordingState.Idle;

    [ObservableProperty]
    private TimeSpan _duration = TimeSpan.Zero;

    [ObservableProperty]
    private float _audioLevel;

    [ObservableProperty]
    private string _statusText = "Tap to Record";

    public string FormattedDuration
    {
        get
        {
            if (Duration.TotalHours >= 1)
            {
                return $"{(int)Duration.TotalHours}:{Duration.Minutes:D2}:{Duration.Seconds:D2}";
            }
            return $"{Duration.Minutes:D2}:{Duration.Seconds:D2}";
        }
    }

    public bool IsRecording => State == RecordingState.Recording;
    public bool IsPaused => State == RecordingState.Paused;
    public bool IsActive => State == RecordingState.Recording || State == RecordingState.Paused;

    public RecordingViewModel(IAudioRecorder audioRecorder, IRecordingRepository recordingRepository)
    {
        _audioRecorder = audioRecorder;
        _recordingRepository = recordingRepository;

        _audioRecorder.StateChanged += OnStateChanged;
        _audioRecorder.DurationChanged += OnDurationChanged;
        _audioRecorder.AudioLevelChanged += OnAudioLevelChanged;
    }

    private void OnStateChanged(object? sender, RecordingState state)
    {
        State = state;
        StatusText = state switch
        {
            RecordingState.Recording => "Recording...",
            RecordingState.Paused => "Paused",
            _ => "Tap to Record"
        };
        OnPropertyChanged(nameof(IsRecording));
        OnPropertyChanged(nameof(IsPaused));
        OnPropertyChanged(nameof(IsActive));
    }

    private void OnDurationChanged(object? sender, TimeSpan duration)
    {
        Duration = duration;
        OnPropertyChanged(nameof(FormattedDuration));
    }

    private void OnAudioLevelChanged(object? sender, float level)
    {
        AudioLevel = level;
    }

    [RelayCommand]
    private void ToggleRecording()
    {
        if (State == RecordingState.Idle)
        {
            _currentRecordingPath = _audioRecorder.StartRecording();
        }
        else
        {
            StopRecording();
        }
    }

    [RelayCommand]
    private void TogglePause()
    {
        if (State == RecordingState.Recording)
        {
            _audioRecorder.PauseRecording();
        }
        else if (State == RecordingState.Paused)
        {
            _audioRecorder.ResumeRecording();
        }
    }

    [RelayCommand]
    private async Task StopRecording()
    {
        var result = _audioRecorder.StopRecording();
        if (result.HasValue)
        {
            var (filePath, duration) = result.Value;
            var recording = new Recording
            {
                Title = $"Recording {DateTime.Now:MMM d, yyyy HH:mm}",
                Duration = duration,
                AudioFilePath = filePath
            };

            await _recordingRepository.AddRecordingAsync(recording);
        }
    }
}
