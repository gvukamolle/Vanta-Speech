using Microsoft.EntityFrameworkCore;
using VantaSpeech.Models;

namespace VantaSpeech.Services.Storage;

public interface IRecordingRepository
{
    Task<List<Recording>> GetAllRecordingsAsync();
    Task<Recording?> GetRecordingByIdAsync(Guid id);
    Task<List<Recording>> SearchRecordingsAsync(string query);
    Task<Recording?> GetMostRecentRecordingAsync();
    Task AddRecordingAsync(Recording recording);
    Task UpdateRecordingAsync(Recording recording);
    Task DeleteRecordingAsync(Guid id);
    Task DeleteAllRecordingsAsync();
    Task UpdateTranscriptionAsync(Guid id, string transcription, string? summary);
}

public class RecordingRepository : IRecordingRepository
{
    private readonly RecordingDbContext _context;

    public RecordingRepository(RecordingDbContext context)
    {
        _context = context;
    }

    public async Task<List<Recording>> GetAllRecordingsAsync()
    {
        return await _context.Recordings
            .OrderByDescending(r => r.CreatedAt)
            .ToListAsync();
    }

    public async Task<Recording?> GetRecordingByIdAsync(Guid id)
    {
        return await _context.Recordings.FindAsync(id);
    }

    public async Task<List<Recording>> SearchRecordingsAsync(string query)
    {
        return await _context.Recordings
            .Where(r => r.Title.Contains(query) ||
                       (r.TranscriptionText != null && r.TranscriptionText.Contains(query)))
            .OrderByDescending(r => r.CreatedAt)
            .ToListAsync();
    }

    public async Task<Recording?> GetMostRecentRecordingAsync()
    {
        return await _context.Recordings
            .OrderByDescending(r => r.CreatedAt)
            .FirstOrDefaultAsync();
    }

    public async Task AddRecordingAsync(Recording recording)
    {
        _context.Recordings.Add(recording);
        await _context.SaveChangesAsync();
    }

    public async Task UpdateRecordingAsync(Recording recording)
    {
        _context.Recordings.Update(recording);
        await _context.SaveChangesAsync();
    }

    public async Task DeleteRecordingAsync(Guid id)
    {
        var recording = await _context.Recordings.FindAsync(id);
        if (recording != null)
        {
            _context.Recordings.Remove(recording);
            await _context.SaveChangesAsync();
        }
    }

    public async Task DeleteAllRecordingsAsync()
    {
        _context.Recordings.RemoveRange(_context.Recordings);
        await _context.SaveChangesAsync();
    }

    public async Task UpdateTranscriptionAsync(Guid id, string transcription, string? summary)
    {
        var recording = await _context.Recordings.FindAsync(id);
        if (recording != null)
        {
            recording.TranscriptionText = transcription;
            recording.SummaryText = summary;
            recording.IsTranscribed = true;
            recording.IsUploading = false;
            await _context.SaveChangesAsync();
        }
    }
}
