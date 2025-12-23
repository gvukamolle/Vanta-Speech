using Concentus.Oggfile;
using Concentus.Structs;
using NAudio.Wave;
using VantaSpeech.Models;

namespace VantaSpeech.Services.Audio;

public interface IAudioConverter
{
    Task<string?> ConvertToOggAsync(string inputPath, AudioQuality quality = AudioQuality.Low);
    long EstimateFileSize(TimeSpan duration, AudioQuality quality);
}

public class AudioConverter : IAudioConverter
{
    private const int SampleRate = 48000;
    private const int Channels = 1;

    public async Task<string?> ConvertToOggAsync(string inputPath, AudioQuality quality = AudioQuality.Low)
    {
        return await Task.Run(() =>
        {
            try
            {
                var outputPath = Path.ChangeExtension(inputPath, ".ogg");
                var bitrate = (int)quality * 1000;

                using var reader = new AudioFileReader(inputPath);

                // Resample to 48kHz mono if needed
                var resampler = new MediaFoundationResampler(reader, new WaveFormat(SampleRate, 16, Channels));

                var encoder = new OpusEncoder(SampleRate, Channels, Concentus.Enums.OpusApplication.OPUS_APPLICATION_VOIP)
                {
                    Bitrate = bitrate,
                    UseVBR = true
                };

                using var outputStream = File.Create(outputPath);
                var oggStream = new OpusOggWriteStream(encoder, outputStream);

                var buffer = new byte[SampleRate * 2 * Channels / 50]; // 20ms of audio
                var pcmBuffer = new short[buffer.Length / 2];

                int bytesRead;
                while ((bytesRead = resampler.Read(buffer, 0, buffer.Length)) > 0)
                {
                    // Convert bytes to shorts
                    for (int i = 0; i < bytesRead / 2; i++)
                    {
                        pcmBuffer[i] = (short)(buffer[i * 2] | (buffer[i * 2 + 1] << 8));
                    }

                    oggStream.WriteSamples(pcmBuffer, 0, bytesRead / 2);
                }

                oggStream.Finish();
                resampler.Dispose();

                return outputPath;
            }
            catch (Exception)
            {
                return null;
            }
        });
    }

    public long EstimateFileSize(TimeSpan duration, AudioQuality quality)
    {
        // Bitrate in kbps * duration in seconds / 8 = bytes
        return (long)((int)quality * duration.TotalSeconds * 1000 / 8);
    }
}
