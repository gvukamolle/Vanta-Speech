using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.UI.Xaml;
using VantaSpeech.Services.Audio;
using VantaSpeech.Services.Network;
using VantaSpeech.Services.Storage;
using VantaSpeech.ViewModels;

namespace VantaSpeech;

public partial class App : Application
{
    public static IHost? Host { get; private set; }
    public static IServiceProvider Services => Host!.Services;

    private Window? _mainWindow;

    public App()
    {
        InitializeComponent();

        Host = Microsoft.Extensions.Hosting.Host.CreateDefaultBuilder()
            .ConfigureServices((context, services) =>
            {
                // Database
                services.AddDbContext<RecordingDbContext>();

                // Services
                services.AddSingleton<IAudioRecorder, AudioRecorder>();
                services.AddSingleton<IAudioPlayer, AudioPlayer>();
                services.AddSingleton<IAudioConverter, AudioConverter>();
                services.AddSingleton<ITranscriptionService, TranscriptionService>();
                services.AddSingleton<IRecordingRepository, RecordingRepository>();
                services.AddSingleton<ISettingsService, SettingsService>();

                // ViewModels
                services.AddTransient<MainViewModel>();
                services.AddTransient<RecordingViewModel>();
                services.AddTransient<LibraryViewModel>();
                services.AddTransient<SettingsViewModel>();
                services.AddTransient<RecordingDetailViewModel>();
            })
            .Build();
    }

    protected override async void OnLaunched(LaunchActivatedEventArgs args)
    {
        await Host!.StartAsync();

        // Initialize database
        using var scope = Services.CreateScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<RecordingDbContext>();
        await dbContext.Database.EnsureCreatedAsync();

        _mainWindow = new MainWindow();
        _mainWindow.Activate();
    }

    public static T GetService<T>() where T : class
    {
        return Services.GetRequiredService<T>();
    }
}
