using NAudio.Wave;

namespace VantaSpeech.Services.Audio;

public enum RecordingState
{
    Idle,
    Recording,
    Paused,
    Stopped
}

public interface IAudioRecorder
{
    RecordingState State { get; }
    TimeSpan Duration { get; }
    float AudioLevel { get; }
    event EventHandler<RecordingState>? StateChanged;
    event EventHandler<TimeSpan>? DurationChanged;
    event EventHandler<float>? AudioLevelChanged;

    string? StartRecording();
    void PauseRecording();
    void ResumeRecording();
    (string FilePath, TimeSpan Duration)? StopRecording();
}

public class AudioRecorder : IAudioRecorder, IDisposable
{
    private WaveInEvent? _waveIn;
    private WaveFileWriter? _waveWriter;
    private string? _currentFilePath;
    private DateTime _startTime;
    private TimeSpan _pausedDuration;
    private DateTime _pauseStartTime;
    private System.Timers.Timer? _metricsTimer;

    private RecordingState _state = RecordingState.Idle;
    public RecordingState State
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

    private TimeSpan _duration;
    public TimeSpan Duration
    {
        get => _duration;
        private set
        {
            if (_duration != value)
            {
                _duration = value;
                DurationChanged?.Invoke(this, value);
            }
        }
    }

    private float _audioLevel;
    public float AudioLevel
    {
        get => _audioLevel;
        private set
        {
            if (Math.Abs(_audioLevel - value) > 0.001f)
            {
                _audioLevel = value;
                AudioLevelChanged?.Invoke(this, value);
            }
        }
    }

    public event EventHandler<RecordingState>? StateChanged;
    public event EventHandler<TimeSpan>? DurationChanged;
    public event EventHandler<float>? AudioLevelChanged;

    public string? StartRecording()
    {
        try
        {
            var recordingsDir = GetRecordingsDirectory();
            var fileName = GenerateFileName();
            _currentFilePath = Path.Combine(recordingsDir, fileName);

            _waveIn = new WaveInEvent
            {
                WaveFormat = new WaveFormat(44100, 16, 1),
                BufferMilliseconds = 100
            };

            _waveWriter = new WaveFileWriter(_currentFilePath, _waveIn.WaveFormat);

            _waveIn.DataAvailable += OnDataAvailable;
            _waveIn.RecordingStopped += OnRecordingStopped;

            _waveIn.StartRecording();
            _startTime = DateTime.Now;
            _pausedDuration = TimeSpan.Zero;

            StartMetricsTimer();

            State = RecordingState.Recording;
            return _currentFilePath;
        }
        catch (Exception)
        {
            Cleanup();
            return null;
        }
    }

    public void PauseRecording()
    {
        if (State != RecordingState.Recording) return;

        _waveIn?.StopRecording();
        _pauseStartTime = DateTime.Now;
        State = RecordingState.Paused;
    }

    public void ResumeRecording()
    {
        if (State != RecordingState.Paused) return;

        _pausedDuration += DateTime.Now - _pauseStartTime;
        _waveIn?.StartRecording();
        State = RecordingState.Recording;
    }

    public (string FilePath, TimeSpan Duration)? StopRecording()
    {
        if (State == RecordingState.Idle) return null;

        var filePath = _currentFilePath;
        var duration = GetCurrentDuration();

        _waveIn?.StopRecording();
        _waveWriter?.Dispose();
        _waveWriter = null;
        _waveIn?.Dispose();
        _waveIn = null;

        StopMetricsTimer();
        State = RecordingState.Idle;
        Duration = TimeSpan.Zero;
        AudioLevel = 0;

        return filePath != null ? (filePath, duration) : null;
    }

    private void OnDataAvailable(object? sender, WaveInEventArgs e)
    {
        _waveWriter?.Write(e.Buffer, 0, e.BytesRecorded);

        // Calculate audio level
        float maxSample = 0;
        for (int i = 0; i < e.BytesRecorded; i += 2)
        {
            short sample = (short)(e.Buffer[i + 1] << 8 | e.Buffer[i]);
            float sampleF = Math.Abs(sample / 32768f);
            if (sampleF > maxSample) maxSample = sampleF;
        }
        AudioLevel = maxSample;
    }

    private void OnRecordingStopped(object? sender, StoppedEventArgs e)
    {
        // Handle recording stopped
    }

    private void StartMetricsTimer()
    {
        _metricsTimer = new System.Timers.Timer(100);
        _metricsTimer.Elapsed += (s, e) =>
        {
            if (State == RecordingState.Recording)
            {
                Duration = GetCurrentDuration();
            }
        };
        _metricsTimer.Start();
    }

    private void StopMetricsTimer()
    {
        _metricsTimer?.Stop();
        _metricsTimer?.Dispose();
        _metricsTimer = null;
    }

    private TimeSpan GetCurrentDuration()
    {
        return State switch
        {
            RecordingState.Recording => DateTime.Now - _startTime - _pausedDuration,
            RecordingState.Paused => _pauseStartTime - _startTime - _pausedDuration,
            _ => TimeSpan.Zero
        };
    }

    private void Cleanup()
    {
        _waveWriter?.Dispose();
        _waveIn?.Dispose();
        _currentFilePath = null;
        StopMetricsTimer();
    }

    private static string GetRecordingsDirectory()
    {
        var dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "VantaSpeech",
            "Recordings"
        );
        if (!Directory.Exists(dir))
        {
            Directory.CreateDirectory(dir);
        }
        return dir;
    }

    private static string GenerateFileName()
    {
        return $"recording_{DateTime.Now:yyyyMMdd_HHmmss}.wav";
    }

    public void Dispose()
    {
        Cleanup();
        GC.SuppressFinalize(this);
    }
}
