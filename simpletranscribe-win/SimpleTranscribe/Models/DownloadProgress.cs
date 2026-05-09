namespace SimpleTranscribe.Models;

public record DownloadProgress(
    double Fraction,
    double BytesPerSecond,
    long TotalBytes,
    long ReceivedBytes)
{
    public double? EtaSeconds =>
        TotalBytes > 0 && BytesPerSecond > 0
            ? (TotalBytes - ReceivedBytes) / BytesPerSecond
            : null;

    public string SpeedString
    {
        get
        {
            double mbs = BytesPerSecond / 1_048_576;
            if (mbs >= 1)
                return $"{mbs:F1} MB/s";

            double kbs = BytesPerSecond / 1_024;
            return $"{Math.Max(kbs, 0):F0} KB/s";
        }
    }

    public string EtaString
    {
        get
        {
            if (EtaSeconds is not { } eta)
                return "";
            if (eta < 60)
                return $"~{eta:F0}s remaining";
            if (eta < 3600)
                return $"~{eta / 60:F0}min remaining";
            return $"~{eta / 3600:F1}h remaining";
        }
    }
}
