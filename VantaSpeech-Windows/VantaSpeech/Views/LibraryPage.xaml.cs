using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using VantaSpeech.ViewModels;

namespace VantaSpeech.Views;

public sealed partial class LibraryPage : Page
{
    public LibraryViewModel ViewModel { get; }

    public LibraryPage()
    {
        InitializeComponent();
        ViewModel = App.GetService<LibraryViewModel>();
    }

    private async void Page_Loaded(object sender, RoutedEventArgs e)
    {
        await ViewModel.LoadRecordingsCommand.ExecuteAsync(null);
    }
}
