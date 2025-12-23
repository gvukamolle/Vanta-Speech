using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Data;
using VantaSpeech.Models;

namespace VantaSpeech.Helpers;

public class BoolToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        return value is true ? Visibility.Visible : Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language)
    {
        return value is Visibility.Visible;
    }
}

public class BoolToVisibilityInverseConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        return value is true ? Visibility.Collapsed : Visibility.Visible;
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language)
    {
        return value is Visibility.Collapsed;
    }
}

public class NullToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        return value != null ? Visibility.Visible : Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language)
    {
        throw new NotImplementedException();
    }
}

public class PauseIconConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        // Play icon when paused, Pause icon when playing
        return value is true ? "\uE768" : "\uE769";
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language)
    {
        throw new NotImplementedException();
    }
}

public class AudioQualityLowConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        return value is AudioQuality quality && quality == AudioQuality.Low;
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language)
    {
        return AudioQuality.Low;
    }
}

public class AudioQualityMediumConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        return value is AudioQuality quality && quality == AudioQuality.Medium;
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language)
    {
        return AudioQuality.Medium;
    }
}

public class AudioQualityHighConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        return value is AudioQuality quality && quality == AudioQuality.High;
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language)
    {
        return AudioQuality.High;
    }
}
