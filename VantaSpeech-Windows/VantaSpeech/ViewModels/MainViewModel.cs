using CommunityToolkit.Mvvm.ComponentModel;

namespace VantaSpeech.ViewModels;

public partial class MainViewModel : ObservableObject
{
    [ObservableProperty]
    private string _selectedNavItem = "library";

    [ObservableProperty]
    private bool _isNavigating;
}
