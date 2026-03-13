namespace DexBarWindows.Models;

public enum DexcomRegion
{
    US,
    OUS,
    JP
}

public static class DexcomRegionExtensions
{
    public static string BaseUrl(this DexcomRegion region) => region switch
    {
        DexcomRegion.OUS => "https://shareous1.dexcom.com/ShareWebServices/Services",
        DexcomRegion.JP => "https://shareous1.dexcom.jp/ShareWebServices/Services",
        _ => "https://share2.dexcom.com/ShareWebServices/Services"
    };
}
