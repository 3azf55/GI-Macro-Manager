using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace UMM.UI;

internal sealed class MacroEditorService
{
    private const int MaximumSourceBytes = 512 * 1024;
    private const int MaximumEventCount = 5_000;
    private const int MaximumLoopDepth = 4;
    private const int MaximumDelayMilliseconds = 600_000;
    private const int MaximumLoopCount = 1_000;

    private static readonly UTF8Encoding Utf8WithoutBom = new(false);
    private static readonly UTF8Encoding Utf8WithBom = new(true);
    private static readonly HashSet<string> AllowedKeys = new(StringComparer.OrdinalIgnoreCase)
    {
        "LButton", "RButton", "MButton", "WheelUp", "WheelDown",
        "Q", "E", "R", "F", "W", "A", "S", "D", "Shift", "Space",
        "1", "2", "3", "4", "5"
    };
    private static readonly HashSet<string> AllowedFpsTags = new(StringComparer.Ordinal)
    {
        string.Empty, "60 FPS", "120 FPS", "240 FPS"
    };
    private static readonly string[] PerformanceHeaderLines =
    [
        "#NoEnv",
        "#NoTrayIcon",
        "#SingleInstance Force",
        "#MaxThreadsPerHotkey 1",
        "#MaxThreadsBuffer Off",
        "SendMode Input",
        "SetBatchLines, -1",
        "SetMouseDelay, -1",
        "SetKeyDelay, -1, -1",
        "SetWinDelay, -1",
        "SetControlDelay, -1",
        "SetDefaultMouseSpeed, 0",
        "ListLines, Off",
        "Process, Priority,, High"
    ];

    private readonly string _rootDirectory;
    private readonly string _registryPath;
    private readonly string _settingsPath;
    private readonly string _runtimePath;
    private readonly string _userMacroRoot;
    private readonly Dictionary<string, EditSession> _sessions = new(StringComparer.Ordinal);
    private readonly object _gate = new();

    public MacroEditorService(string rootDirectory)
    {
        _rootDirectory = Path.GetFullPath(rootDirectory);
        _registryPath = Path.Combine(_rootDirectory, "Macros", "registry.ini");
        _settingsPath = Path.Combine(_rootDirectory, "settings.ini");
        _runtimePath = Path.Combine(_rootDirectory, "Macros", "Runtime", "MacroRuntime.ahk");
        _userMacroRoot = Path.Combine(_rootDirectory, "Macros", "User");
    }

    public MacroEditorDocument Load(string comboId)
    {
        lock (_gate)
        {
            comboId = NormalizeRequiredField(comboId, 120, "Select a valid macro.");
            var registryText = ReadTextFile(_registryPath, MaximumSourceBytes);
            var macros = ParseRegistry(registryText);
            var macro = macros.FirstOrDefault(item =>
                item.Id.Equals(comboId, StringComparison.OrdinalIgnoreCase));

            if (macro is null)
            {
                throw new MacroEditorException("The selected macro no longer exists.");
            }

            var sessionId = Guid.NewGuid().ToString("N");
            if (!TryLoadVisualEditorSource(
                    macro,
                    out var sourcePath,
                    out var packageDirectory,
                    out var sourceBytes,
                    out var sourceText,
                    out var function))
            {
                _sessions[sessionId] = EditSession.ForMetadataOnly(
                    sessionId,
                    macro.Id,
                    macro.Character,
                    TryResolvePackageDirectory(macro.Script));
                TrimSessions();

                return new MacroEditorDocument
                {
                    SessionId = sessionId,
                    Mode = "edit",
                    ComboId = macro.Id,
                    Character = macro.Character,
                    Name = macro.Name,
                    Description = macro.Tooltip,
                    FpsTag = ExtractFpsTag(macro.Tag),
                    Testing = HasTestingTag(macro.Tag),
                    MacroTrigger = macro.MacroTrigger,
                    CanSave = true,
                    CanEditEvents = false,
                    Warnings =
                    [
                        "This macro was not created with Macro Manager's visual editor. " +
                        "Only its name, description, and tags can be changed; its AHK source stays untouched."
                    ]
                };
            }

            var rawBlocks = new Dictionary<string, string>(StringComparer.Ordinal);
            var parser = new AhkEventParser(rawBlocks);
            var events = parser.Parse(function!.Body);
            var warnings = new List<string>();

            if (rawBlocks.Count > 0)
            {
                warnings.Add(
                    $"{rawBlocks.Count} advanced step{(rawBlocks.Count == 1 ? "" : "s")} " +
                    "will be preserved exactly. You can move or remove them, but their internal code stays hidden.");
            }

            if (events.Count == 0)
            {
                warnings.Add("No editable actions were found. Add an event before saving.");
            }

            _sessions[sessionId] = new EditSession(
                sessionId,
                macro.Id,
                macro.Character,
                sourcePath,
                packageDirectory,
                Convert.ToHexString(SHA256.HashData(sourceBytes)),
                sourceText,
                function,
                rawBlocks,
                CanEditEvents: true);
            TrimSessions();

            return new MacroEditorDocument
            {
                SessionId = sessionId,
                Mode = "edit",
                ComboId = macro.Id,
                Character = macro.Character,
                Name = macro.Name,
                Description = macro.Tooltip,
                FpsTag = ExtractFpsTag(macro.Tag),
                Testing = HasTestingTag(macro.Tag),
                MacroTrigger = macro.MacroTrigger,
                CanSave = true,
                CanEditEvents = true,
                Events = events,
                Warnings = warnings
            };
        }
    }

    public MacroEditorDocument CreateDraft(string character)
    {
        lock (_gate)
        {
            character = NormalizeRequiredField(character, 50, "Select a valid character.");
            var registryText = ReadTextFile(_registryPath, MaximumSourceBytes);
            var macros = ParseRegistry(registryText);
            if (!RegistryContainsCharacter(registryText, character, macros))
            {
                throw new MacroEditorException("The selected character no longer exists.");
            }

            return new MacroEditorDocument
            {
                Mode = "create",
                Character = character,
                CanSave = true,
                CanEditEvents = true,
                Events =
                [
                    new MacroEditorEvent
                    {
                        Id = NewEventId(),
                        Type = "input",
                        Key = "LButton",
                        Action = "tap",
                        DurationMs = 30
                    },
                    new MacroEditorEvent
                    {
                        Id = NewEventId(),
                        Type = "delay",
                        DurationMs = 100
                    }
                ]
            };
        }
    }

    public string CreatePreview(MacroEditorSaveRequest request)
    {
        lock (_gate)
        {
            if (request is null)
            {
                throw new MacroEditorException("The macro editor sent an empty test request.");
            }

            IReadOnlyDictionary<string, string> rawBlocks =
                new Dictionary<string, string>(StringComparer.Ordinal);
            EditSession? session = null;
            if (!string.IsNullOrWhiteSpace(request.SessionId))
            {
                var sessionId = NormalizeRequiredField(
                    request.SessionId,
                    64,
                    "The editing session has expired. Reopen the macro and try again.");
                if (!_sessions.TryGetValue(sessionId, out session) || !session.CanEditEvents)
                {
                    throw new MacroEditorException("This macro cannot be tested in the visual editor.");
                }
                if (!string.Equals(request.ComboId, session.ComboId, StringComparison.Ordinal) ||
                    !string.Equals(request.Character, session.Character, StringComparison.Ordinal))
                {
                    throw new MacroEditorException("The selected macro changed while the editor was open.");
                }

                var currentBytes = ReadBytes(session.SourcePath, MaximumSourceBytes);
                var currentHash = Convert.ToHexString(SHA256.HashData(currentBytes));
                if (!currentHash.Equals(session.SourceHash, StringComparison.Ordinal))
                {
                    throw new MacroEditorException(
                        "The AHK file changed outside the editor. Reopen it before testing changes.");
                }
                rawBlocks = session.RawBlocks;
            }

            ValidateEvents(request.Events, rawBlocks, allowRaw: session is not null);
            string previewSource;
            if (session is null)
            {
                var runtimeText = ReadTextFile(_runtimePath, MaximumSourceBytes);
                previewSource = BuildGeneratedSource(runtimeText, request.Events, "\r\n");
            }
            else
            {
                var function = session.Function
                    ?? throw new MacroEditorException("The visual macro editing session is invalid.");
                var renderedBody = RenderEvents(
                    request.Events,
                    session.RawBlocks,
                    function.NewLine,
                    function.BodyIndent);
                previewSource = session.SourceText[..function.BodyStart]
                    + function.NewLine
                    + renderedBody
                    + function.NewLine
                    + function.FunctionIndent
                    + session.SourceText[function.BodyEnd..];
                previewSource = EnsurePerformanceHeader(previewSource, function.NewLine);
            }

            if (Utf8WithBom.GetByteCount(previewSource) > MaximumSourceBytes)
            {
                throw new MacroEditorException("The generated test macro is too large.");
            }

            var previewDirectory = Path.Combine(_rootDirectory, "bridge", "macro-previews");
            Directory.CreateDirectory(previewDirectory);
            DeleteExpiredPreviewFiles(previewDirectory);
            var previewId = Guid.NewGuid().ToString("N");
            AtomicWrite(
                Path.Combine(previewDirectory, previewId + ".ahk"),
                previewSource,
                Utf8WithBom);
            return previewId;
        }
    }

    private static void DeleteExpiredPreviewFiles(string directory)
    {
        var cutoff = DateTime.UtcNow.AddDays(-1);
        foreach (var path in Directory.EnumerateFiles(directory, "*.ahk", SearchOption.TopDirectoryOnly))
        {
            try
            {
                if (File.GetLastWriteTimeUtc(path) < cutoff)
                {
                    File.Delete(path);
                }
            }
            catch (IOException)
            {
                // A running or concurrently cleaned preview can be ignored.
            }
            catch (UnauthorizedAccessException)
            {
                // Preview cleanup must never block the editor.
            }
        }
    }

    public MacroSaveResult Save(MacroEditorSaveRequest request)
    {
        lock (_gate)
        {
            if (request is null)
            {
                throw new MacroEditorException("The macro editor sent an empty save request.");
            }

            var sessionId = NormalizeRequiredField(
                request.SessionId,
                64,
                "The editing session has expired. Reopen the macro and try again.");
            if (!_sessions.TryGetValue(sessionId, out var session))
            {
                throw new MacroEditorException(
                    "The editing session has expired. Reopen the macro and try again.");
            }

            var comboId = NormalizeRequiredField(request.ComboId, 120, "Select a valid macro.");
            if (!comboId.Equals(session.ComboId, StringComparison.Ordinal) ||
                !string.Equals(request.Character, session.Character, StringComparison.Ordinal))
            {
                throw new MacroEditorException("The selected macro changed while the editor was open.");
            }

            var metadata = ValidateMetadata(request);
            var originalRegistry = ReadTextFile(_registryPath, MaximumSourceBytes);
            var macros = ParseRegistry(originalRegistry);
            var macro = macros.FirstOrDefault(item =>
                item.Id.Equals(session.ComboId, StringComparison.Ordinal));
            if (macro is null)
            {
                throw new MacroEditorException("The selected macro no longer exists in the registry.");
            }
            var tag = BuildTag(metadata.FpsTag, metadata.Testing);
            ValidateMacroTrigger(metadata.MacroTrigger, macros, macro.Id);
            if (macros.Any(item =>
                    !item.Id.Equals(macro.Id, StringComparison.Ordinal) &&
                    item.Character.Equals(macro.Character, StringComparison.Ordinal) &&
                    HasSameCatalogIdentity(item, metadata.Name, metadata.Description, tag)))
            {
                throw new MacroEditorException(
                    "Another macro for this character already uses the same name, description, and tags.");
            }

            var updatedRegistry = UpdateIniSection(
                originalRegistry,
                macro.Section,
                new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
                {
                    ["Name"] = metadata.Name,
                    ["Tooltip"] = metadata.Description,
                    ["Tag"] = tag,
                    ["MacroTrigger"] = metadata.MacroTrigger
                });
            var metadataValues = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
            {
                ["Name"] = metadata.Name,
                ["Tooltip"] = metadata.Description,
                ["Tag"] = tag,
                ["MacroTrigger"] = metadata.MacroTrigger
            };
            var updates = new List<FileUpdate>();

            if (session.CanEditEvents)
            {
                var currentBytes = ReadBytes(session.SourcePath, MaximumSourceBytes);
                var currentHash = Convert.ToHexString(SHA256.HashData(currentBytes));
                if (!currentHash.Equals(session.SourceHash, StringComparison.Ordinal))
                {
                    throw new MacroEditorException(
                        "The AHK file changed outside the editor. Reopen it to avoid overwriting newer changes.");
                }

                ValidateEvents(request.Events, session.RawBlocks, allowRaw: true);
                var function = session.Function
                    ?? throw new MacroEditorException("The visual macro editing session is invalid.");
                var renderedBody = RenderEvents(
                    request.Events,
                    session.RawBlocks,
                    function.NewLine,
                    function.BodyIndent);
                var updatedSource = session.SourceText[..function.BodyStart]
                    + function.NewLine
                    + renderedBody
                    + function.NewLine
                    + function.FunctionIndent
                    + session.SourceText[function.BodyEnd..];
                updatedSource = EnsurePerformanceHeader(updatedSource, function.NewLine);

                if (Utf8WithBom.GetByteCount(updatedSource) > MaximumSourceBytes)
                {
                    throw new MacroEditorException("The generated AHK file is too large.");
                }

                updates.Add(new FileUpdate(
                    session.SourcePath,
                    updatedSource,
                    Utf8WithBom,
                    session.SourceText));
            }

            var manifestPath = session.PackageDirectory.Length == 0
                ? string.Empty
                : Path.Combine(session.PackageDirectory, "manifest.ini");
            if (manifestPath.Length > 0 && File.Exists(manifestPath))
            {
                var originalManifest = ReadTextFile(manifestPath, 64 * 1024);
                if (Regex.IsMatch(originalManifest, @"(?m)^\[Macro\][ \t]*\r?$"))
                {
                    updates.Add(new FileUpdate(
                        manifestPath,
                        UpdateIniSection(originalManifest, "Macro", metadataValues),
                        Utf8WithoutBom,
                        originalManifest));
                }
            }

            updates.Add(new FileUpdate(
                _registryPath,
                updatedRegistry,
                Utf8WithoutBom,
                originalRegistry));
            WriteWithRollback(updates.ToArray());

            _sessions.Remove(sessionId);
            return new MacroSaveResult
            {
                ComboId = macro.Id,
                Character = macro.Character,
                Name = metadata.Name,
                Created = false,
                Message = $"Saved {metadata.Name}."
            };
        }
    }

    public MacroSaveResult Create(MacroEditorSaveRequest request)
    {
        lock (_gate)
        {
            if (request is null)
            {
                throw new MacroEditorException("The macro editor sent an empty create request.");
            }

            var character = NormalizeRequiredField(
                request.Character,
                50,
                "Select a valid character.");
            var metadata = ValidateMetadata(request);
            ValidateEvents(request.Events, new Dictionary<string, string>(), allowRaw: false);

            var originalRegistry = ReadTextFile(_registryPath, MaximumSourceBytes);
            var macros = ParseRegistry(originalRegistry);
            var characterMacros = macros
                .Where(item => item.Character.Equals(character, StringComparison.Ordinal))
                .ToList();
            if (characterMacros.Count == 0 &&
                !RegistryContainsCharacter(originalRegistry, character, macros))
            {
                throw new MacroEditorException("The selected character no longer exists.");
            }
            var tag = BuildTag(metadata.FpsTag, metadata.Testing);
            ValidateMacroTrigger(metadata.MacroTrigger, macros);
            if (characterMacros.Any(item =>
                    HasSameCatalogIdentity(item, metadata.Name, metadata.Description, tag)))
            {
                throw new MacroEditorException(
                    "Another macro for this character already uses the same name, description, and tags.");
            }

            var packageRoot = Path.Combine(_userMacroRoot, Slug(character));
            Directory.CreateDirectory(packageRoot);
            var identity = SelectIdentity(character, metadata.Name, packageRoot, macros);
            var packageDirectory = Path.Combine(packageRoot, identity.PackageName);
            if (Directory.Exists(packageDirectory))
            {
                throw new MacroEditorException("The new macro folder already exists.");
            }

            var runtimeText = ReadTextFile(_runtimePath, MaximumSourceBytes);
            var newLine = "\r\n";
            var sourceText = BuildGeneratedSource(runtimeText, request.Events, newLine);
            if (Utf8WithBom.GetByteCount(sourceText) > MaximumSourceBytes)
            {
                throw new MacroEditorException("The generated AHK file is too large.");
            }

            var image = characterMacros.FirstOrDefault()?.Image;
            if (string.IsNullOrWhiteSpace(image))
            {
                image = GetRegisteredCharacterImage(originalRegistry, character);
            }
            if (string.IsNullOrWhiteSpace(image))
            {
                image = character + ".png";
            }
            var order = macros.Count == 0 ? 10 : macros.Max(item => item.Order) + 10;
            var relativeSource = Path.GetRelativePath(
                    _rootDirectory,
                    Path.Combine(packageDirectory, "source.ahk"))
                .Replace('/', '\\');
            var section = "Combo." + identity.ComboId;
            var registrySection = new StringBuilder()
                .Append('[').Append(section).Append(']').Append(newLine)
                .Append("Id=").Append(identity.ComboId).Append(newLine)
                .Append("Character=").Append(character).Append(newLine)
                .Append("Image=").Append(image).Append(newLine)
                .Append("Name=").Append(metadata.Name).Append(newLine)
                .Append("Tooltip=").Append(metadata.Description).Append(newLine)
                .Append("Tag=").Append(tag).Append(newLine)
                .Append("Script=").Append(relativeSource).Append(newLine)
                .Append("BuiltIn=0").Append(newLine)
                .Append("Order=").Append(order).Append(newLine)
                .Append("ExecutionMode=AutoExecute").Append(newLine)
                .Append("MacroTrigger=").Append(metadata.MacroTrigger).Append(newLine)
                .ToString();
            var updatedRegistry = originalRegistry.TrimEnd('\r', '\n')
                + newLine + newLine + registrySection;
            var manifestText = BuildManifest(
                identity.ComboId,
                character,
                image,
                metadata.Name,
                metadata.Description,
                tag,
                metadata.MacroTrigger,
                newLine);

            try
            {
                Directory.CreateDirectory(packageDirectory);
                AtomicWrite(
                    Path.Combine(packageDirectory, "source.ahk"),
                    sourceText,
                    Utf8WithBom);
                AtomicWrite(
                    Path.Combine(packageDirectory, "manifest.ini"),
                    manifestText,
                    Utf8WithoutBom);
                AtomicWrite(_registryPath, updatedRegistry, Utf8WithoutBom);
            }
            catch
            {
                try
                {
                    AtomicWrite(_registryPath, originalRegistry, Utf8WithoutBom);
                }
                catch
                {
                    // Keep the original failure as the actionable error.
                }

                try
                {
                    if (Directory.Exists(packageDirectory))
                    {
                        Directory.Delete(packageDirectory, recursive: true);
                    }
                }
                catch
                {
                    // The unregistered folder is harmless and can be removed later.
                }

                throw;
            }

            return new MacroSaveResult
            {
                ComboId = identity.ComboId,
                Character = character,
                Name = metadata.Name,
                Created = true,
                Message = $"Created {metadata.Name}."
            };
        }
    }

    private static MacroMetadata ValidateMetadata(MacroEditorSaveRequest request)
    {
        var name = NormalizeRequiredField(request.Name, 60, "Macro name is required.");
        var description = NormalizeOptionalField(request.Description, 80, "Description is too long.");
        if (!AllowedFpsTags.Contains(request.FpsTag ?? string.Empty))
        {
            throw new MacroEditorException("Select a supported FPS tag.");
        }

        return new MacroMetadata(
            name,
            description,
            request.FpsTag ?? string.Empty,
            request.Testing,
            NormalizeMacroTrigger(request.MacroTrigger));
    }

    private static string NormalizeMacroTrigger(string? value)
    {
        var trigger = NormalizeOptionalField(value, 32, "The macro trigger is invalid.");
        if (trigger.Length == 0)
        {
            return string.Empty;
        }

        var supported = Regex.IsMatch(
            trigger,
            @"(?i)^(?:XButton[12]|F(?:[1-9]|1[0-9]|2[0-4])|[A-Z0-9]|Space|Tab|CapsLock|Backspace|Enter|Insert|Delete|Home|End|PgUp|PgDn|Up|Down|Left|Right|LShift|RShift|LControl|RControl|LAlt|RAlt|AppsKey|Numpad[0-9]|NumpadDot|NumpadAdd|NumpadSub|NumpadMult|NumpadDiv|NumpadEnter)$");
        var reserved = Regex.IsMatch(
            trigger,
            @"(?i)^(?:LButton|RButton|Q|W|E|A|S|D|F|Shift|LShift|RShift|WheelUp|WheelDown|WheelLeft|WheelRight)$");
        if (!supported || reserved)
        {
            throw new MacroEditorException("Choose a supported, non-gameplay key for the macro trigger.");
        }
        return trigger;
    }

    private void ValidateMacroTrigger(
        string trigger,
        IReadOnlyCollection<RegistryMacro> macros,
        string excludedComboId = "")
    {
        if (trigger.Length == 0)
        {
            return;
        }

        if (macros.Any(item =>
                !item.Id.Equals(excludedComboId, StringComparison.OrdinalIgnoreCase) &&
                item.MacroTrigger.Equals(trigger, StringComparison.OrdinalIgnoreCase)))
        {
            throw new MacroEditorException("That trigger is already linked to another macro.");
        }

        var configuredHotkeys = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["TriggerKey"] = "XButton2",
            ["ComboToggleKey"] = "F10",
            ["CharacterToggleKey"] = "F9",
            ["ModeToggleKey"] = "F8",
            ["InterfaceKey"] = "F11",
            ["RecorderHotkey"] = "F7"
        };
        if (File.Exists(_settingsPath))
        {
            var settingsText = ReadTextFile(_settingsPath, 64 * 1024);
            var settingsMatch = Regex.Match(
                settingsText,
                @"(?ms)^\[Settings\][ \t]*\r?\n(?<body>.*?)(?=^\[|\z)");
            if (settingsMatch.Success)
            {
                foreach (Match match in Regex.Matches(
                             settingsMatch.Groups["body"].Value,
                             @"(?m)^(?<key>TriggerKey|ComboToggleKey|CharacterToggleKey|ModeToggleKey|InterfaceKey|RecorderHotkey)=(?<value>.*)$",
                             RegexOptions.IgnoreCase))
                {
                    configuredHotkeys[match.Groups["key"].Value] = match.Groups["value"].Value.Trim();
                }
            }
        }

        if (configuredHotkeys.Values.Any(value => value.Equals(trigger, StringComparison.OrdinalIgnoreCase)))
        {
            throw new MacroEditorException("That key is already assigned on the Hotkeys page.");
        }
    }

    private static void ValidateEvents(
        IReadOnlyList<MacroEditorEvent>? events,
        IReadOnlyDictionary<string, string> rawBlocks,
        bool allowRaw)
    {
        if (events is null || events.Count == 0)
        {
            throw new MacroEditorException("Add at least one event before saving.");
        }

        var count = 0;
        var executableCount = 0;
        ValidateEventList(events, rawBlocks, allowRaw, 0, ref count, ref executableCount);
        if (executableCount == 0)
        {
            throw new MacroEditorException("Add at least one input, delay, loop, or advanced step.");
        }
    }

    private static void ValidateEventList(
        IReadOnlyList<MacroEditorEvent> events,
        IReadOnlyDictionary<string, string> rawBlocks,
        bool allowRaw,
        int depth,
        ref int count,
        ref int executableCount)
    {
        if (depth > MaximumLoopDepth)
        {
            throw new MacroEditorException($"Loops can be nested up to {MaximumLoopDepth} levels.");
        }

        foreach (var item in events)
        {
            count++;
            if (count > MaximumEventCount)
            {
                throw new MacroEditorException(
                    $"A macro can contain up to {MaximumEventCount} visual events.");
            }

            item.Type = (item.Type ?? string.Empty).Trim().ToLowerInvariant();
            item.Id = NormalizeEventId(item.Id);
            switch (item.Type)
            {
                case "input":
                    item.Key = NormalizeKey(item.Key);
                    item.Action = (item.Action ?? string.Empty).Trim().ToLowerInvariant();
                    if (item.Action is not ("tap" or "down" or "up"))
                    {
                        throw new MacroEditorException("Select a valid input action.");
                    }
                    if (item.Key is "WheelUp" or "WheelDown" && item.Action != "tap")
                    {
                        throw new MacroEditorException("Mouse wheel events can only use Tap.");
                    }
                    if (item.Action == "tap" && item.Key is not ("WheelUp" or "WheelDown") &&
                        item.DurationMs is < 0 or > 10_000)
                    {
                        throw new MacroEditorException("Tap duration must be between 0 and 10,000 ms.");
                    }
                    executableCount++;
                    break;

                case "delay":
                    if (item.DurationMs is < 1 or > MaximumDelayMilliseconds)
                    {
                        throw new MacroEditorException(
                            $"Delays must be between 1 and {MaximumDelayMilliseconds:N0} ms.");
                    }
                    executableCount++;
                    break;

                case "loop":
                    if (depth >= MaximumLoopDepth)
                    {
                        throw new MacroEditorException(
                            $"Loops can be nested up to {MaximumLoopDepth} levels.");
                    }
                    if (item.Count is < 0 or > MaximumLoopCount)
                    {
                        throw new MacroEditorException(
                            $"Loop count must be 0 (until released) or 1–{MaximumLoopCount:N0}.");
                    }
                    if (item.Children is null || item.Children.Count == 0)
                    {
                        throw new MacroEditorException("Each loop must contain at least one event.");
                    }
                    var executableCountBeforeLoop = executableCount;
                    ValidateEventList(
                        item.Children,
                        rawBlocks,
                        allowRaw,
                        depth + 1,
                        ref count,
                        ref executableCount);
                    if (executableCount == executableCountBeforeLoop)
                    {
                        throw new MacroEditorException(
                            "Each loop must contain an input, delay, loop, or advanced step.");
                    }
                    executableCount++;
                    break;

                case "note":
                    item.Text = NormalizeOptionalField(item.Text, 120, "A note is too long.");
                    if (item.Text.Length == 0)
                    {
                        throw new MacroEditorException("Notes cannot be empty.");
                    }
                    break;

                case "raw":
                    if (!allowRaw || string.IsNullOrWhiteSpace(item.RawId) ||
                        !rawBlocks.ContainsKey(item.RawId))
                    {
                        throw new MacroEditorException(
                            "An advanced step is no longer valid. Reopen the macro and try again.");
                    }
                    executableCount++;
                    break;

                default:
                    throw new MacroEditorException("The macro contains an unsupported event type.");
            }
        }
    }

    private static string RenderEvents(
        IReadOnlyList<MacroEditorEvent> events,
        IReadOnlyDictionary<string, string> rawBlocks,
        string newLine,
        string indent)
    {
        var builder = new StringBuilder();
        RenderEventList(builder, events, rawBlocks, newLine, indent);
        return builder.ToString().TrimEnd('\r', '\n');
    }

    private static void RenderEventList(
        StringBuilder builder,
        IReadOnlyList<MacroEditorEvent> events,
        IReadOnlyDictionary<string, string> rawBlocks,
        string newLine,
        string indent)
    {
        for (var index = 0; index < events.Count; index++)
        {
            var item = events[index];
            switch (item.Type)
            {
                case "input":
                    if (item.Action == "tap")
                    {
                        if (item.Key is "WheelUp" or "WheelDown")
                        {
                            AppendLine(builder, indent + $"SendInput, {{{item.Key}}}", newLine);
                        }
                        else if (item.DurationMs == 0)
                        {
                            AppendLine(builder, indent + $"SendInput, {{{item.Key}}}", newLine);
                        }
                        else
                        {
                            AppendLine(
                                builder,
                                indent + $"; @MM-Tap {item.Key} {item.DurationMs}",
                                newLine);
                            AppendLine(builder, indent + $"SendInput, {{{item.Key} down}}", newLine);
                            AppendPreciseDelay(builder, item.DurationMs, indent, newLine);
                            AppendLine(builder, indent + $"SendInput, {{{item.Key} up}}", newLine);
                        }
                    }
                    else
                    {
                        AppendLine(
                            builder,
                            indent + $"SendInput, {{{item.Key} {item.Action}}}",
                            newLine);
                    }
                    break;

                case "delay":
                    AppendPreciseDelay(builder, item.DurationMs, indent, newLine);
                    break;

                case "loop":
                    AppendLine(
                        builder,
                        indent + (item.Count == 0
                            ? "while (ShouldContinue()) {"
                            : $"Loop, {item.Count} {{"),
                        newLine);
                    RenderEventList(
                        builder,
                        item.Children,
                        rawBlocks,
                        newLine,
                        indent + "    ");
                    AppendLine(builder, indent + "}", newLine);
                    break;

                case "note":
                    AppendLine(builder, indent + "; " + item.Text, newLine);
                    break;

                case "raw":
                    AppendRawBlock(builder, rawBlocks[item.RawId], indent, newLine);
                    break;
            }

            if (index < events.Count - 1)
            {
                builder.Append(newLine);
            }
        }
    }

    private static void AppendPreciseDelay(
        StringBuilder builder,
        int milliseconds,
        string indent,
        string newLine)
    {
        AppendLine(builder, indent + $"if (!PreciseSleep({milliseconds}))", newLine);
        AppendLine(builder, indent + "    return", newLine);
    }

    private static void AppendRawBlock(
        StringBuilder builder,
        string raw,
        string indent,
        string newLine)
    {
        var lines = Regex.Split(raw.Trim('\r', '\n'), "\\r\\n|\\n|\\r");
        var nonEmpty = lines.Where(line => line.Trim().Length > 0).ToArray();
        var commonIndent = nonEmpty.Length == 0
            ? 0
            : nonEmpty.Min(CountLeadingWhitespace);

        foreach (var line in lines)
        {
            var normalized = line.Length >= commonIndent
                ? line[commonIndent..]
                : line.TrimStart();
            AppendLine(builder, indent + normalized, newLine);
        }
    }

    private static int CountLeadingWhitespace(string value)
    {
        var count = 0;
        while (count < value.Length && value[count] is ' ' or '\t')
        {
            count++;
        }
        return count;
    }

    private static void AppendLine(StringBuilder builder, string line, string newLine) =>
        builder.Append(line).Append(newLine);

    private string BuildGeneratedSource(
        string runtimeText,
        IReadOnlyList<MacroEditorEvent> events,
        string newLine)
    {
        runtimeText = NormalizeNewLines(runtimeText, newLine).TrimEnd('\r', '\n');
        var body = RenderEvents(events, new Dictionary<string, string>(), newLine, "    ");
        var generated = runtimeText + newLine + newLine
            + "; ===== END MACRO MANAGER RUNTIME =====" + newLine + newLine
            + "; Macro Manager visual macro v1" + newLine
            + "StartTimerResolution()" + newLine
            + "try {" + newLine
            + "    RunMacro()" + newLine
            + "} finally {" + newLine
            + "    ReleaseAll()" + newLine
            + "    StopTimerResolution()" + newLine
            + "}" + newLine
            + "ExitApp" + newLine + newLine
            + "RunMacro() {" + newLine
            + body + newLine
            + "}" + newLine;
        return EnsurePerformanceHeader(generated, newLine);
    }

    private static string BuildManifest(
        string comboId,
        string character,
        string image,
        string name,
        string description,
        string tag,
        string macroTrigger,
        string newLine) =>
        "[Macro]" + newLine
        + "Id=" + comboId + newLine
        + "Character=" + character + newLine
        + "Image=" + image + newLine
        + "Name=" + name + newLine
        + "Tooltip=" + description + newLine
        + "Tag=" + tag + newLine
        + "MacroTrigger=" + macroTrigger + newLine
        + "Source=source.ahk" + newLine
        + "ManagedPackage=1" + newLine
        + "EditorFormat=VisualMacroV1" + newLine
        + "PackageFormat=2" + newLine
        + "Version=2" + newLine;

    private static string EnsurePerformanceHeader(string source, string newLine)
    {
        var normalizedLines = Regex.Split(source, "\\r\\n|\\r|\\n")
            .Select(line => line.Trim())
            .Where(line => line.Length > 0 && !line.StartsWith(';'))
            .Select(line => Regex.Replace(line, @"[ \t]+", " "))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var missingLines = PerformanceHeaderLines
            .Where(line => !normalizedLines.Contains(Regex.Replace(line, @"[ \t]+", " ")))
            .ToArray();
        if (missingLines.Length == 0)
        {
            return source;
        }

        return string.Join(newLine, missingLines) + newLine + source;
    }

    private static FunctionSlice? FindEditableFunction(string source)
    {
        var marker = Regex.Match(
            source,
            @"(?im)^\s*;\s*@MacroManager-Entry:\s*([A-Za-z_][A-Za-z0-9_]*)\s*$");
        if (marker.Success)
        {
            var marked = FindFunction(source, marker.Groups[1].Value);
            if (marked is not null)
            {
                return marked;
            }
        }

        var runMacro = FindFunction(source, "RunMacro");
        if (runMacro is not null)
        {
            return runMacro;
        }

        var invoked = Regex.Match(
            source,
            @"(?is)\btry\s*\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*\)");
        if (invoked.Success)
        {
            var called = FindFunction(source, invoked.Groups[1].Value);
            if (called is not null)
            {
                return called;
            }
        }

        foreach (Match match in Regex.Matches(
                     source,
                     @"(?m)^[ \t]*(Run_[A-Za-z0-9_]+)\s*\([^\r\n]*\)\s*\{"))
        {
            var candidate = FindFunction(source, match.Groups[1].Value);
            if (candidate is not null)
            {
                return candidate;
            }
        }

        return null;
    }

    private static FunctionSlice? FindFunction(string source, string name)
    {
        var match = Regex.Match(
            source,
            $@"(?m)^(?<indent>[ \t]*){Regex.Escape(name)}\s*\([^\r\n]*\)\s*\{{[ \t]*(?:\r?\n|\r)");
        if (!match.Success)
        {
            return null;
        }

        var openingBrace = source.IndexOf('{', match.Index, match.Length);
        if (openingBrace < 0)
        {
            return null;
        }

        var closingBrace = FindMatchingBrace(source, openingBrace);
        if (closingBrace < 0)
        {
            return null;
        }

        var newLine = source.Contains("\r\n", StringComparison.Ordinal) ? "\r\n" : "\n";
        var functionIndent = match.Groups["indent"].Value;
        var bodyStart = openingBrace + 1;
        var body = source[bodyStart..closingBrace];
        return new FunctionSlice(
            bodyStart,
            closingBrace,
            body,
            newLine,
            functionIndent,
            functionIndent + "    ");
    }

    private static int FindMatchingBrace(string source, int openingBrace)
    {
        var depth = 0;
        var inString = false;
        var inComment = false;

        for (var index = openingBrace; index < source.Length; index++)
        {
            var character = source[index];
            if (inComment)
            {
                if (character is '\r' or '\n')
                {
                    inComment = false;
                }
                continue;
            }

            if (inString)
            {
                if (character == '`' && index + 1 < source.Length)
                {
                    index++;
                    continue;
                }
                if (character == '"')
                {
                    if (index + 1 < source.Length && source[index + 1] == '"')
                    {
                        index++;
                    }
                    else
                    {
                        inString = false;
                    }
                }
                continue;
            }

            if (character == ';')
            {
                inComment = true;
                continue;
            }
            if (character == '"')
            {
                inString = true;
                continue;
            }
            if (character == '{')
            {
                depth++;
            }
            else if (character == '}' && --depth == 0)
            {
                return index;
            }
        }

        return -1;
    }

    private static string UpdateIniSection(
        string text,
        string section,
        IReadOnlyDictionary<string, string> values)
    {
        var newLine = text.Contains("\r\n", StringComparison.Ordinal) ? "\r\n" : "\n";
        var sectionPattern = new Regex(
            $@"(?ms)^(?<header>\[{Regex.Escape(section)}\][ \t]*(?:\r?\n|\r))(?<body>.*?)(?=^\[|\z)");
        var match = sectionPattern.Match(text);
        if (!match.Success)
        {
            throw new MacroEditorException($"The [{section}] metadata section is missing.");
        }

        var body = match.Groups["body"].Value;
        foreach (var pair in values)
        {
            var keyPattern = new Regex(
                $@"(?m)^{Regex.Escape(pair.Key)}=.*?(?=\r?$)",
                RegexOptions.IgnoreCase);
            if (keyPattern.IsMatch(body))
            {
                body = keyPattern.Replace(
                    body,
                    _ => pair.Key + "=" + pair.Value,
                    1);
            }
            else
            {
                body = body.TrimEnd('\r', '\n') + newLine + pair.Key + "=" + pair.Value + newLine;
            }
        }

        return text[..match.Index]
            + match.Groups["header"].Value
            + body
            + text[(match.Index + match.Length)..];
    }

    private static List<RegistryMacro> ParseRegistry(string text)
    {
        var result = new List<RegistryMacro>();
        foreach (Match sectionMatch in Regex.Matches(
                     text,
                     @"(?ms)^\[(?<section>Combo\.[^\]]+)\][ \t]*\r?\n(?<body>.*?)(?=^\[|\z)"))
        {
            var values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (Match valueMatch in Regex.Matches(
                         sectionMatch.Groups["body"].Value,
                         @"(?m)^(?<key>[^=\r\n]+)=(?<value>.*)$"))
            {
                values[valueMatch.Groups["key"].Value.Trim()] =
                    valueMatch.Groups["value"].Value.TrimEnd('\r').Trim();
            }

            if (!values.TryGetValue("Id", out var id) ||
                !values.TryGetValue("Character", out var character) ||
                !values.TryGetValue("Name", out var name) ||
                !values.TryGetValue("Script", out var script))
            {
                continue;
            }

            _ = int.TryParse(values.GetValueOrDefault("Order"), out var order);
            result.Add(new RegistryMacro(
                sectionMatch.Groups["section"].Value,
                id,
                character,
                values.GetValueOrDefault("Image") ?? string.Empty,
                name,
                values.GetValueOrDefault("Tooltip") ?? string.Empty,
                values.GetValueOrDefault("Tag") ?? string.Empty,
                values.GetValueOrDefault("MacroTrigger") ?? string.Empty,
                script,
                values.GetValueOrDefault("BuiltIn") == "1",
                order));
        }

        return result;
    }

    private static bool RegistryContainsCharacter(
        string registryText,
        string character,
        IReadOnlyCollection<RegistryMacro>? macros = null)
    {
        if ((macros ?? ParseRegistry(registryText)).Any(item =>
                item.Character.Equals(character, StringComparison.Ordinal)))
        {
            return true;
        }

        return EnumerateCharacterSections(registryText).Any(item =>
            item.Name.Equals(character, StringComparison.Ordinal));
    }

    private static string GetRegisteredCharacterImage(string registryText, string character) =>
        EnumerateCharacterSections(registryText)
            .FirstOrDefault(item => item.Name.Equals(character, StringComparison.Ordinal))
            ?.Image ?? string.Empty;

    private static IEnumerable<RegistryCharacter> EnumerateCharacterSections(string text)
    {
        foreach (Match sectionMatch in Regex.Matches(
                     text,
                     @"(?ms)^\[(?<section>Character\.[^\]]+)\][ \t]*\r?\n(?<body>.*?)(?=^\[|\z)"))
        {
            var values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (Match valueMatch in Regex.Matches(
                         sectionMatch.Groups["body"].Value,
                         @"(?m)^(?<key>[^=\r\n]+)=(?<value>.*)$"))
            {
                values[valueMatch.Groups["key"].Value.Trim()] =
                    valueMatch.Groups["value"].Value.TrimEnd('\r').Trim();
            }

            if (values.TryGetValue("Name", out var name) && !string.IsNullOrWhiteSpace(name))
            {
                yield return new RegistryCharacter(
                    name,
                    values.GetValueOrDefault("Image") ?? string.Empty);
            }
        }
    }

    private string ResolveUserMacroPath(string relativePath)
    {
        if (string.IsNullOrWhiteSpace(relativePath) || Path.IsPathRooted(relativePath))
        {
            throw new MacroEditorException("The selected macro path is invalid.");
        }

        var normalized = relativePath.Replace('\\', Path.DirectorySeparatorChar)
            .Replace('/', Path.DirectorySeparatorChar);
        var fullPath = Path.GetFullPath(Path.Combine(_rootDirectory, normalized));
        if (!IsPathInside(fullPath, _userMacroRoot) || !File.Exists(fullPath))
        {
            throw new MacroEditorException("The selected macro file is outside Macros\\User or is missing.");
        }

        return fullPath;
    }

    private bool TryLoadVisualEditorSource(
        RegistryMacro macro,
        out string sourcePath,
        out string packageDirectory,
        out byte[] sourceBytes,
        out string sourceText,
        out FunctionSlice? function)
    {
        sourcePath = string.Empty;
        packageDirectory = string.Empty;
        sourceBytes = [];
        sourceText = string.Empty;
        function = null;

        if (macro.BuiltIn)
        {
            return false;
        }

        try
        {
            var scriptPath = ResolveUserMacroPath(macro.Script);
            packageDirectory = Path.GetDirectoryName(scriptPath) ?? string.Empty;
            if (packageDirectory.Length == 0)
            {
                return false;
            }

            sourcePath = ResolveEditableSourcePath(packageDirectory, scriptPath);
            sourceBytes = ReadBytes(sourcePath, MaximumSourceBytes);
            sourceText = DecodeText(sourceBytes);

            // This exact marker is emitted only by BuildGeneratedSource. Never
            // run the AHK event parser for imported or otherwise unknown code.
            if (!Regex.IsMatch(
                    sourceText,
                    @"(?im)^\s*;\s*Macro Manager visual macro v1\s*$"))
            {
                return false;
            }

            function = FindEditableFunction(sourceText);
            return function is not null;
        }
        catch (Exception exception) when (
            exception is MacroEditorException or IOException or UnauthorizedAccessException or
            InvalidDataException or ArgumentException or NotSupportedException)
        {
            sourcePath = string.Empty;
            packageDirectory = string.Empty;
            sourceBytes = [];
            sourceText = string.Empty;
            function = null;
            return false;
        }
    }

    private string TryResolvePackageDirectory(string relativeScriptPath)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(relativeScriptPath) ||
                Path.IsPathRooted(relativeScriptPath))
            {
                return string.Empty;
            }

            var normalized = relativeScriptPath
                .Replace('\\', Path.DirectorySeparatorChar)
                .Replace('/', Path.DirectorySeparatorChar);
            var scriptPath = Path.GetFullPath(Path.Combine(_rootDirectory, normalized));
            if (!IsPathInside(scriptPath, _rootDirectory) || !File.Exists(scriptPath))
            {
                return string.Empty;
            }

            return Path.GetDirectoryName(scriptPath) ?? string.Empty;
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException)
        {
            return string.Empty;
        }
    }

    private static string ResolveEditableSourcePath(string packageDirectory, string scriptPath)
    {
        var manifestPath = Path.Combine(packageDirectory, "manifest.ini");
        if (File.Exists(manifestPath))
        {
            var manifest = File.ReadAllText(manifestPath);
            var sourceMatch = Regex.Match(manifest, @"(?mi)^Source=(.+?)\s*$");
            if (sourceMatch.Success)
            {
                var candidate = Path.GetFullPath(Path.Combine(
                    packageDirectory,
                    sourceMatch.Groups[1].Value.Trim()
                        .Replace('\\', Path.DirectorySeparatorChar)
                        .Replace('/', Path.DirectorySeparatorChar)));
                if (IsPathInside(candidate, packageDirectory) && File.Exists(candidate))
                {
                    return candidate;
                }
            }
        }

        var conventionalSource = Path.Combine(packageDirectory, "source.ahk");
        return File.Exists(conventionalSource) ? conventionalSource : scriptPath;
    }

    private static bool IsPathInside(string candidate, string root)
    {
        var fullCandidate = Path.GetFullPath(candidate);
        var fullRoot = Path.GetFullPath(root).TrimEnd(
            Path.DirectorySeparatorChar,
            Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
        return fullCandidate.StartsWith(fullRoot, StringComparison.OrdinalIgnoreCase);
    }

    private static byte[] ReadBytes(string path, int maximumBytes)
    {
        var info = new FileInfo(path);
        if (!info.Exists)
        {
            throw new MacroEditorException("A required macro file is missing.");
        }
        if (info.Length <= 0 || info.Length > maximumBytes)
        {
            throw new MacroEditorException("The macro file is empty or too large for the visual editor.");
        }
        return File.ReadAllBytes(path);
    }

    private static string ReadTextFile(string path, int maximumBytes) =>
        DecodeText(ReadBytes(path, maximumBytes));

    private static string DecodeText(byte[] bytes)
    {
        if (bytes.Length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF)
        {
            return Encoding.UTF8.GetString(bytes, 3, bytes.Length - 3);
        }
        return Encoding.UTF8.GetString(bytes);
    }

    private static void AtomicWrite(string path, string content, Encoding encoding)
    {
        var directory = Path.GetDirectoryName(path)
            ?? throw new IOException("The destination directory is invalid.");
        Directory.CreateDirectory(directory);
        var temporaryPath = Path.Combine(
            directory,
            $".{Path.GetFileName(path)}.{Guid.NewGuid():N}.tmp");
        try
        {
            File.WriteAllText(temporaryPath, content, encoding);
            File.Move(temporaryPath, path, overwrite: true);
        }
        finally
        {
            if (File.Exists(temporaryPath))
            {
                File.Delete(temporaryPath);
            }
        }
    }

    private static void WriteWithRollback(params FileUpdate[] updates)
    {
        var completed = new List<FileUpdate>();
        try
        {
            foreach (var update in updates)
            {
                AtomicWrite(update.Path, update.UpdatedText, update.Encoding);
                completed.Add(update);
            }
        }
        catch
        {
            for (var index = completed.Count - 1; index >= 0; index--)
            {
                try
                {
                    var update = completed[index];
                    AtomicWrite(update.Path, update.OriginalText, update.Encoding);
                }
                catch
                {
                    // Preserve the first write failure; the backup text remains in memory only.
                }
            }
            throw;
        }
    }

    private static string NormalizeRequiredField(string? value, int maximumLength, string error)
    {
        var normalized = (value ?? string.Empty).Trim();
        if (normalized.Length is < 1 || normalized.Length > maximumLength ||
            Regex.IsMatch(normalized, @"[\r\n\t=|]"))
        {
            throw new MacroEditorException(error);
        }
        return normalized;
    }

    private static string NormalizeOptionalField(string? value, int maximumLength, string error)
    {
        var normalized = (value ?? string.Empty).Trim();
        if (normalized.Length > maximumLength || Regex.IsMatch(normalized, @"[\r\n\t=|]"))
        {
            throw new MacroEditorException(error);
        }
        return normalized;
    }

    private static string NormalizeEventId(string? value)
    {
        var normalized = (value ?? string.Empty).Trim();
        return Regex.IsMatch(normalized, @"^[A-Za-z0-9_-]{1,64}$")
            ? normalized
            : NewEventId();
    }

    private static string NormalizeKey(string? value)
    {
        var normalized = (value ?? string.Empty).Trim();
        var key = AllowedKeys.FirstOrDefault(item =>
            item.Equals(normalized, StringComparison.OrdinalIgnoreCase));
        return key ?? throw new MacroEditorException("Select a supported keyboard or mouse input.");
    }

    private static string BuildTag(string fpsTag, bool testing) =>
        fpsTag + (testing ? (fpsTag.Length > 0 ? ", TESTING" : "TESTING") : string.Empty);

    private static bool HasSameCatalogIdentity(
        RegistryMacro macro,
        string name,
        string description,
        string tag) =>
        macro.Name.Equals(name, StringComparison.OrdinalIgnoreCase) &&
        macro.Tooltip.Equals(description, StringComparison.OrdinalIgnoreCase) &&
        BuildTag(ExtractFpsTag(macro.Tag), HasTestingTag(macro.Tag))
            .Equals(tag, StringComparison.OrdinalIgnoreCase);

    private static string ExtractFpsTag(string tag)
    {
        var match = Regex.Match(tag ?? string.Empty, @"(?i)\b(60|120|240) FPS\b");
        return match.Success ? match.Groups[1].Value + " FPS" : string.Empty;
    }

    private static bool HasTestingTag(string tag) =>
        Regex.IsMatch(tag ?? string.Empty, @"(?i)(?:^|,\s*)TESTING(?:\s*,|$)");

    private static string Slug(string value)
    {
        var slug = Regex.Replace(value, @"[^A-Za-z0-9_-]+", "_").Trim('_');
        return slug.Length == 0 ? "macro" : slug;
    }

    private static MacroIdentity SelectIdentity(
        string character,
        string name,
        string packageRoot,
        IReadOnlyList<RegistryMacro> macros)
    {
        var packageBase = Slug(name);
        var idBase = Slug(character + "_" + name);
        for (var suffix = 1; suffix <= 1000; suffix++)
        {
            var suffixText = suffix == 1 ? string.Empty : "_" + suffix;
            var packageName = packageBase + suffixText;
            var comboId = idBase + suffixText;
            if (!Directory.Exists(Path.Combine(packageRoot, packageName)) &&
                !macros.Any(item => item.Id.Equals(comboId, StringComparison.OrdinalIgnoreCase)))
            {
                return new MacroIdentity(comboId, packageName);
            }
        }

        throw new MacroEditorException("Unable to create a unique macro name.");
    }

    private static string NormalizeNewLines(string value, string newLine) =>
        Regex.Replace(value, "\\r\\n|\\r|\\n", newLine);

    private static string NewEventId() => "event_" + Guid.NewGuid().ToString("N")[..12];

    private void TrimSessions()
    {
        while (_sessions.Count > 16)
        {
            _sessions.Remove(_sessions.Keys.First());
        }
    }

    private sealed class AhkEventParser
    {
        private readonly Dictionary<string, string> _rawBlocks;

        public AhkEventParser(Dictionary<string, string> rawBlocks)
        {
            _rawBlocks = rawBlocks;
        }

        public List<MacroEditorEvent> Parse(string body)
        {
            var lines = Regex.Split(body.Trim('\r', '\n'), "\\r\\n|\\n|\\r");
            return ParseBlock(lines, 0, lines.Length, 0);
        }

        private List<MacroEditorEvent> ParseBlock(string[] lines, int start, int end, int depth)
        {
            var events = new List<MacroEditorEvent>();
            var absoluteTargets = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            var index = start;

            while (index < end)
            {
                var trimmed = lines[index].Trim();
                if (trimmed.Length == 0)
                {
                    index++;
                    continue;
                }

                var timerOrigin = Regex.Match(
                    trimmed,
                    @"^(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*:=\s*QpcMs\(\)\s*$");
                if (timerOrigin.Success)
                {
                    absoluteTargets[timerOrigin.Groups["name"].Value] = 0;
                    var timingAnchorRawId = "raw_" + Guid.NewGuid().ToString("N");
                    _rawBlocks[timingAnchorRawId] = lines[index];
                    events.Add(new MacroEditorEvent
                    {
                        Id = NewEventId(),
                        Type = "raw",
                        RawId = timingAnchorRawId,
                        Summary = "Timing anchor",
                        TimingUnknown = false
                    });
                    index++;
                    continue;
                }

                var loop = ParseLoopHeader(trimmed);
                if (loop is not null)
                {
                    var closeIndex = FindBlockEnd(lines, index, end);
                    if (closeIndex > index && depth < MaximumLoopDepth)
                    {
                        events.Add(new MacroEditorEvent
                        {
                            Id = NewEventId(),
                            Type = "loop",
                            Count = loop.Value,
                            Children = ParseBlock(lines, index + 1, closeIndex, depth + 1)
                        });
                        index = closeIndex + 1;
                        continue;
                    }
                }

                var tapMarker = Regex.Match(
                    trimmed,
                    @"^;\s*@MM-Tap\s+(?<key>[A-Za-z0-9]+)\s+(?<duration>\d+)\s*$");
                if (tapMarker.Success &&
                    int.TryParse(tapMarker.Groups["duration"].Value, out var tapDuration) &&
                    TryNormalizeParsedKey(tapMarker.Groups["key"].Value, out var tapKey))
                {
                    events.Add(new MacroEditorEvent
                    {
                        Id = NewEventId(),
                        Type = "input",
                        Key = tapKey,
                        Action = "tap",
                        DurationMs = tapDuration
                    });
                    index = SkipGeneratedTap(lines, index + 1, end, tapKey);
                    continue;
                }

                if (TryParseInput(trimmed, out var inputKey, out var inputAction))
                {
                    events.Add(new MacroEditorEvent
                    {
                        Id = NewEventId(),
                        Type = "input",
                        Key = inputKey,
                        Action = inputAction,
                        DurationMs = 0
                    });
                    index++;
                    continue;
                }

                if (TryParseDelay(
                        lines,
                        index,
                        end,
                        absoluteTargets,
                        out var delay,
                        out var consumed))
                {
                    if (delay > 0)
                    {
                        events.Add(new MacroEditorEvent
                        {
                            Id = NewEventId(),
                            Type = "delay",
                            DurationMs = delay
                        });
                    }
                    index += consumed;
                    continue;
                }

                if (trimmed.StartsWith(';'))
                {
                    var note = trimmed.TrimStart(';').Trim();
                    if (note.Length is > 0 and <= 120 &&
                        !note.StartsWith("=====", StringComparison.Ordinal))
                    {
                        events.Add(new MacroEditorEvent
                        {
                            Id = NewEventId(),
                            Type = "note",
                            Text = note
                        });
                        index++;
                        continue;
                    }
                }

                var rawEnd = FindRawEnd(lines, index, end);
                var raw = string.Join("\n", lines[index..rawEnd]);
                var rawId = "raw_" + Guid.NewGuid().ToString("N");
                _rawBlocks[rawId] = raw;
                events.Add(new MacroEditorEvent
                {
                    Id = NewEventId(),
                    Type = "raw",
                    RawId = rawId,
                    Summary = SummarizeRaw(trimmed),
                    TimingUnknown = RawMayAffectTiming(raw)
                });
                index = rawEnd;
            }

            return events;
        }

        private static int? ParseLoopHeader(string line)
        {
            if (Regex.IsMatch(line, @"^while\s*\(\s*ShouldContinue\(\)\s*\)\s*\{\s*$", RegexOptions.IgnoreCase))
            {
                return 0;
            }

            var finite = Regex.Match(line, @"^Loop\s*,?\s*(\d+)\s*\{\s*$", RegexOptions.IgnoreCase);
            return finite.Success && int.TryParse(finite.Groups[1].Value, out var count)
                ? count
                : null;
        }

        private static int FindBlockEnd(string[] lines, int start, int end)
        {
            var depth = 0;
            for (var index = start; index < end; index++)
            {
                var (open, close) = CountBraces(lines[index]);
                depth += open - close;
                if (index > start && depth <= 0)
                {
                    return index;
                }
            }
            return -1;
        }

        private static (int Open, int Close) CountBraces(string line)
        {
            var open = 0;
            var close = 0;
            var inString = false;
            for (var index = 0; index < line.Length; index++)
            {
                var character = line[index];
                if (character == '`' && inString && index + 1 < line.Length)
                {
                    index++;
                    continue;
                }
                if (character == '"')
                {
                    inString = !inString;
                    continue;
                }
                if (!inString && character == ';')
                {
                    break;
                }
                if (!inString && character == '{') open++;
                if (!inString && character == '}') close++;
            }
            return (open, close);
        }

        private static bool TryParseInput(string line, out string key, out string action)
        {
            var helper = Regex.Match(
                line,
                @"^(?<key>L|R|Q|E|W|Shift|A|D|F)_(?<action>Down|Up)\(\)\s*$",
                RegexOptions.IgnoreCase);
            if (helper.Success)
            {
                key = helper.Groups["key"].Value.ToUpperInvariant() switch
                {
                    "L" => "LButton",
                    "R" => "RButton",
                    "SHIFT" => "Shift",
                    var value => value
                };
                action = helper.Groups["action"].Value.ToLowerInvariant();
                return true;
            }

            var send = Regex.Match(
                line,
                @"^Send(?:Input)?\s*,?\s*\{(?<key>[A-Za-z0-9]+)(?:\s+(?<action>down|up))?\}\s*$",
                RegexOptions.IgnoreCase);
            if (send.Success && TryNormalizeParsedKey(send.Groups["key"].Value, out key))
            {
                action = send.Groups["action"].Success
                    ? send.Groups["action"].Value.ToLowerInvariant()
                    : "tap";
                return true;
            }

            key = string.Empty;
            action = string.Empty;
            return false;
        }

        private static bool TryNormalizeParsedKey(string value, out string key)
        {
            key = AllowedKeys.FirstOrDefault(item =>
                item.Equals(value, StringComparison.OrdinalIgnoreCase)) ?? string.Empty;
            return key.Length > 0;
        }

        private static bool TryParseDelay(
            string[] lines,
            int index,
            int end,
            Dictionary<string, int> absoluteTargets,
            out int delay,
            out int consumed)
        {
            var line = lines[index].Trim();
            delay = 0;
            consumed = 0;

            var precise = Regex.Match(
                line,
                @"^(?:if\s*\(\s*!)?PreciseSleep(?:Held)?\(\s*(\d+)\s*\)\s*\)?\s*$",
                RegexOptions.IgnoreCase);
            if (!precise.Success)
            {
                precise = Regex.Match(
                    line,
                    @"^if\s+!PreciseSleep(?:Held)?\(\s*(\d+)\s*\)\s*$",
                    RegexOptions.IgnoreCase);
            }
            if (!precise.Success)
            {
                precise = Regex.Match(line, @"^Sleep\s*,\s*(\d+)\s*$", RegexOptions.IgnoreCase);
            }
            if (precise.Success && int.TryParse(precise.Groups[1].Value, out delay))
            {
                consumed = 1 + ConsumeFollowingReturn(lines, index + 1, end);
                return delay is >= 1 and <= MaximumDelayMilliseconds;
            }

            var wait = Regex.Match(
                line,
                @"^if\s*\(\s*!WaitUntil\(\s*(?<origin>[A-Za-z_][A-Za-z0-9_]*)\s*\+\s*(?<target>\d+)\s*\)\s*\)\s*$",
                RegexOptions.IgnoreCase);
            var conditionalWait = wait.Success;
            if (!wait.Success)
            {
                wait = Regex.Match(
                    line,
                    @"^WaitUntil\(\s*(?<origin>[A-Za-z_][A-Za-z0-9_]*)\s*\+\s*(?<target>\d+)\s*\)\s*$",
                    RegexOptions.IgnoreCase);
            }
            if (wait.Success &&
                absoluteTargets.TryGetValue(wait.Groups["origin"].Value, out var previous) &&
                int.TryParse(wait.Groups["target"].Value, out var target))
            {
                delay = Math.Max(0, target - previous);
                absoluteTargets[wait.Groups["origin"].Value] = Math.Max(previous, target);
                consumed = 1 + (conditionalWait
                    ? ConsumeFollowingReturn(lines, index + 1, end)
                    : 0);
                return delay <= MaximumDelayMilliseconds;
            }

            return false;
        }

        private static int ConsumeFollowingReturn(string[] lines, int index, int end)
        {
            var consumed = 0;
            while (index + consumed < end && lines[index + consumed].Trim().Length == 0)
            {
                consumed++;
            }
            if (index + consumed < end &&
                Regex.IsMatch(
                    lines[index + consumed].Trim(),
                    @"^return(?:\s+(?:false|true))?\s*$",
                    RegexOptions.IgnoreCase))
            {
                consumed++;
            }
            return consumed;
        }

        private static int SkipGeneratedTap(string[] lines, int index, int end, string key)
        {
            var expectedDown = new Regex(
                $@"^SendInput\s*,?\s*\{{{Regex.Escape(key)}\s+down\}}\s*$",
                RegexOptions.IgnoreCase);
            var expectedUp = new Regex(
                $@"^SendInput\s*,?\s*\{{{Regex.Escape(key)}\s+up\}}\s*$",
                RegexOptions.IgnoreCase);

            if (index >= end || !expectedDown.IsMatch(lines[index].Trim()))
            {
                return index;
            }
            index++;
            var dummyTargets = new Dictionary<string, int>();
            if (!TryParseDelay(lines, index, end, dummyTargets, out _, out var delayLines))
            {
                return index;
            }
            index += delayLines;
            while (index < end && lines[index].Trim().Length == 0) index++;
            return index < end && expectedUp.IsMatch(lines[index].Trim()) ? index + 1 : index;
        }

        private static int FindRawEnd(string[] lines, int start, int end)
        {
            var (open, close) = CountBraces(lines[start]);
            if (open > close)
            {
                var blockEnd = FindBlockEnd(lines, start, end);
                return blockEnd > start ? blockEnd + 1 : start + 1;
            }

            var index = start + 1;
            while (index < end)
            {
                var trimmed = lines[index].Trim();
                if (trimmed.Length == 0 || IsKnownStart(trimmed))
                {
                    break;
                }
                index++;
            }
            return index;
        }

        private static bool IsKnownStart(string line) =>
            line.StartsWith(';') ||
            ParseLoopHeader(line) is not null ||
            Regex.IsMatch(line, @"^[A-Za-z_][A-Za-z0-9_]*\s*:=\s*QpcMs\(\)") ||
            Regex.IsMatch(line, @"^(?:if\s*\(\s*!)?PreciseSleep") ||
            Regex.IsMatch(line, @"^(?:if\s*\(\s*!)?WaitUntil") ||
            Regex.IsMatch(line, @"^Sleep\s*,", RegexOptions.IgnoreCase) ||
            Regex.IsMatch(line, @"^(?:L|R|Q|E|W|Shift|A|D|F)_(?:Down|Up)\(\)", RegexOptions.IgnoreCase) ||
            Regex.IsMatch(line, @"^Send(?:Input)?\s*,?\s*\{", RegexOptions.IgnoreCase);

        private static string SummarizeRaw(string line)
        {
            if (Regex.IsMatch(line, @"^(?:local\s+)?[A-Za-z_][A-Za-z0-9_]*\s*:=", RegexOptions.IgnoreCase))
            {
                return "Advanced setup";
            }

            var call = Regex.Match(line, @"(?:!|\b)(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*\(");
            if (call.Success)
            {
                var words = Regex.Replace(call.Groups["name"].Value, "([a-z])([A-Z])", "$1 $2")
                    .Replace('_', ' ');
                return words.Length <= 64 ? words : "Advanced action";
            }

            return "Preserved advanced step";
        }

        private static bool RawMayAffectTiming(string raw)
        {
            var meaningfulLines = Regex.Split(raw, "\\r\\n|\\n|\\r")
                .Select(line => line.Trim())
                .Where(line => line.Length > 0 && !line.StartsWith(';'))
                .ToArray();
            if (meaningfulLines.Length > 0 && meaningfulLines.All(line =>
                    Regex.IsMatch(
                        line,
                        @"^local\s+[A-Za-z_][A-Za-z0-9_]*(?:\s*,\s*[A-Za-z_][A-Za-z0-9_]*)*\s*$",
                        RegexOptions.IgnoreCase)))
            {
                return false;
            }

            return meaningfulLines.Length != 2 ||
                !Regex.IsMatch(
                    meaningfulLines[0],
                    @"^if\s*\(\s*!ShouldContinue\(\)\s*\)\s*$",
                    RegexOptions.IgnoreCase) ||
                !Regex.IsMatch(meaningfulLines[1], @"^return\s*$", RegexOptions.IgnoreCase);
        }
    }

    private sealed record EditSession(
        string SessionId,
        string ComboId,
        string Character,
        string SourcePath,
        string PackageDirectory,
        string SourceHash,
        string SourceText,
        FunctionSlice? Function,
        Dictionary<string, string> RawBlocks,
        bool CanEditEvents)
    {
        public static EditSession ForMetadataOnly(
            string sessionId,
            string comboId,
            string character,
            string packageDirectory) =>
            new(
                sessionId,
                comboId,
                character,
                string.Empty,
                packageDirectory,
                string.Empty,
                string.Empty,
                null,
                new Dictionary<string, string>(StringComparer.Ordinal),
                CanEditEvents: false);
    }

    private sealed record FunctionSlice(
        int BodyStart,
        int BodyEnd,
        string Body,
        string NewLine,
        string FunctionIndent,
        string BodyIndent);

    private sealed record RegistryMacro(
        string Section,
        string Id,
        string Character,
        string Image,
        string Name,
        string Tooltip,
        string Tag,
        string MacroTrigger,
        string Script,
        bool BuiltIn,
        int Order);

    private sealed record RegistryCharacter(string Name, string Image);

    private sealed record MacroMetadata(
        string Name,
        string Description,
        string FpsTag,
        bool Testing,
        string MacroTrigger);

    private sealed record MacroIdentity(string ComboId, string PackageName);

    private sealed record FileUpdate(
        string Path,
        string UpdatedText,
        Encoding Encoding,
        string OriginalText);
}

internal sealed class MacroEditorDocument
{
    public string SessionId { get; set; } = string.Empty;
    public string Mode { get; set; } = string.Empty;
    public string ComboId { get; set; } = string.Empty;
    public string Character { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string FpsTag { get; set; } = string.Empty;
    public bool Testing { get; set; }
    public string MacroTrigger { get; set; } = string.Empty;
    public bool CanSave { get; set; }
    public bool CanEditEvents { get; set; }
    public List<MacroEditorEvent> Events { get; set; } = [];
    public List<string> Warnings { get; set; } = [];
}

internal sealed class MacroEditorEvent
{
    public string Id { get; set; } = string.Empty;
    public string Type { get; set; } = string.Empty;
    public string Key { get; set; } = string.Empty;
    public string Action { get; set; } = string.Empty;
    public int DurationMs { get; set; }
    public int Count { get; set; }
    public string Text { get; set; } = string.Empty;
    public string RawId { get; set; } = string.Empty;
    public string Summary { get; set; } = string.Empty;
    public bool TimingUnknown { get; set; } = true;
    public List<MacroEditorEvent> Children { get; set; } = [];
}

internal sealed class MacroEditorSaveRequest
{
    public string SessionId { get; set; } = string.Empty;
    public string ComboId { get; set; } = string.Empty;
    public string Character { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string FpsTag { get; set; } = string.Empty;
    public bool Testing { get; set; }
    public string MacroTrigger { get; set; } = string.Empty;
    public List<MacroEditorEvent> Events { get; set; } = [];
}

internal sealed class MacroSaveResult
{
    public string ComboId { get; set; } = string.Empty;
    public string Character { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public bool Created { get; set; }
    public string Message { get; set; } = string.Empty;
}

internal sealed class MacroEditorException : Exception
{
    public MacroEditorException(string message)
        : base(message)
    {
    }
}
