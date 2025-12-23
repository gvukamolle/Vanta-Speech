using Microsoft.UI.Xaml.Controls;
using VantaSpeech.ViewModels;

namespace VantaSpeech.Views;

public sealed partial class RecordingPage : Page
{
    public RecordingViewModel ViewModel { get; }

    public RecordingPage()
    {
        InitializeComponent();
        ViewModel = App.GetService<RecordingViewModel>();
    }
}
