using NAudio.Wave;

namespace VantaSpeech.Services.Audio;

public enum PlaybackState
{
    Idle,
    Playing,
    Paused,
    Stopped
}

public interface IAudioPlayer
{
    PlaybackState State { get; }
    TimeSpan CurrentPosition { get; }
    TimeSpan Duration { get; }
    float Progress { get; }
    event EventHandler<PlaybackState>? StateChanged;
    event EventHandler<TimeSpan>? PositionChanged;

    void Load(string filePath);
    void Play();
    void Pause();
    void Stop();
    void SeekTo(TimeSpan position);
    void SeekToProgress(float progress);
    void SkipForward(int seconds = 15);
    void SkipBackward(int seconds = 15);
    string FormatTime(TimeSpan time);
}

public class AudioPlayer : IAudioPlayer, IDisposable
{
    private WaveOutEvent? _waveOut;
    private AudioFileReader? _audioReader;
    private System.Timers.Timer? _positionTimer;
    private string? _currentFilePath;

    private PlaybackState _state = PlaybackState.Idle;
    public PlaybackState State
    {
        get => _state;
        private set
        {
            if (_state != value)
            {
                _state = value;
                StateChanged?.Invoke(this, value);
            }
        }
    }

    private TimeSpan _currentPosition;
    public TimeSpan CurrentPosition
    {
        get => _currentPosition;
        private set
        {
            if (_currentPosition != value)
            {
                _currentPosition = value;
                PositionChanged?.Invoke(this, value);
            }
        }
    }

    public TimeSpan Duration => _audioReader?.TotalTime ?? TimeSpan.Zero;
    public float Progress => Duration.TotalMilliseconds > 0
        ? (float)(CurrentPosition.TotalMilliseconds / Duration.TotalMilliseconds)
        : 0;

    public event EventHandler<PlaybackState>? StateChanged;
    public event EventHandler<TimeSpan>? PositionChanged;

    public void Load(string filePath)
    {
        if (_currentFilePath == filePath && _audioReader != null) return;

        Release();
        _currentFilePath = filePath;

        _audioReader = new AudioFileReader(filePath);
        _waveOut = new WaveOutEvent();
        _waveOut.Init(_audioReader);
        _waveOut.PlaybackStopped += OnPlaybackStopped;

        State = PlaybackState.Idle;
        CurrentPosition = TimeSpan.Zero;
    }

    public void Play()
    {
        _waveOut?.Play();
        StartPositionTimer();
        State = PlaybackState.Playing;
    }

    public void Pause()
    {
        _waveOut?.Pause();
        StopPositionTimer();
        State = PlaybackState.Paused;
    }

    public void Stop()
    {
        _waveOut?.Stop();
        if (_audioReader != null)
        {
            _audioReader.Position = 0;
        }
        StopPositionTimer();
        CurrentPosition = TimeSpan.Zero;
        State = PlaybackState.Stopped;
    }

    public void SeekTo(TimeSpan position)
    {
        if (_audioReader != null)
        {
            var clampedPosition = TimeSpan.FromMilliseconds(
                Math.Clamp(position.TotalMilliseconds, 0, Duration.TotalMilliseconds)
            );
            _audioReader.CurrentTime = clampedPosition;
            CurrentPosition = clampedPosition;
        }
    }

    public void SeekToProgress(float progress)
    {
        var position = TimeSpan.FromMilliseconds(Duration.TotalMilliseconds * progress);
        SeekTo(position);
    }

    public void SkipForward(int seconds = 15)
    {
        SeekTo(CurrentPosition + TimeSpan.FromSeconds(seconds));
    }

    public void SkipBackward(int seconds = 15)
    {
        SeekTo(CurrentPosition - TimeSpan.FromSeconds(seconds));
    }

    public string FormatTime(TimeSpan time)
    {
        if (time.TotalHours >= 1)
        {
            return $"{(int)time.TotalHours}:{time.Minutes:D2}:{time.Seconds:D2}";
        }
        return $"{time.Minutes}:{time.Seconds:D2}";
    }

    private void OnPlaybackStopped(object? sender, StoppedEventArgs e)
    {
        if (_audioReader?.CurrentTime >= Duration - TimeSpan.FromMilliseconds(100))
        {
            State = PlaybackState.Stopped;
            CurrentPosition = TimeSpan.Zero;
            if (_audioReader != null)
            {
                _audioReader.Position = 0;
            }
        }
    }

    private void StartPositionTimer()
    {
        _positionTimer = new System.Timers.Timer(100);
        _positionTimer.Elapsed += (s, e) =>
        {
            if (_audioReader != null)
            {
                CurrentPosition = _audioReader.CurrentTime;
            }
        };
        _positionTimer.Start();
    }

    private void StopPositionTimer()
    {
        _positionTimer?.Stop();
        _positionTimer?.Dispose();
        _positionTimer = null;
    }

    private void Release()
    {
        StopPositionTimer();
        _waveOut?.Dispose();
        _audioReader?.Dispose();
        _waveOut = null;
        _audioReader = null;
        _currentFilePath = null;
    }

    public void Dispose()
    {
        Release();
        GC.SuppressFinalize(this);
    }
}
