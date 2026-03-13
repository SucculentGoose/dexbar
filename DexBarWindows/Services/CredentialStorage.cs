using System.Runtime.InteropServices;
using System.Text;

namespace DexBarWindows.Services;

/// <summary>
/// Stores and retrieves the Dexcom password using the Windows Credential Manager
/// via P/Invoke to advapi32.dll.
/// </summary>
public static class CredentialStorage
{
    private const string CredentialTarget = "DexBar";
    private const string CredentialUserName = "dexbar";

    // -------------------------------------------------------------------------
    // P/Invoke declarations
    // -------------------------------------------------------------------------

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CredRead(
        string target,
        CRED_TYPE type,
        int flags,
        out IntPtr credential);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CredWrite(
        ref CREDENTIAL credential,
        uint flags);

    [DllImport("advapi32.dll")]
    private static extern void CredFree(IntPtr buffer);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CredDelete(
        string target,
        CRED_TYPE type,
        int flags);

    // -------------------------------------------------------------------------
    // Types
    // -------------------------------------------------------------------------

    private enum CRED_TYPE : uint
    {
        Generic = 1
    }

    private enum CRED_PERSIST : uint
    {
        LocalMachine = 2
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct CREDENTIAL
    {
        public uint Flags;
        public CRED_TYPE Type;
        public string TargetName;
        public string? Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public CRED_PERSIST Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        public string? TargetAlias;
        public string UserName;
    }

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    /// <summary>Saves the Dexcom password to Windows Credential Manager.</summary>
    public static void SavePassword(string password)
    {
        var blob = Encoding.UTF8.GetBytes(password);
        var blobPtr = Marshal.AllocHGlobal(blob.Length);
        try
        {
            Marshal.Copy(blob, 0, blobPtr, blob.Length);

            var credential = new CREDENTIAL
            {
                Flags = 0,
                Type = CRED_TYPE.Generic,
                TargetName = CredentialTarget,
                Comment = null,
                CredentialBlobSize = (uint)blob.Length,
                CredentialBlob = blobPtr,
                Persist = CRED_PERSIST.LocalMachine,
                AttributeCount = 0,
                Attributes = IntPtr.Zero,
                TargetAlias = null,
                UserName = CredentialUserName
            };

            if (!CredWrite(ref credential, 0))
                throw new InvalidOperationException(
                    $"CredWrite failed with error {Marshal.GetLastWin32Error()}.");
        }
        finally
        {
            Marshal.FreeHGlobal(blobPtr);
        }
    }

    /// <summary>
    /// Loads the Dexcom password from Windows Credential Manager.
    /// Returns null if no credential is stored.
    /// </summary>
    public static string? LoadPassword()
    {
        if (!CredRead(CredentialTarget, CRED_TYPE.Generic, 0, out var credPtr))
            return null;

        try
        {
            var cred = Marshal.PtrToStructure<CREDENTIAL>(credPtr);

            if (cred.CredentialBlobSize == 0 || cred.CredentialBlob == IntPtr.Zero)
                return null;

            var blob = new byte[cred.CredentialBlobSize];
            Marshal.Copy(cred.CredentialBlob, blob, 0, blob.Length);
            return Encoding.UTF8.GetString(blob);
        }
        finally
        {
            CredFree(credPtr);
        }
    }

    /// <summary>Deletes the stored Dexcom credential from Windows Credential Manager.</summary>
    public static void DeletePassword()
    {
        // CredDelete returns false if the credential doesn't exist; that's acceptable.
        CredDelete(CredentialTarget, CRED_TYPE.Generic, 0);
    }
}
