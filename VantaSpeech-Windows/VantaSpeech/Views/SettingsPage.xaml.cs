using Microsoft.UI.Xaml.Controls;
using VantaSpeech.ViewModels;

namespace VantaSpeech.Views;

public sealed partial class SettingsPage : Page
{
    public SettingsViewModel ViewModel { get; }

    public SettingsPage()
    {
        InitializeComponent();
        ViewModel = App.GetService<SettingsViewModel>();
    }
}
