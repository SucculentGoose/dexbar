namespace DexBarWindows.Models;

public abstract record MonitorState
{
    public sealed record Idle : MonitorState;
    public sealed record Loading : MonitorState;
    public sealed record Connected : MonitorState;
    public sealed record Error(string Message) : MonitorState;

    public string StatusText => this switch
    {
        Idle => "Idle",
        Loading => "Loading...",
        Connected => "Connected",
        Error e => $"Error: {e.Message}",
        _ => "Unknown"
    };
}
