using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using VantaSpeech.Models;
using VantaSpeech.Services.Storage;

namespace VantaSpeech.ViewModels;

public partial class LibraryViewModel : ObservableObject
{
    private readonly IRecordingRepository _recordingRepository;

    [ObservableProperty]
    private ObservableCollection<Recording> _recordings = new();

    [ObservableProperty]
    private Recording? _recentRecording;

    [ObservableProperty]
    private string _searchQuery = string.Empty;

    [ObservableProperty]
    private bool _isLoading;

    [ObservableProperty]
    private bool _isEmpty;

    public LibraryViewModel(IRecordingRepository recordingRepository)
    {
        _recordingRepository = recordingRepository;
    }

    [RelayCommand]
    private async Task LoadRecordingsAsync()
    {
        IsLoading = true;

        try
        {
            var recordings = string.IsNullOrWhiteSpace(SearchQuery)
                ? await _recordingRepository.GetAllRecordingsAsync()
                : await _recordingRepository.SearchRecordingsAsync(SearchQuery);

            Recordings.Clear();
            foreach (var recording in recordings)
            {
                Recordings.Add(recording);
            }

            RecentRecording = await _recordingRepository.GetMostRecentRecordingAsync();
            IsEmpty = Recordings.Count == 0 && string.IsNullOrWhiteSpace(SearchQuery);
        }
        finally
        {
            IsLoading = false;
        }
    }

    [RelayCommand]
    private async Task SearchAsync()
    {
        await LoadRecordingsAsync();
    }

    [RelayCommand]
    private async Task DeleteRecordingAsync(Recording recording)
    {
        // Delete audio file
        try
        {
            if (File.Exists(recording.AudioFilePath))
            {
                File.Delete(recording.AudioFilePath);
            }
        }
        catch
        {
            // Ignore file deletion errors
        }

        await _recordingRepository.DeleteRecordingAsync(recording.Id);
        Recordings.Remove(recording);

        if (RecentRecording?.Id == recording.Id)
        {
            RecentRecording = await _recordingRepository.GetMostRecentRecordingAsync();
        }

        IsEmpty = Recordings.Count == 0 && string.IsNullOrWhiteSpace(SearchQuery);
    }

    [RelayCommand]
    private async Task RenameRecordingAsync(Recording recording)
    {
        // This would typically show a dialog - simplified here
        await _recordingRepository.UpdateRecordingAsync(recording);
    }

    partial void OnSearchQueryChanged(string value)
    {
        _ = LoadRecordingsAsync();
    }
}
