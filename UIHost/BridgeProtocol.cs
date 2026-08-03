using System.Runtime.InteropServices;
using System.Text;

namespace UMM.UI;

internal static class LineProtocol
{
    internal const int MaximumPayloadLength = 1024 * 1024;
    private const int MaximumLineCount = 256;
    private const int MaximumKeyLength = 64;
    private const int MaximumValueLength = 512 * 1024;

    public static Dictionary<string, string> Parse(string payload)
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (string.IsNullOrEmpty(payload) || payload.Length > MaximumPayloadLength)
        {
            return result;
        }

        var lineCount = 0;
        foreach (var rawLine in payload.Split('\n'))
        {
            var line = rawLine.TrimEnd('\r');
            if (line.Length == 0)
            {
                continue;
            }

            lineCount++;
            if (lineCount > MaximumLineCount)
            {
                return new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            }

            var separator = line.IndexOf('=');
            if (separator <= 0)
            {
                return new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            }

            var key = line[..separator];
            if (!IsValidKey(key) || result.ContainsKey(key))
            {
                return new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            }

            if (!TryNormalizeValue(line[(separator + 1)..], MaximumValueLength, out var value))
            {
                return new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            }

            result[key] = value;
        }

        return result;
    }

    public static string Serialize(IEnumerable<KeyValuePair<string, string?>> values)
    {
        var payload = new StringBuilder();
        var seenKeys = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var lineCount = 0;

        foreach (var pair in values)
        {
            lineCount++;
            if (lineCount > MaximumLineCount ||
                !IsValidKey(pair.Key) ||
                !seenKeys.Add(pair.Key))
            {
                throw new InvalidDataException("The line protocol contains an invalid key set.");
            }

            if (!TryNormalizeValue(pair.Value, MaximumValueLength, out var value))
            {
                throw new InvalidDataException($"The line protocol value for '{pair.Key}' is too long.");
            }

            if (payload.Length > 0)
            {
                payload.Append('\n');
            }

            payload.Append(pair.Key).Append('=').Append(value);
            if (payload.Length > MaximumPayloadLength)
            {
                throw new InvalidDataException("The line protocol payload is too large.");
            }
        }

        return payload.ToString();
    }

    public static bool TryNormalizeCommandValue(
        string? value,
        int maximumLength,
        out string normalized) =>
        TryNormalizeValue(value, maximumLength, out normalized);

    private static bool IsValidKey(string key)
    {
        if (key.Length is < 1 or > MaximumKeyLength || !IsAsciiLetter(key[0]))
        {
            return false;
        }

        return key.Skip(1).All(character => IsAsciiLetter(character) || char.IsAsciiDigit(character));
    }

    private static bool IsAsciiLetter(char character) =>
        character is >= 'A' and <= 'Z' or >= 'a' and <= 'z';

    private static bool TryNormalizeValue(
        string? value,
        int maximumLength,
        out string normalized)
    {
        value ??= string.Empty;
        if (maximumLength < 0 || value.Length > maximumLength)
        {
            normalized = string.Empty;
            return false;
        }

        StringBuilder? builder = null;
        for (var index = 0; index < value.Length; index++)
        {
            var character = value[index];
            if (character is '\r' or '\n' or '\t' or '\0' || char.IsControl(character))
            {
                builder ??= new StringBuilder(value[..index], value.Length);
                builder.Append(' ');
            }
            else
            {
                builder?.Append(character);
            }
        }

        normalized = builder?.ToString() ?? value;
        return true;
    }
}

internal static class CopyDataMessageReader
{
    public const int WmCopyData = 0x004A;
    private const int MaximumByteCount = 2 * 1024 * 1024;

    [StructLayout(LayoutKind.Sequential)]
    private struct CopyDataStruct
    {
        public nint DataId;
        public int ByteCount;
        public nint DataPointer;
    }

    public static string Read(nint lParam)
    {
        if (lParam == 0)
        {
            return string.Empty;
        }

        var copyData = Marshal.PtrToStructure<CopyDataStruct>(lParam);
        if (copyData.DataPointer == 0 ||
            copyData.ByteCount <= 1 ||
            copyData.ByteCount > MaximumByteCount ||
            copyData.ByteCount % sizeof(char) != 0)
        {
            return string.Empty;
        }

        var characterCount = Math.Max(0, copyData.ByteCount / sizeof(char) - 1);
        return Marshal.PtrToStringUni(copyData.DataPointer, characterCount) ?? string.Empty;
    }
}
