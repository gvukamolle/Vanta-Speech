using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using VantaSpeech.Views;

namespace VantaSpeech;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();

        Title = "Vanta Speech";
        ExtendsContentIntoTitleBar = true;

        // Navigate to Library by default
        ContentFrame.Navigate(typeof(LibraryPage));
        NavView.SelectedItem = NavView.MenuItems[0];
    }

    private void NavView_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.IsSettingsSelected)
        {
            ContentFrame.Navigate(typeof(SettingsPage));
        }
        else if (args.SelectedItem is NavigationViewItem item)
        {
            var tag = item.Tag?.ToString();
            switch (tag)
            {
                case "library":
                    ContentFrame.Navigate(typeof(LibraryPage));
                    break;
                case "record":
                    ContentFrame.Navigate(typeof(RecordingPage));
                    break;
            }
        }
    }
}
