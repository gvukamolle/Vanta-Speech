using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using VantaSpeech.Models;
using VantaSpeech.Services.Audio;
using VantaSpeech.Services.Network;
using VantaSpeech.Services.Storage;

namespace VantaSpeech.ViewModels;

public partial class RecordingDetailViewModel : ObservableObject
{
    private readonly IRecordingRepository _recordingRepository;
    private readonly ITranscriptionService _transcriptionService;
    private readonly IAudioPlayer _audioPlayer;

    [ObservableProperty]
    private Recording? _recording;

    [ObservableProperty]
    private bool _isTranscribing;

    [ObservableProperty]
    private string? _errorMessage;

    [ObservableProperty]
    private int _selectedTab; // 0 = Transcription, 1 = Summary

    [ObservableProperty]
    private PlaybackState _playbackState = PlaybackState.Idle;

    [ObservableProperty]
    private TimeSpan _currentPosition = TimeSpan.Zero;

    [ObservableProperty]
    private TimeSpan _duration = TimeSpan.Zero;

    [ObservableProperty]
    private float _progress;

    public string FormattedPosition => _audioPlayer.FormatTime(CurrentPosition);
    public string FormattedDuration => _audioPlayer.FormatTime(Duration);
    public bool IsPlaying => PlaybackState == PlaybackState.Playing;

    public RecordingDetailViewModel(
        IRecordingRepository recordingRepository,
        ITranscriptionService transcriptionService,
        IAudioPlayer audioPlayer)
    {
        _recordingRepository = recordingRepository;
        _transcriptionService = transcriptionService;
        _audioPlayer = audioPlayer;

        _audioPlayer.StateChanged += OnPlaybackStateChanged;
        _audioPlayer.PositionChanged += OnPositionChanged;
    }

    private void OnPlaybackStateChanged(object? sender, PlaybackState state)
    {
        PlaybackState = state;
        OnPropertyChanged(nameof(IsPlaying));
    }

    private void OnPositionChanged(object? sender, TimeSpan position)
    {
        CurrentPosition = position;
        Progress = _audioPlayer.Progress;
        OnPropertyChanged(nameof(FormattedPosition));
    }

    [RelayCommand]
    private async Task LoadRecordingAsync(Guid id)
    {
        Recording = await _recordingRepository.GetRecordingByIdAsync(id);
        if (Recording != null)
        {
            _audioPlayer.Load(Recording.AudioFilePath);
            Duration = _audioPlayer.Duration;
            OnPropertyChanged(nameof(FormattedDuration));
        }
    }

    [RelayCommand]
    private void TogglePlayback()
    {
        if (PlaybackState == PlaybackState.Playing)
        {
            _audioPlayer.Pause();
        }
        else
        {
            _audioPlayer.Play();
        }
    }

    [RelayCommand]
    private void Stop()
    {
        _audioPlayer.Stop();
    }

    [RelayCommand]
    private void SkipForward()
    {
        _audioPlayer.SkipForward(15);
    }

    [RelayCommand]
    private void SkipBackward()
    {
        _audioPlayer.SkipBackward(15);
    }

    [RelayCommand]
    private void SeekTo(float progress)
    {
        _audioPlayer.SeekToProgress(progress);
    }

    [RelayCommand]
    private async Task TranscribeAsync()
    {
        if (Recording == null || IsTranscribing) return;

        IsTranscribing = true;
        ErrorMessage = null;

        try
        {
            Recording.IsUploading = true;
            await _recordingRepository.UpdateRecordingAsync(Recording);

            var result = await _transcriptionService.TranscribeAsync(Recording.AudioFilePath);
            if (result != null)
            {
                await _recordingRepository.UpdateTranscriptionAsync(
                    Recording.Id,
                    result.Transcription,
                    result.Summary
                );

                // Reload recording to get updated data
                Recording = await _recordingRepository.GetRecordingByIdAsync(Recording.Id);
            }
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
            Recording.IsUploading = false;
            await _recordingRepository.UpdateRecordingAsync(Recording);
        }
        finally
        {
            IsTranscribing = false;
        }
    }

    [RelayCommand]
    private void CopyToClipboard(string? content)
    {
        if (string.IsNullOrEmpty(content)) return;

        var dataPackage = new Windows.ApplicationModel.DataTransfer.DataPackage();
        dataPackage.SetText(content);
        Windows.ApplicationModel.DataTransfer.Clipboard.SetContent(dataPackage);
    }
}
