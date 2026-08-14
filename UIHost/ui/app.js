const bridge = window.chrome?.webview;

const communityLinks = {
  github: "https://github.com/3azf55/GI-Macro-Manager",
  discord: "https://discord.gg/H8HNhvqqm"
};

const releasesUrl = "https://github.com/3azf55/GI-Macro-Manager/releases";

const THEME_STORAGE_KEY = "umm-theme";
const UPDATE_REMINDER_STORAGE_KEY = "umm-update-reminder";
const UPDATE_REMINDER_DELAY_MS = 6 * 60 * 60 * 1000;

let buildInfo = {
  version: "—",
  buildDate: "—"
};

let updateState = {
  status: "idle",
  message: "Check GitHub for new releases.",
  currentVersion: "",
  latestVersion: "",
  releaseName: "",
  releaseNotes: "",
  releaseUrl: releasesUrl,
  canInstall: false,
  progress: null
};

let lastAnnouncedUpdate = "";
const promptedUpdateVersions = new Set();

const translations = {
  controlCenter: "CONTROL CENTER",
  dashboardTitle: "Dashboard",
  applicationMode: "APPLICATION MODE",
  soundFeedback: "SOUND FEEDBACK",
  quickControls: "QUICK CONTROLS",
  skipDialogBehavior: "SKIP DIALOG BEHAVIOR",
  characterLibrary: "CHARACTER LIBRARY",
  charactersTitle: "Characters & Combos",
  activeCharacter: "ACTIVE CHARACTER",
  inputSettings: "INPUT SETTINGS",
  hotkeysTitle: "Hotkeys",
  hotkeyInfo: "Gameplay keys and duplicate assignments are rejected.",
  hotkeyScopeEyebrow: "ACTIVATION SCOPE",
  hotkeyScopeTitle: "Where hotkeys work",
  hotkeyScopeHelp: "Choose whether the configured hotkeys respond everywhere or only while the game window is focused.",
  fpsSettings: "FRAME LIMITER",
  fpsTitle: "FPS",
  fpsUnlockerEyebrow: "FPS UNLOCKER",
  fpsLimiterTitle: "Frame-rate limiter",
  fpsRiskTooltip: "This feature modifies game memory and may carry compatibility or account risk.",
  launchSettings: "LAUNCH SETTINGS",
  startupTitle: "Startup application",
  selectedExecutable: "SELECTED EXECUTABLE",
  projectCommunity: "PROJECT & COMMUNITY",
  aboutTitle: "About",
  aboutDescription: "A configurable macro manager for Windows.",
  githubDescription: "Project source and releases",
  discordDescription: "Community and support",
  updatesTitle: "Updates",
  updatesIdle: "Check GitHub for new releases.",
  checkUpdates: "Check for updates",
  installUpdate: "Download & install",
  viewRelease: "View release",
  releaseNotes: "Release notes",
  versionLabel: "Version",
  builtLabel: "Built",
  captureHotkey: "CAPTURE HOTKEY",
  pressKey: "Press a key",
  hotkeyModalHelp: "Press a keyboard key or a mouse side button. Press Escape to cancel.",
  buildInformation: "Build information",
  openGithub: "Open GitHub project",
  openDiscord: "Open Discord community",
  enabled: "Enabled",
  muted: "Muted",
  characterCombos: "Character combos",
  skipDialogs: "Skip dialogs",
  untilAnyKey: "Until any key pressed",
  untilTriggerReleased: "Until trigger released",
  dialogAutomation: "DIALOG AUTOMATION",
  selected: "SELECTED",
  noExecutable: "No executable selected",
  executableHelp: "Choose the game executable that should start with the macro engine.",
  webviewUnavailable: "WebView2 messaging is unavailable.",
  engineRejected: "The engine rejected the request.",
  releaseBeforeHotkeys: "Release the macro trigger before changing hotkeys.",
  changeHotkeyTitle: "Change {name} hotkey",
  releaseBeforeReset: "Release the macro trigger before resetting hotkeys.",
  resetHotkeysTitle: "Reset hotkeys to their defaults",
  newKey: "New {name} key",
  unsupported: "Unsupported",
  addCommunityUrl: "Add the {name} URL in ui/app.js first.",
  copyright: "© {year} Macro Manager. All rights reserved."
};

function t(key, variables = {}) {
  let value = translations[key] ?? key;

  Object.entries(variables).forEach(([name, replacement]) => {
    value = value.replaceAll(`{${name}}`, replacement);
  });

  return value;
}

function applyStaticTranslations() {
  $$("[data-i18n]").forEach(element => {
    element.textContent = t(element.dataset.i18n);
  });

  $$("[data-i18n-aria]").forEach(element => {
    element.setAttribute("aria-label", t(element.dataset.i18nAria));
  });
}

let characterCatalog = {};

let catalogJsonCache = "";
let macroEditorDocument = null;
let macroEditorSaving = false;
let macroEditorPending = false;
let macroEventDragId = "";
let macroEventDragIds = [];
let macroEventSelection = new Set();
let macroEventSelectionAnchor = "";
let collapsedMacroLoops = new Set();
let macroPreviewRunning = false;
let macroEventUndoStack = [];
let macroEventRedoStack = [];
let macroEventHistoryKey = "";
let macroEventHistoryTime = 0;
let macroEventAnimationFrame = 0;
let macroDeleteTarget = null;
let macroRecordingState = {
  available: false,
  recording: false,
  sessionId: "",
  elapsedMs: 0,
  capacityTrimmed: false,
  settings: {
    lastWindowEnabled: true,
    windowSeconds: 30,
    toggleHotkey: "F7",
    allowedKeys: []
  },
  transitions: []
};
let macroRecordingBaseline = null;
let macroRecordingSettingsTimer = 0;

const macroEditorKeys = [
  ["LButton", "Left mouse"], ["RButton", "Right mouse"], ["MButton", "Middle mouse"],
  ["WheelUp", "Wheel up"], ["WheelDown", "Wheel down"],
  ["Q", "Q"], ["E", "E"], ["R", "R"], ["F", "F"],
  ["W", "W"], ["A", "A"], ["S", "S"], ["D", "D"],
  ["Shift", "Shift"], ["Space", "Space"],
  ["1", "1"], ["2", "2"], ["3", "3"], ["4", "4"], ["5", "5"]
];

const hotkeyCatalog = [
  { target: "Trigger", title: "Trigger", description: "Run the selected action", stateKey: "triggerKey" },
  { target: "ModeToggle", title: "Mode", description: "Switch application mode", stateKey: "modeToggleKey" },
  { target: "CharacterToggle", title: "Character", description: "Cycle through characters", stateKey: "characterToggleKey" },
  { target: "ComboToggle", title: "Combo", description: "Cycle the current character combos", stateKey: "comboToggleKey" },
  { target: "Interface", title: "Interface", description: "Open Macro Manager above the game", stateKey: "interfaceKey" },
  { target: "Recorder", title: "Recorder", description: "Start or stop recording while a macro editor is open", stateKey: "recorderHotkey" }
];

let state = {
  soundsEnabled: true,
  macroRunning: false,
  hotkeyScope: "GameOnly",
  appMode: "CharacterCombos",
  skipStopMode: "Release",
  character: "",
  combo: "",
  comboDisplay: "—",
  catalogJson: "",
  triggerKey: "—",
  comboToggleKey: "—",
  characterToggleKey: "—",
  modeToggleKey: "—",
  interfaceKey: "F11",
  recorderHotkey: "F7",
  autoLaunchPath: "",
  autoLaunchEnabled: true,
  fpsEnabled: false,
  fpsTarget: 120,
  fpsStatus: "disabled",
  fpsMessage: "Enable the limiter, then start the game.",
  fpsAvailable: false,
  version: "—"
};

let captureTarget = null;
let fpsTargetCommitTimer = 0;
let fpsTargetEditing = false;

const COMBO_LONG_PRESS_MS = 450;
const COMBO_PRESS_MOVE_TOLERANCE = 8;
let comboPressState = null;
let suppressComboClickUntil = 0;
let stateRequestPending = false;
let stateRequestTimer = 0;
let lastLegacyErrorMessage = "";
let lastLegacyErrorAt = 0;
let lastToastSignature = "";
let lastToastAt = 0;

const STATE_REQUEST_COOLDOWN_MS = 1200;
const DUPLICATE_TOAST_WINDOW_MS = 1200;
const MAX_VISIBLE_TOASTS = 3;

const $ = selector => document.querySelector(selector);
const $$ = selector => [...document.querySelectorAll(selector)];

function post(action, payload = {}) {
  if (!bridge) {
    showToast(t("webviewUnavailable"), true);
    return false;
  }
  bridge.postMessage({ action, ...payload });
  return true;
}

function requestState() {
  if (stateRequestPending) return;

  stateRequestPending = true;
  if (!post("requestState")) {
    stateRequestPending = false;
    return;
  }

  window.clearTimeout(stateRequestTimer);
  stateRequestTimer = window.setTimeout(() => {
    stateRequestPending = false;
    stateRequestTimer = 0;
  }, STATE_REQUEST_COOLDOWN_MS);
}

function completeStateRequest() {
  stateRequestPending = false;
  window.clearTimeout(stateRequestTimer);
  stateRequestTimer = 0;
}

function boolValue(value) {
  return value === true || value === 1 || value === "1" || String(value).toLowerCase() === "true";
}

function parseEngineUtc(value) {
  const match = /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$/.exec(String(value || ""));
  if (!match) return Number.NaN;

  return Date.UTC(
    Number(match[1]),
    Number(match[2]) - 1,
    Number(match[3]),
    Number(match[4]),
    Number(match[5]),
    Number(match[6])
  );
}

function isFreshNotice(message) {
  const createdAt = parseEngineUtc(message.createdUtc);
  if (!Number.isFinite(createdAt)) return false;

  const age = Date.now() - createdAt;
  return age >= -5000 && age <= 15000;
}

const LAST_NOTICE_ID_KEY = "umm.lastNoticeId";

function shouldShowNotice(message) {
  const noticeId = String(message.noticeId || "").trim();

  if (!noticeId) {
    // Old events from pre-v1.4.1 builds are shown only when genuinely fresh.
    return isFreshNotice(message);
  }

  try {
    const lastNoticeId = localStorage.getItem(LAST_NOTICE_ID_KEY);
    if (lastNoticeId === noticeId) return false;
    localStorage.setItem(LAST_NOTICE_ID_KEY, noticeId);
  } catch {
    // Continue with in-memory freshness behavior when storage is unavailable.
    return isFreshNotice(message);
  }

  return true;
}

const LAST_ERROR_ID_KEY = "umm.lastErrorId";

function shouldShowError(message) {
  const errorId = String(message.errorId || "").trim();

  if (errorId) {
    try {
      const lastErrorId = localStorage.getItem(LAST_ERROR_ID_KEY);
      if (lastErrorId === errorId) return false;
      localStorage.setItem(LAST_ERROR_ID_KEY, errorId);
      return true;
    } catch {
      return isFreshNotice(message);
    }
  }

  // Older engines do not attach an error ID. Suppress only an immediate
  // duplicate delivered through both WM_COPYDATA and bridge/error.txt.
  const errorMessage = String(message.message || t("engineRejected"));
  const now = Date.now();
  if (errorMessage === lastLegacyErrorMessage && now - lastLegacyErrorAt <= DUPLICATE_TOAST_WINDOW_MS) {
    return false;
  }

  lastLegacyErrorMessage = errorMessage;
  lastLegacyErrorAt = now;
  return true;
}

function applyMessage(message) {
  if (message.type === "macroEditorDocument") {
    macroEditorPending = false;
    openMacroEditorDocument(message.document);
    renderCharacters();
    return;
  }

  if (message.type === "macroEditorSaved") {
    const refreshQueued = boolValue(message.refreshQueued);
    macroEditorSaving = false;
    closeMacroEditor(true);
    showToast(message.message || (message.created ? "Macro created." : "Macro saved."));
    if (!refreshQueued) {
      showToast("The file was saved. Restart Macro Manager to refresh the library.", true);
    }
    requestState();
    return;
  }

  if (message.type === "macroEditorError") {
    macroEditorPending = false;
    setMacroEditorSaving(false);
    showToast(message.message || "The macro could not be saved.", true);
    renderCharacters();
    return;
  }

  if (message.type === "macroRecordingState") {
    applyMacroRecordingSnapshot(message.snapshot);
    return;
  }

  if (message.type === "macroPreviewState") {
    macroPreviewRunning = boolValue(message.running);
    renderMacroPreviewButton();
    if (message.message) showToast(String(message.message), boolValue(message.error));
    return;
  }

  if (message.type === "windowState") {
    const maximized = boolValue(message.maximized);
    document.documentElement.classList.toggle("window-maximized", maximized);
    const button = $('[data-window-action="maximize"]');
    if (button) {
      button.setAttribute("aria-pressed", String(maximized));
      button.setAttribute("aria-label", maximized ? "Restore interface" : "Maximize interface");
      button.title = maximized ? "Restore interface" : "Maximize interface";
    }
    return;
  }

  if (message.type === "state") {
    completeStateRequest();

    if (message.catalogJson && message.catalogJson !== catalogJsonCache) {
      try {
        const parsedCatalog = JSON.parse(message.catalogJson);
        if (parsedCatalog && typeof parsedCatalog === "object") {
          characterCatalog = parsedCatalog;
          catalogJsonCache = message.catalogJson;
          const characterGrid = $("#characterGrid");
          characterGrid.innerHTML = "";
          delete characterGrid.dataset.initialized;
          const comboList = $("#comboList");
          comboList.innerHTML = "";
          delete comboList.dataset.character;
        }
      } catch {
        showToast("The macro catalog could not be read.", true);
      }
    }

    state = {
      ...state,
      ...message,
      soundsEnabled: boolValue(message.soundsEnabled),
      macroRunning: boolValue(message.macroRunning),
      autoLaunchEnabled: boolValue(message.autoLaunchEnabled)
    };
    render();
    return;
  }

  if (message.type === "fpsState") {
    const parsedTarget = Number(message.fpsTarget);
    state = {
      ...state,
      fpsEnabled: boolValue(message.fpsEnabled),
      fpsTarget: Number.isFinite(parsedTarget) ? Math.min(420, Math.max(10, Math.round(parsedTarget))) : state.fpsTarget,
      fpsStatus: String(message.fpsStatus || "disabled"),
      fpsMessage: String(message.fpsMessage || ""),
      fpsAvailable: boolValue(message.fpsAvailable)
    };
    renderFps();
    return;
  }

  if (message.type === "updateStatus") {
    updateState = {
      ...updateState,
      ...message,
      canInstall: boolValue(message.canInstall),
      progress: message.progress === "" || message.progress == null
        ? null
        : Number(message.progress)
    };

    renderUpdateStatus();

    const manual = boolValue(message.manual);
    if (message.status === "available" && message.latestVersion) {
      if (lastAnnouncedUpdate !== message.latestVersion) {
        lastAnnouncedUpdate = message.latestVersion;
        showToast(`${message.latestVersion} is available.`);
      }
      if (!manual) maybeShowUpdatePrompt(message);
    } else if (message.status === "installed") {
      clearUpdateReminder();
      showToast(message.message || "Update installed successfully.");
    } else if (message.status === "error" && manual) {
      showToast(message.message || "The update operation failed.", true);
    } else if (message.status === "current" && manual) {
      showToast(message.message || "Macro Manager is up to date.");
    } else if (message.status === "noRelease" && manual) {
      showToast(message.message || "No published release is available.", true);
    }
    return;
  }

  if (message.type === "error") {
    if (shouldShowError(message)) {
      showToast(message.message || t("engineRejected"), true);
    }
    if (message.errorCode !== "INVALID_BRIDGE_PAYLOAD" &&
        message.errorCode !== "UNSUPPORTED_BRIDGE_ACTION") {
      requestState();
    }
    return;
  }

  if (message.type === "notice") {
    // Each success event has a stable ID. It is shown once, even if the host
    // rereads bridge/error.txt or the interface is reopened immediately.
    if (shouldShowNotice(message)) {
      showToast(message.message || "Done");
    }
    requestState();
    return;
  }

}

function readUpdateReminder() {
  try {
    const value = JSON.parse(localStorage.getItem(UPDATE_REMINDER_STORAGE_KEY) || "null");
    if (!value || typeof value !== "object") return null;
    return {
      version: String(value.version || ""),
      remindAfter: Number(value.remindAfter || 0)
    };
  } catch {
    return null;
  }
}

function clearUpdateReminder() {
  try {
    localStorage.removeItem(UPDATE_REMINDER_STORAGE_KEY);
  } catch {
    // An unavailable storage area must not block update actions.
  }
}

function snoozeAvailableUpdate() {
  const version = String(updateState.latestVersion || "").trim();
  if (version) {
    try {
      localStorage.setItem(UPDATE_REMINDER_STORAGE_KEY, JSON.stringify({
        version,
        remindAfter: Date.now() + UPDATE_REMINDER_DELAY_MS
      }));
    } catch {
      // The prompt still closes when storage is unavailable.
    }
  }

  closeUpdatePrompt();
}

function maybeShowUpdatePrompt(message) {
  const version = String(message.latestVersion || "").trim();
  if (!version || promptedUpdateVersions.has(version)) return;

  const reminder = readUpdateReminder();
  if (reminder?.version === version && reminder.remindAfter > Date.now()) return;

  if (reminder && reminder.version !== version) clearUpdateReminder();
  promptedUpdateVersions.add(version);

  $("#updatePromptVersion").textContent = version;
  $("#updatePromptTitle").textContent = `${version} is ready`;
  $("#updatePromptDescription").textContent = updateState.canInstall
    ? "Update Macro Manager now to get the latest improvements and fixes. The application will restart automatically."
    : "A new release is available. Open the release page to download the latest version.";

  renderUpdatePromptAction();
  $("#updatePromptModal").classList.remove("hidden");
  window.setTimeout(() => $("#updateNowButton").focus(), 0);
}

function renderUpdatePromptAction() {
  const updateButton = $("#updateNowButton");
  if (!updateButton) return;

  updateButton.textContent = updateState.canInstall ? "Update now" : "Open release";
  updateButton.disabled = updateState.canInstall && state.macroRunning;
  updateButton.title = updateButton.disabled
    ? "Release the macro trigger before installing the update."
    : "";
}

function closeUpdatePrompt() {
  $("#updatePromptModal").classList.add("hidden");
}

function acceptAvailableUpdate() {
  if (updateState.canInstall) {
    if (state.macroRunning) {
      showToast("Release the macro trigger before installing the update.", true);
      return;
    }

    clearUpdateReminder();
    closeUpdatePrompt();
    post("installUpdate");
    return;
  }

  clearUpdateReminder();
  closeUpdatePrompt();
  post("openExternal", { url: updateState.releaseUrl || releasesUrl });
}

function render() {
  renderDashboard();
  renderCharacters();
  renderHotkeys();
  renderFps();
  renderStartup();
  renderAboutMeta();
  renderUpdateStatus();
}


function updateSegmentedIndicator(container) {
  if (!container) return;

  const activeButton = container.querySelector("button.active");
  const indicator = container.querySelector(".segmented-indicator");
  if (!activeButton || !indicator) return;

  indicator.style.width = `${activeButton.offsetWidth}px`;
  indicator.style.transform = `translateX(${activeButton.offsetLeft}px)`;
  container.classList.add("indicator-ready");
}

function updateAllSegmentedIndicators() {
  $$(".segmented").forEach(updateSegmentedIndicator);
}

function previewSegmentedSelection(button) {
  const container = button.closest(".segmented");
  if (!container) return;

  container.querySelectorAll("button").forEach(item => {
    item.classList.toggle("active", item === button);
  });

  updateSegmentedIndicator(container);
}

function renderDashboard() {
  const soundToggle = $("#soundToggle");
  const soundControl = $("#soundControl");
  const soundStateLabel = state.soundsEnabled ? "Sound feedback enabled" : "Sound feedback muted";
  soundToggle.checked = state.soundsEnabled;
  soundToggle.setAttribute("aria-label", soundStateLabel);
  soundControl.title = state.soundsEnabled ? "Mute sound feedback" : "Enable sound feedback";
  $("#modeTitle").textContent = state.appMode === "SkipDialogs" ? t("skipDialogs") : t("characterCombos");
  $("#skipBehaviorTitle").textContent = state.skipStopMode === "AnyKey" ? t("untilAnyKey") : t("untilTriggerReleased");

  const startGameButton = $("#startGameButton");
  const hasExecutable = Boolean(state.autoLaunchPath);
  startGameButton.disabled = false;
  startGameButton.title = hasExecutable
    ? "Start the selected game"
    : "Select the game executable and start";

  $$("[data-mode]").forEach(button => button.classList.toggle("active", button.dataset.mode === state.appMode));
  $$("[data-skip-mode]").forEach(button => button.classList.toggle("active", button.dataset.skipMode === state.skipStopMode));
  requestAnimationFrame(updateAllSegmentedIndicators);

  const isSkip = state.appMode === "SkipDialogs";
  const activeCharacter = state.character || "No character";
  const activeCombo = state.comboDisplay || "No macro selected";

  $("#heroMode").textContent = isSkip ? t("dialogAutomation") : t("characterCombos").toUpperCase();
  $("#heroTitle").textContent = isSkip ? t("skipDialogs") : activeCharacter;
  $("#heroSubtitle").textContent = isSkip
    ? (state.skipStopMode === "AnyKey" ? t("untilAnyKey") : t("untilTriggerReleased"))
    : activeCombo;
  $("#triggerChip").textContent = `Trigger  ${state.triggerKey}`;

  setImage(
    $("#heroImage"),
    $("#heroFallback"),
    isSkip
      ? "https://assets.umm/icons/Skip.ico"
      : (state.character ? portraitUrl(state.character) : ""),
    isSkip ? "SKIP" : initials(activeCharacter),
    !isSkip && characterCatalog[state.character]?.fallbackImage
      ? `https://assets.umm/portraits/${encodeURIComponent(characterCatalog[state.character].fallbackImage)}`
      : null
  );

  $("#quickTrigger").textContent = state.triggerKey;
  $("#quickMode").textContent = state.modeToggleKey;
  $("#quickCharacter").textContent = state.characterToggleKey;
  $("#quickCombo").textContent = state.comboToggleKey;
}

function ensureCharacterCards() {
  const grid = $("#characterGrid");
  if (grid.dataset.initialized === "1") return;

  Object.entries(characterCatalog).forEach(([name, meta]) => {
    const button = document.createElement("button");
    button.className = "character-card";
    button.dataset.character = name;
    button.innerHTML = `
      <img alt="${escapeHtml(name)}" src="${portraitUrl(name)}" draggable="false" />
      <div class="character-card-copy">
        <strong class="preserve-ltr">${escapeHtml(name)}</strong>
      </div>`;

    const image = button.querySelector("img");
    image.addEventListener("dragstart", event => event.preventDefault());
    image.addEventListener("error", () => {
      if (meta.fallbackImage && !image.dataset.fallbackTried) {
        image.dataset.fallbackTried = "1";
        image.src = `https://assets.umm/portraits/${encodeURIComponent(meta.fallbackImage)}`;
      } else {
        image.style.display = "none";
        button.classList.add("image-missing");
      }
    });

    button.addEventListener("click", () => {
      if (state.macroRunning || state.character === name) return;
      post("setCharacter", { value: name });
    });

    grid.appendChild(button);
  });

  grid.dataset.initialized = "1";
}

function comboPresentation(combo) {
  const testing = Boolean(combo.testing);
  const label = combo.label;

  const badges = [];
  if (combo.fps) badges.push({ text: combo.fps, className: "fps-badge" });
  if (testing) badges.push({ text: "Test", className: "testing-badge" });
  if (combo.macroTrigger) badges.push({ text: `TRIGGER ${combo.macroTrigger}`, className: "trigger-badge" });

  return { label, badges };
}

function comboOrderForCurrentCharacter() {
  return $$("#comboList .combo-option").map(button => button.dataset.comboValue);
}

function captureComboLayout(list) {
  return new Map(
    Array.from(list.querySelectorAll(".combo-option")).map(button => [
      button.dataset.comboValue,
      button.getBoundingClientRect()
    ])
  );
}

function clampComboMotion(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, value));
}

function updateComboDragMotion(press, event) {
  if (!press?.active) return;

  const deltaX = event.clientX - press.startX;
  const deltaY = event.clientY - press.startY;
  const shiftX = clampComboMotion(deltaX * 0.035, -5, 5);
  const shiftY = clampComboMotion(deltaY * 0.025, -3, 3);

  press.button.style.setProperty("--combo-drag-x", `${shiftX}px`);
  press.button.style.setProperty("--combo-drag-y", `${shiftY}px`);
}

function resetComboDragMotion(button) {
  button.style.removeProperty("--combo-drag-x");
  button.style.removeProperty("--combo-drag-y");
}

function animateComboLift(button) {
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

  button._comboLiftAnimation?.cancel();
  button._comboLiftAnimation = button.animate(
    [
      { transform: "translate3d(0, 1px, 0) scale(.985)" },
      { transform: "translate3d(0, -8px, 0) scale(1.035)", offset: .62 },
      { transform: "translate3d(0, -6px, 0) scale(1.025)" }
    ],
    {
      duration: 220,
      easing: "cubic-bezier(.18, .9, .28, 1.2)"
    }
  );
}

function animateComboLayout(list, beforeLayout, draggedButton = null) {
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

  list.querySelectorAll(".combo-option").forEach(button => {
    if (button === draggedButton) return;

    const before = beforeLayout.get(button.dataset.comboValue);
    if (!before) return;

    const after = button.getBoundingClientRect();
    const deltaX = before.left - after.left;
    const deltaY = before.top - after.top;

    if (Math.abs(deltaX) < 0.5 && Math.abs(deltaY) < 0.5) return;

    button._comboReflowAnimation?.cancel();
    button._comboReflowAnimation = button.animate(
      [
        { transform: `translate3d(${deltaX}px, ${deltaY}px, 0)` },
        { transform: "translate3d(0, 0, 0)" }
      ],
      {
        duration: 190,
        easing: "cubic-bezier(.2, .78, .24, 1)"
      }
    );
  });
}

function animateComboDrop(button) {
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

  button.animate(
    [
      { transform: "translateY(-6px) scale(1.025)" },
      { transform: "translateY(2px) scale(.992)", offset: .52 },
      { transform: "translateY(-1px) scale(1.004)", offset: .78 },
      { transform: "translateY(0) scale(1)" }
    ],
    {
      duration: 310,
      easing: "cubic-bezier(.2, .82, .28, 1)"
    }
  );
}

function cancelPendingComboPress() {
  if (!comboPressState || comboPressState.active) return;

  clearTimeout(comboPressState.timer);
  comboPressState.button.classList.remove("is-hold-pending");
  comboPressState = null;
}

function activateComboReorder() {
  const press = comboPressState;
  if (!press || press.active || state.macroRunning) return;

  const availableCombos = characterCatalog[press.character]?.combos || [];
  if (availableCombos.length < 2) {
    cancelPendingComboPress();
    return;
  }

  press.active = true;
  press.button.classList.remove("is-hold-pending");
  resetComboDragMotion(press.button);
  press.button.classList.add("is-dragging");
  animateComboLift(press.button);
  press.button.setAttribute("aria-grabbed", "true");
  press.list.classList.add("is-reordering");
  suppressComboClickUntil = Date.now() + 1000;

  try {
    press.button.setPointerCapture(press.pointerId);
  } catch {
    // Pointer capture is optional; window-level handlers remain active.
  }

  if (navigator.vibrate) {
    navigator.vibrate(22);
  }
}

function beginComboLongPress(event, button) {
  if (state.macroRunning || event.button !== 0 || comboPressState) return;

  const availableCombos = characterCatalog[state.character]?.combos || [];
  if (availableCombos.length < 2) return;

  comboPressState = {
    pointerId: event.pointerId,
    startX: event.clientX,
    startY: event.clientY,
    button,
    list: $("#comboList"),
    character: state.character,
    originalOrder: comboOrderForCurrentCharacter(),
    active: false,
    timer: null
  };

  button.classList.add("is-hold-pending");
  comboPressState.timer = setTimeout(
    activateComboReorder,
    COMBO_LONG_PRESS_MS
  );
}

function moveComboDuringReorder(event) {
  const press = comboPressState;
  if (!press || event.pointerId !== press.pointerId) return;

  const distance = Math.hypot(
    event.clientX - press.startX,
    event.clientY - press.startY
  );

  if (!press.active) {
    if (distance > COMBO_PRESS_MOVE_TOLERANCE) {
      cancelPendingComboPress();
    }
    return;
  }

  event.preventDefault();
  updateComboDragMotion(press, event);

  const target = document
    .elementFromPoint(event.clientX, event.clientY)
    ?.closest(".combo-option");

  if (!target || target === press.button || target.parentElement !== press.list) {
    return;
  }

  const targetRect = target.getBoundingClientRect();
  const verticalDistance = Math.abs(event.clientY - (targetRect.top + targetRect.height / 2));
  const placeAfter = verticalDistance < targetRect.height * 0.34
    ? event.clientX > targetRect.left + targetRect.width / 2
    : event.clientY > targetRect.top + targetRect.height / 2;

  const beforeOrder = comboOrderForCurrentCharacter();
  const beforeLayout = captureComboLayout(press.list);

  press.list.insertBefore(
    press.button,
    placeAfter ? target.nextSibling : target
  );

  const afterOrder = comboOrderForCurrentCharacter();
  if (afterOrder.join("|") !== beforeOrder.join("|")) {
    animateComboLayout(press.list, beforeLayout, press.button);
  }
}

function finishComboReorder(event, cancelled = false) {
  const press = comboPressState;
  if (!press || event.pointerId !== press.pointerId) return;

  clearTimeout(press.timer);
  press.button.classList.remove("is-hold-pending");

  if (!press.active) {
    comboPressState = null;
    return;
  }

  event.preventDefault();
  press.button.classList.remove("is-dragging");
  resetComboDragMotion(press.button);
  press.button.removeAttribute("aria-grabbed");
  press.list.classList.remove("is-reordering");
  animateComboDrop(press.button);

  try {
    press.button.releasePointerCapture(press.pointerId);
  } catch {
    // Ignore when capture was unavailable or already released.
  }

  if (cancelled) {
    const beforeLayout = captureComboLayout(press.list);
    const buttonById = new Map(
      $$("#comboList .combo-option").map(button => [
        button.dataset.comboValue,
        button
      ])
    );

    press.originalOrder.forEach(comboId => {
      const button = buttonById.get(comboId);
      if (button) press.list.appendChild(button);
    });

    animateComboLayout(press.list, beforeLayout, press.button);
  } else {
    const newOrder = comboOrderForCurrentCharacter();
    if (newOrder.join("|") !== press.originalOrder.join("|")) {
      // Force the authoritative engine response to rebuild the list. This
      // restores the original order when persistence fails and confirms the
      // new order only after the engine has saved it.
      catalogJsonCache = "";
      post("reorderMacros", {
        character: press.character,
        comboIds: newOrder.join("|")
      });
    }
  }

  suppressComboClickUntil = Date.now() + 650;
  comboPressState = null;
}

function ensureComboButtons() {
  const comboList = $("#comboList");
  const character = state.character;
  const combos = characterCatalog[character]?.combos || [];

  if (comboList.dataset.character === character) {
    return;
  }

  comboList.innerHTML = "";
  comboList.dataset.character = character;

  combos.forEach(combo => {
    const presentation = comboPresentation(combo);
    const button = document.createElement("button");
    button.className = "combo-option";
    button.type = "button";
    button.dataset.comboValue = combo.value;
    button.setAttribute("aria-grabbed", "false");

    const reorderHelp = "Press and hold, then drag to reorder.";
    if (combo.tooltip) {
      button.setAttribute(
        "aria-label",
        `${presentation.label}: ${combo.tooltip}. ${reorderHelp}`
      );
    } else {
      button.setAttribute(
        "aria-label",
        `${presentation.label}. ${reorderHelp}`
      );
    }

    const badges = presentation.badges
      .map(badge => `<span class="${badge.className}">${escapeHtml(badge.text)}</span>`)
      .join("");

    const description = combo.tooltip
      ? `<small>${escapeHtml(combo.tooltip)}</small>`
      : "";
    button.innerHTML = `
      <span class="combo-copy">
        <strong class="preserve-ltr">${escapeHtml(presentation.label)}</strong>
        ${description}
      </span>
      ${badges ? `<span class="combo-badges">${badges}</span>` : ""}`;

    button.addEventListener("pointerdown", event => {
      beginComboLongPress(event, button);
    });

    button.addEventListener("click", event => {
      if (
        Date.now() < suppressComboClickUntil ||
        comboPressState?.active
      ) {
        event.preventDefault();
        return;
      }

      if (state.macroRunning || state.combo === combo.value) return;
      post("setCombo", { value: combo.value });
    });

    button.addEventListener("contextmenu", event => {
      if (comboPressState?.active) {
        event.preventDefault();
      }
    });

    comboList.appendChild(button);
  });
}

function getSelectedCombo() {
  const combos = characterCatalog[state.character]?.combos || [];
  return combos.find(combo => combo.value === state.combo) || null;
}

function renderCharacters() {
  ensureCharacterCards();
  ensureComboButtons();

  $$(".character-card").forEach(button => {
    const selected = button.dataset.character === state.character;
    button.classList.toggle("active", selected);
    button.disabled = state.macroRunning;
  });

  $("#comboPanelTitle").textContent = state.character || "No character";
  $("#comboPanelCurrent").textContent = state.comboDisplay || "No macro selected";

  const addMacroButton = $("#addMacroButton");
  addMacroButton.disabled = state.macroRunning || !state.character || macroEditorPending;
  addMacroButton.title = state.macroRunning
    ? "Release the trigger before importing a macro."
    : `Import an AHK macro for ${state.character}`;

  const createMacroButton = $("#createMacroButton");
  createMacroButton.disabled = state.macroRunning || !state.character || macroEditorPending;
  createMacroButton.title = state.macroRunning
    ? "Release the trigger before creating a macro."
    : `Create a macro for ${state.character}`;

  const selectedCombo = getSelectedCombo();
  const hasSelectedCombo = Boolean(selectedCombo);
  const canManageSelected = hasSelectedCombo && !state.macroRunning;
  const canDelete = canManageSelected && !selectedCombo.builtIn;

  const editMacroButton = $("#editMacroButton");
  editMacroButton.disabled = !canManageSelected || macroEditorPending;
  editMacroButton.title = hasSelectedCombo
    ? `Edit ${selectedCombo.label}`
    : "Select a macro first.";
  editMacroButton.setAttribute(
    "aria-label",
    hasSelectedCombo ? `Edit ${selectedCombo.label}` : "Edit selected macro"
  );

  const exportMacroButton = $("#exportMacroButton");
  exportMacroButton.disabled = !canManageSelected;
  exportMacroButton.title = hasSelectedCombo
    ? `Export ${selectedCombo.label}`
    : "Select a macro first.";
  exportMacroButton.setAttribute(
    "aria-label",
    hasSelectedCombo ? `Export ${selectedCombo.label}` : "Export selected macro"
  );

  const deleteMacroButton = $("#deleteMacroButton");
  deleteMacroButton.classList.toggle("hidden", !hasSelectedCombo || selectedCombo.builtIn);
  deleteMacroButton.disabled = !canDelete;
  deleteMacroButton.title = canDelete
    ? `Delete ${selectedCombo.label}`
    : "Release the trigger before deleting this macro.";
  deleteMacroButton.setAttribute(
    "aria-label",
    canDelete
      ? `Delete ${selectedCombo.label}`
      : "Delete selected macro"
  );

  $$(".combo-option").forEach(button => {
    const selected = button.dataset.comboValue === state.combo;
    button.classList.toggle("active", selected);
    button.disabled = state.macroRunning;
  });
}

function ensureHotkeyCards() {
  const grid = $("#hotkeyGrid");
  if (grid.dataset.initialized === "1") return;

  hotkeyCatalog.forEach(item => {
    const card = document.createElement("article");
    card.className = "hotkey-card";
    card.dataset.hotkeyTarget = item.target;
    card.innerHTML = `
      <div class="hotkey-copy">
        <h3 class="hotkey-title">${item.title.toUpperCase()}</h3>
        <p class="hotkey-description">${item.description}</p>
      </div>
      <div class="hotkey-action">
        <div class="hotkey-value">—</div>
        <button class="secondary-button">Change</button>
      </div>`;

    card.querySelector("button").addEventListener("click", () => beginHotkeyCapture(item));
    grid.appendChild(card);
  });

  grid.dataset.initialized = "1";
}

function renderHotkeys() {
  const grid = $("#hotkeyGrid");
  ensureHotkeyCards();

  if (state.macroRunning && captureTarget) {
    endHotkeyCapture();
  }

  hotkeyCatalog.forEach((item, index) => {
    const card = grid.children[index];
    const value = card.querySelector(".hotkey-value");
    const changeButton = card.querySelector("button");
    card.classList.toggle("is-disabled", state.macroRunning);
    value.textContent = state[item.stateKey] || "—";
    changeButton.disabled = state.macroRunning;
    changeButton.title = state.macroRunning
      ? t("releaseBeforeHotkeys")
      : t("changeHotkeyTitle", { name: item.title });
  });

  const resetButton = $("#resetHotkeysButton");
  resetButton.disabled = state.macroRunning;
  resetButton.title = state.macroRunning
    ? t("releaseBeforeReset")
    : t("resetHotkeysTitle");

  $$('[data-hotkey-scope]').forEach(button => {
    button.classList.toggle("active", button.dataset.hotkeyScope === state.hotkeyScope);
    button.disabled = state.macroRunning;
  });

  const scopeSegmented = $("#hotkeyScopeSegmented");
  scopeSegmented.classList.toggle("is-disabled", state.macroRunning);
  $("#hotkeyInfo").textContent = state.hotkeyScope === "Everywhere"
    ? "Hotkeys are active in every application. Gameplay keys and duplicate assignments are still rejected."
    : t("hotkeyInfo");
  requestAnimationFrame(() => updateSegmentedIndicator(scopeSegmented));
}

function clampFpsTarget(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.min(420, Math.max(10, Math.round(parsed))) : 120;
}

function queueFpsTarget(value, immediate = false) {
  const target = clampFpsTarget(value);
  state.fpsTarget = target;
  $("#fpsTargetSlider").value = String(target);
  $("#fpsTargetInput").value = String(target);
  renderFpsPresetSelection();

  window.clearTimeout(fpsTargetCommitTimer);
  if (immediate) {
    post("setFpsTarget", { value: target });
    return;
  }

  fpsTargetCommitTimer = window.setTimeout(() => {
    fpsTargetCommitTimer = 0;
    post("setFpsTarget", { value: target });
  }, 90);
}

function renderFpsPresetSelection() {
  $$('[data-fps-preset]').forEach(button => {
    button.classList.toggle("active", Number(button.dataset.fpsPreset) === state.fpsTarget);
  });
}

function renderFps() {
  const toggle = $("#fpsUnlockToggle");
  if (!toggle) return;

  toggle.checked = state.fpsEnabled;
  toggle.disabled = !state.fpsAvailable;
  toggle.closest(".fps-enable-switch").title = state.fpsAvailable
    ? (state.fpsEnabled ? "Disable FPS unlocker" : "Enable FPS unlocker")
    : "The native FPS component is not available in this build.";

  if (!fpsTargetEditing) {
    $("#fpsTargetInput").value = String(state.fpsTarget);
    $("#fpsTargetSlider").value = String(state.fpsTarget);
  }

  const controlsDisabled = !state.fpsAvailable;
  $("#fpsTargetInput").disabled = controlsDisabled;
  $("#fpsTargetSlider").disabled = controlsDisabled;
  $$('[data-fps-preset]').forEach(button => { button.disabled = controlsDisabled; });
  renderFpsPresetSelection();

  const labels = {
    disabled: "Disabled",
    unavailable: "Unavailable",
    waiting: "Waiting for game",
    connecting: "Connecting",
    active: "Active",
    error: "Unavailable for this game version"
  };
  const status = String(state.fpsStatus || "disabled").toLowerCase();
  $("#fpsStatus").dataset.status = status;
  $("#fpsStatusLabel").textContent = labels[status] || "FPS unlocker";
  $("#fpsStatusMessage").textContent = state.fpsMessage || "Enable the limiter, then start the game.";
}

function renderStartup() {
  const path = state.autoLaunchPath || "";
  const hasExecutable = Boolean(path);

  $("#executableName").textContent = hasExecutable
    ? path.split(/[\\/]/).pop()
    : t("noExecutable");
  $("#executablePath").textContent = path || t("executableHelp");

  const autoLaunchToggle = $("#autoLaunchToggle");
  autoLaunchToggle.checked = state.autoLaunchEnabled;
  autoLaunchToggle.disabled = !hasExecutable;
  autoLaunchToggle.closest(".startup-behavior-row")
    .classList.toggle("is-disabled", !hasExecutable);

  $("#clearExecutableButton").disabled = !hasExecutable;
}


function formatBuildDate(value) {
  if (!value || value === "—") return "—";

  const parsed = new Date(`${value}T00:00:00`);
  if (Number.isNaN(parsed.getTime())) return value;

  return new Intl.DateTimeFormat("en", {
    year: "numeric",
    month: "short",
    day: "numeric"
  }).format(parsed);
}

function renderUpdateStatus() {
  const statusText = $("#updateStatusText");
  const checkButton = $("#checkUpdateButton");
  const installButton = $("#installUpdateButton");
  const viewButton = $("#viewReleaseButton");
  const progressTrack = $("#updateProgress");
  const progressBar = $("#updateProgressBar");
  const releaseNotes = $("#updateReleaseNotes");
  const releaseNotesSummary = $("#updateReleaseNotesSummary");
  const releaseNotesText = $("#updateReleaseNotesText");

  if (!statusText || !checkButton || !installButton || !viewButton) return;

  const busy = ["checking", "downloading", "installing", "busy"].includes(updateState.status);
  statusText.textContent = updateState.message || t("updatesIdle");
  checkButton.disabled = busy;
  checkButton.textContent = updateState.status === "checking"
    ? "Checking…"
    : t("checkUpdates");

  const canInstall = updateState.status === "available" && updateState.canInstall;
  installButton.classList.toggle("hidden", !canInstall);
  installButton.disabled = busy || state.macroRunning;
  installButton.textContent = state.macroRunning
    ? "Release trigger first"
    : t("installUpdate");

  const releaseUrl = updateState.releaseUrl || releasesUrl;
  viewButton.classList.toggle(
    "hidden",
    !releaseUrl || updateState.status === "idle" || updateState.status === "checking"
  );
  viewButton.disabled = busy && updateState.status !== "downloading";

  const notes = String(updateState.releaseNotes || "").trim();
  const releaseName = String(updateState.releaseName || "").trim();
  const showNotes = Boolean(notes) && ["available", "current", "downloading", "installing"].includes(updateState.status);
  if (releaseNotes && releaseNotesText) {
    releaseNotes.classList.toggle("hidden", !showNotes);
    releaseNotes.setAttribute("aria-hidden", showNotes ? "false" : "true");
    if (releaseNotesSummary) {
      releaseNotesSummary.textContent = releaseName
        ? `${t("releaseNotes")} — ${releaseName}`
        : t("releaseNotes");
    }
    releaseNotesText.textContent = showNotes
      ? (notes.length > 1200 ? `${notes.slice(0, 1200).trimEnd()}…` : notes)
      : "";
    if (!showNotes) releaseNotes.open = false;
  }

  const hasProgress = Number.isFinite(updateState.progress) &&
    ["downloading", "installing"].includes(updateState.status);
  progressTrack.classList.toggle("hidden", !hasProgress);
  progressTrack.setAttribute("aria-hidden", hasProgress ? "false" : "true");
  progressBar.style.width = hasProgress
    ? `${Math.max(0, Math.min(100, updateState.progress))}%`
    : "0%";
  renderUpdatePromptAction();
}

function renderAboutMeta() {
  const version = buildInfo.version !== "—" ? buildInfo.version : (state.version || "—");
  $("#aboutVersion").textContent = version;
  $("#aboutBuildDate").textContent = formatBuildDate(buildInfo.buildDate);
  $("#aboutCopyright").textContent = t("copyright", { year: new Date().getFullYear() });
}

async function loadBuildInfo() {
  try {
    const response = await fetch(`build-info.json?t=${Date.now()}`, { cache: "no-store" });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);

    const data = await response.json();
    buildInfo = {
      version: data.version || "—",
      buildDate: data.buildDate || "—"
    };
  } catch {
    buildInfo = {
      version: state.version || "—",
      buildDate: "—"
    };
  }

  renderAboutMeta();
}


function normalizeTheme(value) {
  return value === "light" ? "light" : "dark";
}

function applyTheme(theme, persist = true) {
  const selectedTheme = normalizeTheme(theme);
  document.documentElement.dataset.theme = selectedTheme;
  post("setMacroRecordingTheme", { theme: selectedTheme });

  const isDark = selectedTheme === "dark";
  const icon = $("#themeIcon");
  const label = $("#themeLabel");
  const hint = $("#themeHint");
  const toggle = $("#themeToggle");

  if (icon) icon.textContent = isDark ? "☾" : "☀";
  if (label) label.textContent = isDark ? "Dark mode" : "Light mode";
  if (hint) hint.textContent = isDark ? "Switch to light" : "Switch to dark";
  if (toggle) {
    const actionLabel = isDark ? "Switch to light mode" : "Switch to dark mode";
    toggle.setAttribute("aria-label", actionLabel);
    toggle.title = actionLabel;
  }

  if (persist) localStorage.setItem(THEME_STORAGE_KEY, selectedTheme);
}

function toggleTheme() {
  const root = document.documentElement;
  if (root.classList.contains("theme-transitioning")) return;

  const current = normalizeTheme(document.documentElement.dataset.theme);
  const nextTheme = current === "dark" ? "light" : "dark";
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const commitTheme = () => applyTheme(nextTheme);

  if (reducedMotion) {
    commitTheme();
    return;
  }

  root.classList.add("theme-transitioning");
  const finishTransition = () => {
    root.classList.remove("theme-transitioning", "theme-transition-fallback");
  };

  if (typeof document.startViewTransition === "function") {
    const transition = document.startViewTransition(commitTheme);
    transition.finished.then(finishTransition, finishTransition);
    return;
  }

  root.classList.add("theme-transition-fallback");
  requestAnimationFrame(() => {
    commitTheme();
    window.setTimeout(finishTransition, 360);
  });
}

function openCommunityLink(name) {
  const url = communityLinks[name];
  if (!url) {
    showToast(t("addCommunityUrl", { name }), true);
    return;
  }

  post("openExternal", { url });
}

function setImage(image, fallback, primaryUrl, fallbackText, secondUrl = null) {
  image.draggable = false;
  fallback.textContent = fallbackText;

  if (!primaryUrl) {
    image.removeAttribute("src");
    image.style.display = "none";
    fallback.style.display = "grid";
    return;
  }

  fallback.style.display = "none";
  image.style.display = "block";
  image.dataset.secondTried = "";
  image.onerror = () => {
    if (secondUrl && !image.dataset.secondTried) {
      image.dataset.secondTried = "1";
      image.src = secondUrl;
      return;
    }
    image.style.display = "none";
    fallback.style.display = "grid";
  };
  image.src = primaryUrl;
}

function portraitUrl(name) {
  const file = characterCatalog[name]?.image || `${name}.png`;
  return `https://assets.umm/portraits/${encodeURIComponent(file)}`;
}

function initials(value) {
  const text = String(value || "").trim();
  if (!text) return "MM";
  return text.split(/\s+/).map(part => part[0] || "").join("").slice(0, 3).toUpperCase();
}

function beginHotkeyCapture(item) {
  if (state.macroRunning) return;

  captureTarget = item;
  $("#hotkeyModalTitle").textContent = t("newKey", { name: item.title });
  $("#capturedKey").textContent = "…";
  $("#hotkeyModal").classList.remove("hidden");
  post("setTransientTopMost", { active: true });
}

function endHotkeyCapture() {
  captureTarget = null;
  $("#hotkeyModal").classList.add("hidden");
  post("setTransientTopMost", { active: false });
}

function renderMacroTrigger() {
  const value = macroEditorDocument?.macroTrigger || "";
  $("#macroTriggerValue").textContent = value || "Choose custom hotkey";
  $("#macroTriggerClearButton").disabled = !value;
}

function beginMacroTriggerCapture() {
  if (!macroEditorDocument?.canSave || macroRecordingState.recording) return;
  beginHotkeyCapture({ target: "MacroTrigger", title: "Custom hotkey" });
}

function macroTriggerValidationMessage(key) {
  const normalized = String(key || "").toLowerCase();
  const reserved = new Set([
    "lbutton", "rbutton", "q", "w", "e", "a", "s", "d", "f",
    "shift", "lshift", "rshift", "wheelup", "wheeldown", "wheelleft", "wheelright"
  ]);
  if (reserved.has(normalized)) return "This gameplay key cannot be used as a macro trigger.";

  const appHotkeys = [
    state.triggerKey, state.comboToggleKey, state.characterToggleKey,
    state.modeToggleKey, state.interfaceKey, state.recorderHotkey
  ].map(value => String(value || "").toLowerCase());
  if (appHotkeys.includes(normalized)) return "This key is already assigned on the Hotkeys page.";

  const duplicate = Object.values(characterCatalog).some(character =>
    (character?.combos || []).some(combo =>
      combo.value !== macroEditorDocument?.comboId &&
      String(combo.macroTrigger || "").toLowerCase() === normalized));
  return duplicate ? "This key is already linked to another macro." : "";
}

function commitCapturedHotkey(mappedKey) {
  if (!captureTarget) return;
  $("#capturedKey").textContent = mappedKey;
  if (captureTarget.target === "MacroTrigger") {
    const error = macroTriggerValidationMessage(mappedKey);
    if (error) {
      showToast(error, true);
      return;
    }
    macroEditorDocument.macroTrigger = mappedKey;
    renderMacroTrigger();
  } else {
    post("setHotkey", { target: captureTarget.target, value: mappedKey });
  }
  endHotkeyCapture();
}

function mapKeyboardEvent(event) {
  if (/^F\d{1,2}$/.test(event.key)) return event.key;
  if (/^[a-zA-Z0-9]$/.test(event.key)) return event.key.toUpperCase();

  const map = {
    " ": "Space", "Tab": "Tab", "CapsLock": "CapsLock", "Backspace": "Backspace", "Enter": "Enter",
    "Insert": "Insert", "Delete": "Delete", "Home": "Home", "End": "End", "PageUp": "PgUp", "PageDown": "PgDn",
    "ArrowUp": "Up", "ArrowDown": "Down", "ArrowLeft": "Left", "ArrowRight": "Right",
    "Shift": event.location === 2 ? "RShift" : "LShift",
    "Control": event.location === 2 ? "RControl" : "LControl",
    "Alt": event.location === 2 ? "RAlt" : "LAlt",
    "ContextMenu": "AppsKey"
  };

  if (map[event.key]) return map[event.key];
  if (/^Numpad\d$/.test(event.code)) return event.code;
  const numpadMap = {
    NumpadDecimal: "NumpadDot", NumpadAdd: "NumpadAdd", NumpadSubtract: "NumpadSub",
    NumpadMultiply: "NumpadMult", NumpadDivide: "NumpadDiv", NumpadEnter: "NumpadEnter"
  };
  return numpadMap[event.code] || null;
}

function openMacroImport() {
  if (state.macroRunning) {
    showToast("Release the trigger before importing a macro.", true);
    return;
  }

  if (!state.character || !characterCatalog[state.character]) {
    showToast("Select a character first.", true);
    return;
  }

  post("importMacro", { character: state.character });
}

function openMacroCreate() {
  if (state.macroRunning) {
    showToast("Release the trigger before creating a macro.", true);
    return;
  }
  if (!state.character || !characterCatalog[state.character]) {
    showToast("Select a character first.", true);
    return;
  }

  macroEditorPending = true;
  renderCharacters();
  if (!post("createMacroDefinition", { character: state.character })) {
    macroEditorPending = false;
    renderCharacters();
  }
}

function openMacroEdit(combo) {
  if (!combo || state.macroRunning || macroEditorPending) return;

  macroEditorPending = true;
  renderCharacters();
  if (!post("loadMacroDefinition", { comboId: combo.value })) {
    macroEditorPending = false;
    renderCharacters();
  }
}

function macroInteger(value, fallback = 0, maximum = Number.MAX_SAFE_INTEGER) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(maximum, Math.max(0, Math.round(parsed)));
}

function normalizeMacroEditorEvent(item) {
  const type = String(item?.type || "").toLowerCase();
  return {
    id: String(item?.id || newMacroEventId()),
    type,
    key: String(item?.key || ""),
    action: String(item?.action || ""),
    durationMs: macroInteger(item?.durationMs, 0, 600000),
    count: macroInteger(item?.count, 0, 1000),
    text: String(item?.text || ""),
    rawId: String(item?.rawId || ""),
    summary: String(item?.summary || ""),
    timingUnknown: item?.timingUnknown !== false,
    children: Array.isArray(item?.children)
      ? item.children.map(normalizeMacroEditorEvent)
      : []
  };
}

function openMacroEditorDocument(document) {
  if (!document || typeof document !== "object") {
    showToast("The macro editor received an invalid document.", true);
    return;
  }

  macroEditorDocument = {
    sessionId: String(document.sessionId || ""),
    mode: document.mode === "create" ? "create" : "edit",
    comboId: String(document.comboId || ""),
    character: String(document.character || ""),
    name: String(document.name || ""),
    description: String(document.description || ""),
    fpsTag: String(document.fpsTag || ""),
    testing: Boolean(document.testing),
    macroTrigger: String(document.macroTrigger || ""),
    canSave: Boolean(document.canSave),
    canEditEvents: Boolean(document.canEditEvents),
    events: Array.isArray(document.events)
      ? document.events.map(normalizeMacroEditorEvent)
      : [],
    warnings: Array.isArray(document.warnings)
      ? document.warnings.map(String)
      : []
  };
  macroEventSelection = new Set();
  macroEventSelectionAnchor = "";
  collapsedMacroLoops = new Set();
  macroPreviewRunning = false;
  resetMacroEventHistory();

  const creating = macroEditorDocument.mode === "create";
  const metadataOnly = !creating && !macroEditorDocument.canEditEvents;
  const shell = $("#macroEditorForm");
  shell.classList.remove("details-collapsed", "is-recording");
  $("#toggleMacroDetailsButton").setAttribute("aria-pressed", "false");
  $("#toggleMacroDetailsButton").textContent = "Collapse";
  $("#toggleMacroDetailsButton").title = "Collapse macro details";
  shell.classList.toggle("is-metadata-only", metadataOnly);
  $("#macroEditorTitle").textContent = creating
    ? "Create macro"
    : metadataOnly ? "Edit macro details" : "Edit macro";
  $("#macroEditorCharacter").textContent = macroEditorDocument.character || "—";
  $("#macroEditorName").value = macroEditorDocument.name;
  $("#macroEditorDescription").value = macroEditorDocument.description;
  $("#macroEditorFpsTag").value = macroEditorDocument.fpsTag;
  $("#macroEditorTestingTag").checked = macroEditorDocument.testing;
  renderMacroTrigger();

  const warning = $("#macroEditorWarning");
  warning.textContent = macroEditorDocument.warnings.join(" ");
  warning.classList.toggle("hidden", macroEditorDocument.warnings.length === 0);

  $("#saveMacroEditorButton").disabled = !macroEditorDocument.canSave;
  $("#saveMacroEditorButton").textContent = creating ? "Create macro" : "Save changes";
  const status = $("#macroEditorStatus");
  status.textContent = macroEditorDocument.canSave ? "" : "This macro cannot be saved.";
  status.classList.toggle("hidden", macroEditorDocument.canSave);

  renderMacroEditorEvents();
  renderMacroRecorder();
  $("#macroEditorModal").classList.remove("hidden");
  post("getMacroRecordingState");
  setMacroEditorSaving(false);
  window.setTimeout(() => {
    $("#macroEditorName").focus();
    if (!creating) $("#macroEditorName").select();
  }, 0);
}

function closeMacroEditor(force = false) {
  if (macroEditorSaving && !force) return;
  if (captureTarget) endHotkeyCapture();
  window.cancelAnimationFrame(macroEventAnimationFrame);
  macroEventAnimationFrame = 0;
  $("#macroEditorModal").classList.add("hidden");
  $("#macroEditorForm").classList.remove("is-metadata-only");
  macroEditorDocument = null;
  macroEventDragId = "";
  macroEventDragIds = [];
  macroEventSelection = new Set();
  macroEventSelectionAnchor = "";
  collapsedMacroLoops = new Set();
  macroPreviewRunning = false;
  resetMacroEventHistory();
  macroRecordingBaseline = null;
  post("stopMacroPreview");
  post("closeMacroEditorSession");
  setMacroEditorSaving(false);
}

function setMacroEditorSaving(saving) {
  macroEditorSaving = Boolean(saving);
  const shell = $("#macroEditorForm");
  const saveButton = $("#saveMacroEditorButton");
  shell?.classList.toggle("is-saving", macroEditorSaving);
  if (saveButton) {
    saveButton.disabled = macroEditorSaving || !macroEditorDocument?.canSave;
    if (macroEditorSaving) saveButton.textContent = "Saving…";
    else if (macroEditorDocument) {
      saveButton.textContent = macroEditorDocument.mode === "create"
        ? "Create macro"
        : "Save changes";
    }
  }
  renderMacroPreviewButton();
}

function cloneMacroEvents(events) {
  return (events || []).map(item => ({
    ...item,
    children: cloneMacroEvents(item.children || [])
  }));
}

function macroEventHistorySnapshot() {
  return JSON.stringify(cleanMacroEditorEvents(macroEditorDocument?.events || []));
}

function resetMacroEventHistory() {
  macroEventUndoStack = [];
  macroEventRedoStack = [];
  macroEventHistoryKey = "";
  macroEventHistoryTime = 0;
}

function recordMacroEventHistory(key = "change") {
  if (!macroEditorDocument?.canEditEvents) return;
  invalidateMacroPreview();
  const snapshot = macroEventHistorySnapshot();
  const now = performance.now();
  const coalesce = key.startsWith("field:") &&
    key === macroEventHistoryKey && now - macroEventHistoryTime < 700;
  if (!coalesce && macroEventUndoStack.at(-1) !== snapshot) {
    macroEventUndoStack.push(snapshot);
    if (macroEventUndoStack.length > 80) macroEventUndoStack.shift();
  }
  macroEventRedoStack = [];
  macroEventHistoryKey = key;
  macroEventHistoryTime = now;
}

function restoreMacroEventHistory(snapshot) {
  try {
    const parsed = JSON.parse(snapshot);
    if (!Array.isArray(parsed)) return false;
    macroEditorDocument.events = parsed.map(normalizeMacroEditorEvent);
    macroEventSelection = new Set();
    macroEventSelectionAnchor = "";
    invalidateMacroPreview();
    renderMacroEditorEvents();
    return true;
  } catch {
    return false;
  }
}

function undoMacroEditorEvents() {
  if (!macroEditorDocument?.canEditEvents || macroRecordingState.recording || !macroEventUndoStack.length) return;
  const current = macroEventHistorySnapshot();
  const previous = macroEventUndoStack.pop();
  if (!restoreMacroEventHistory(previous)) return;
  macroEventRedoStack.push(current);
  macroEventHistoryKey = "";
  macroEventHistoryTime = 0;
}

function redoMacroEditorEvents() {
  if (!macroEditorDocument?.canEditEvents || macroRecordingState.recording || !macroEventRedoStack.length) return;
  const current = macroEventHistorySnapshot();
  const next = macroEventRedoStack.pop();
  if (!restoreMacroEventHistory(next)) return;
  macroEventUndoStack.push(current);
  macroEventHistoryKey = "";
  macroEventHistoryTime = 0;
}

function recordedTransitionsToMacroEvents(transitions) {
  const events = [];
  let previousOffset = 0;

  (transitions || []).forEach((transition, index) => {
    const offset = macroInteger(transition?.offsetMs, previousOffset, Number.MAX_SAFE_INTEGER);
    let delay = Math.max(0, offset - previousOffset);
    let delayPart = 0;
    while (delay > 0) {
      const durationMs = Math.min(600000, delay);
      events.push({
        id: `recorded_delay_${index}_${delayPart}_${newMacroEventId()}`,
        type: "delay",
        durationMs,
        children: []
      });
      delay -= durationMs;
      delayPart++;
    }

    const key = String(transition?.key || "");
    const action = ["down", "up", "tap"].includes(transition?.action)
      ? transition.action
      : "tap";
    events.push({
      id: `recorded_input_${index}_${newMacroEventId()}`,
      type: "input",
      key,
      action,
      durationMs: 0,
      children: []
    });
    previousOffset = offset;
  });

  return events;
}

function applyMacroRecordingSnapshot(snapshot) {
  if (!snapshot || typeof snapshot !== "object") return;

  const wasRecording = macroRecordingState.recording;
  const nextSettings = snapshot.settings && typeof snapshot.settings === "object"
    ? snapshot.settings
    : macroRecordingState.settings;
  macroRecordingState = {
    available: Boolean(snapshot.available),
    recording: Boolean(snapshot.recording),
    sessionId: String(snapshot.sessionId || ""),
    elapsedMs: macroInteger(snapshot.elapsedMs, 0, Number.MAX_SAFE_INTEGER),
    capacityTrimmed: Boolean(snapshot.capacityTrimmed),
    settings: {
      lastWindowEnabled: nextSettings.lastWindowEnabled !== false,
      windowSeconds: Math.max(1, macroInteger(nextSettings.windowSeconds, 30, 600)),
      toggleHotkey: String(nextSettings.toggleHotkey || state.recorderHotkey || "F7"),
      allowedKeys: Array.isArray(nextSettings.allowedKeys)
        ? nextSettings.allowedKeys.map(String)
        : []
    },
    transitions: Array.isArray(snapshot.transitions) ? snapshot.transitions : []
  };

  if (macroEditorDocument?.canEditEvents) {
    if (macroRecordingState.recording && !wasRecording) {
      recordMacroEventHistory("recording");
      macroRecordingBaseline = cloneMacroEvents(macroEditorDocument.events);
    }

    if (macroRecordingBaseline && (macroRecordingState.recording || wasRecording)) {
      macroEditorDocument.events = [
        ...cloneMacroEvents(macroRecordingBaseline),
        ...recordedTransitionsToMacroEvents(macroRecordingState.transitions)
      ];
      renderMacroEditorEvents();
    }

    if (!macroRecordingState.recording && wasRecording) {
      macroRecordingBaseline = null;
    }
  }

  renderMacroRecorder();
}

function renderMacroRecorderKeys() {
  const container = $("#macroRecorderKeys");
  if (!container || container.dataset.initialized) return;
  container.dataset.initialized = "1";
  container.innerHTML = macroEditorKeys.map(([value, label]) => `
    <label class="macro-recorder-key-chip">
      <input type="checkbox" value="${escapeHtml(value)}" />
      <span>${escapeHtml(label)}</span>
    </label>`).join("");
}

function renderMacroRecorder() {
  const panel = $("#macroRecorderPanel");
  if (!panel) return;
  renderMacroRecorderKeys();

  const settings = macroRecordingState.settings;
  panel.classList.toggle("is-recording", macroRecordingState.recording);
  $("#macroEditorForm")?.classList.toggle("is-recording", macroRecordingState.recording);
  const toggle = $("#macroRecorderToggleButton");
  toggle.textContent = macroRecordingState.recording ? "Stop recording" : "Start recording";
  toggle.disabled = !macroEditorDocument?.canEditEvents || !macroRecordingState.available;

  const seconds = Math.max(0, Math.round(macroRecordingState.elapsedMs / 1000));
  const count = macroRecordingState.transitions.length;
  $("#macroRecorderStatus").textContent = macroRecordingState.recording
    ? `Recording · ${seconds}s · ${count} captured`
    : count ? `Stopped · ${count} captured` : `Ready · ${settings.toggleHotkey}`;
  $("#macroRecorderLastWindow").checked = settings.lastWindowEnabled;
  $("#macroRecorderLastWindow").disabled = macroRecordingState.recording;
  $("#macroRecorderWindowSeconds").value = settings.windowSeconds;
  $("#macroRecorderWindowSeconds").disabled = !settings.lastWindowEnabled || macroRecordingState.recording;
  const allowed = new Set(settings.allowedKeys);
  $$("#macroRecorderKeys input[type='checkbox']").forEach(input => {
    input.checked = allowed.has(input.value);
    input.disabled = macroRecordingState.recording;
  });
  $$(".macro-recorder-key-actions button").forEach(button => {
    button.disabled = macroRecordingState.recording;
  });

  const warning = $("#macroEditorWarning");
  if (macroRecordingState.capacityTrimmed && warning) {
    const recorderWarning = "The recording reached its safety limit; the oldest captured inputs were removed.";
    if (!warning.textContent.includes(recorderWarning)) {
      warning.textContent = `${warning.textContent} ${recorderWarning}`.trim();
    }
    warning.classList.remove("hidden");
  }
  renderMacroPreviewButton();
}

function collectMacroRecordingSettings() {
  return {
    lastWindowEnabled: $("#macroRecorderLastWindow").checked,
    windowSeconds: Math.max(1, macroInteger($("#macroRecorderWindowSeconds").value, 30, 600)),
    toggleHotkey: macroRecordingState.settings.toggleHotkey,
    allowedKeys: $$("#macroRecorderKeys input:checked").map(input => input.value)
  };
}

function queueMacroRecordingSettings() {
  window.clearTimeout(macroRecordingSettingsTimer);
  macroRecordingSettingsTimer = window.setTimeout(() => {
    post("setMacroRecordingSettings", collectMacroRecordingSettings());
  }, 120);
}

function newMacroEventId() {
  const suffix = globalThis.crypto?.randomUUID?.().replaceAll("-", "").slice(0, 12)
    || `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 7)}`;
  return `event_${suffix}`;
}

function createMacroEvent(type) {
  if (type === "delay") {
    return { id: newMacroEventId(), type, durationMs: 100, children: [] };
  }
  if (type === "loop") {
    return {
      id: newMacroEventId(),
      type,
      count: 2,
      children: [{
        id: newMacroEventId(),
        type: "input",
        key: "LButton",
        action: "tap",
        durationMs: 30,
        children: []
      }]
    };
  }
  if (type === "note") {
    return { id: newMacroEventId(), type, text: "New note", children: [] };
  }
  return {
    id: newMacroEventId(),
    type: "input",
    key: "LButton",
    action: "tap",
    durationMs: 30,
    children: []
  };
}

function findMacroEvent(eventId, events = macroEditorDocument?.events || [], depth = 0, parentLoop = null) {
  for (let index = 0; index < events.length; index++) {
    const item = events[index];
    if (item.id === eventId) return { item, list: events, index, depth, parentLoop };
    if (item.type === "loop") {
      const nested = findMacroEvent(eventId, item.children, depth + 1, item);
      if (nested) return nested;
    }
  }
  return null;
}

function flattenMacroEvents(events = macroEditorDocument?.events || [], result = []) {
  for (const item of events) {
    result.push(item);
    if (item.type === "loop") flattenMacroEvents(item.children || [], result);
  }
  return result;
}

function pruneMacroEventSelection() {
  const validIds = new Set(flattenMacroEvents().map(item => item.id));
  macroEventSelection = new Set([...macroEventSelection].filter(id => validIds.has(id)));
  if (!validIds.has(macroEventSelectionAnchor)) macroEventSelectionAnchor = "";
  collapsedMacroLoops = new Set([...collapsedMacroLoops].filter(id => validIds.has(id)));
}

function syncMacroEventSelectionClasses() {
  $$("#macroEditorEvents .macro-event-card[data-event-id]").forEach(card => {
    const selected = macroEventSelection.has(card.dataset.eventId);
    card.classList.toggle("is-selected", selected);
    card.setAttribute("aria-selected", String(selected));
  });
}

function selectMacroEvent(eventId, { additive = false, range = false } = {}) {
  if (!findMacroEvent(eventId)) return;
  const flattened = flattenMacroEvents();
  if (range && macroEventSelectionAnchor) {
    const anchorIndex = flattened.findIndex(item => item.id === macroEventSelectionAnchor);
    const targetIndex = flattened.findIndex(item => item.id === eventId);
    if (anchorIndex >= 0 && targetIndex >= 0) {
      if (!additive) macroEventSelection.clear();
      const start = Math.min(anchorIndex, targetIndex);
      const end = Math.max(anchorIndex, targetIndex);
      flattened.slice(start, end + 1).forEach(item => macroEventSelection.add(item.id));
    }
  } else if (additive) {
    if (macroEventSelection.has(eventId)) macroEventSelection.delete(eventId);
    else macroEventSelection.add(eventId);
    macroEventSelectionAnchor = eventId;
  } else {
    macroEventSelection = new Set([eventId]);
    macroEventSelectionAnchor = eventId;
  }
  syncMacroEventSelectionClasses();
}

function countMacroEvents(events = macroEditorDocument?.events || []) {
  return events.reduce(
    (total, item) => total + 1 + (item.type === "loop" ? countMacroEvents(item.children) : 0),
    0
  );
}

function calculateMacroDuration(events = macroEditorDocument?.events || []) {
  let milliseconds = 0n;
  let indefinite = false;
  let unknown = false;

  for (const item of events) {
    if (item.type === "delay" || (item.type === "input" && item.action === "tap" &&
        item.key !== "WheelUp" && item.key !== "WheelDown")) {
      const maximum = item.type === "input" ? 10000 : 600000;
      milliseconds += BigInt(macroInteger(item.durationMs, 0, maximum));
      continue;
    }

    if (item.type === "loop") {
      const nested = calculateMacroDuration(item.children || []);
      unknown ||= nested.unknown;
      if (Number(item.count) === 0 || nested.indefinite) {
        indefinite = true;
      } else {
        const count = BigInt(Math.max(1, macroInteger(item.count, 1, 1000)));
        milliseconds += nested.milliseconds * count;
      }
      continue;
    }

    if (item.type === "raw" && item.timingUnknown !== false) unknown = true;
  }

  return { milliseconds, indefinite, unknown };
}

function formatMacroDuration(milliseconds) {
  if (milliseconds < 1000n) return `${milliseconds} ms`;

  const totalSeconds = milliseconds / 1000n;
  const remainingMilliseconds = milliseconds % 1000n;
  const decimal = remainingMilliseconds === 0n
    ? ""
    : `.${remainingMilliseconds.toString().padStart(3, "0").replace(/0+$/, "")}`;
  if (totalSeconds < 60n) return `${totalSeconds}${decimal} s`;

  const seconds = totalSeconds % 60n;
  const totalMinutes = totalSeconds / 60n;
  const secondsText = `${seconds.toString().padStart(2, "0")}${decimal}s`;
  if (totalMinutes < 60n) return `${totalMinutes}m ${secondsText}`;

  const minutes = totalMinutes % 60n;
  const totalHours = totalMinutes / 60n;
  if (totalHours < 24n) {
    return `${totalHours}h ${minutes.toString().padStart(2, "0")}m ${secondsText}`;
  }

  const days = totalHours / 24n;
  const hours = totalHours % 24n;
  return `${days}d ${hours.toString().padStart(2, "0")}h ${minutes.toString().padStart(2, "0")}m`;
}

function renderMacroEditorDuration() {
  const durationElement = $("#macroEditorDuration");
  const valueElement = $("#macroEditorTotalDuration");
  if (!durationElement || !valueElement) return;

  const duration = calculateMacroDuration();
  durationElement.classList.toggle("is-indefinite", duration.indefinite);
  durationElement.classList.toggle("is-estimate", !duration.indefinite && duration.unknown);

  if (duration.indefinite) {
    valueElement.textContent = "Until release";
    durationElement.title = "This sequence contains a loop that continues until the trigger is released.";
  } else if (duration.unknown) {
    const knownDuration = formatMacroDuration(duration.milliseconds);
    valueElement.textContent = duration.milliseconds > 0n ? `≥ ${knownDuration}` : "Variable";
    durationElement.title = duration.milliseconds > 0n
      ? `Advanced preserved steps may contain hidden timing. Known minimum: ${duration.milliseconds} ms.`
      : "Advanced preserved steps may contain hidden timing, so the total duration is variable.";
  } else {
    valueElement.textContent = formatMacroDuration(duration.milliseconds);
    durationElement.title = `Exact configured time from the first event to the last: ${duration.milliseconds} ms.`;
  }
}

function macroKeyOptions(selected) {
  return macroEditorKeys.map(([value, label]) =>
    `<option value="${escapeHtml(value)}"${value === selected ? " selected" : ""}>${escapeHtml(label)}</option>`
  ).join("");
}

function macroActionOptions(selected, wheelOnly = false) {
  const actions = wheelOnly
    ? [["tap", "Scroll"]]
    : [["tap", "Tap"], ["down", "Hold down"], ["up", "Release"]];
  return actions.map(([value, label]) =>
    `<option value="${value}"${value === selected ? " selected" : ""}>${label}</option>`
  ).join("");
}

function isCompactMacroEvent(item) {
  return item?.type === "input" || item?.type === "delay" || item?.type === "note";
}

function macroEventCards(events, depth) {
  return events.map((item, index) => macroEventCard(item, events, index, depth)).join("");
}

function macroEventCard(item, list, index, depth) {
  const canMoveUp = index > 0;
  const canMoveDown = index < list.length - 1;
  const selected = macroEventSelection.has(item.id);
  const folded = item.type === "loop" && collapsedMacroLoops.has(item.id);
  const foldControl = item.type === "loop"
    ? `<button class="macro-event-action fold" type="button" data-event-command="fold" title="${folded ? "Expand loop" : "Fold loop"}" aria-label="${folded ? "Expand loop" : "Fold loop"}">${folded ? "›" : "⌄"}</button>`
    : "";
  const controls = `
    <div class="macro-event-actions">
      ${foldControl}
      <button class="macro-event-action" type="button" data-event-command="up" title="Move up" ${canMoveUp ? "" : "disabled"}>↑</button>
      <button class="macro-event-action" type="button" data-event-command="down" title="Move down" ${canMoveDown ? "" : "disabled"}>↓</button>
      <button class="macro-event-action duplicate" type="button" data-event-command="duplicate" title="Duplicate event" aria-label="Duplicate event">⧉</button>
      <button class="macro-event-action delete" type="button" data-event-command="delete" title="Delete event">×</button>
    </div>`;

  if (item.type === "delay") {
    return `<article class="macro-event-card${selected ? " is-selected" : ""}" data-event-id="${escapeHtml(item.id)}" data-event-type="delay" aria-selected="${selected}">
      <span class="macro-event-icon" draggable="true" title="Click to select; drag to move the selection">◷</span>
      <div class="macro-event-main">
        <div class="macro-event-title"><strong>Delay</strong><small>Wait before the next action</small></div>
        <div class="macro-event-fields">
          <label>Duration <input type="number" min="1" max="600000" step="1" value="${Math.max(1, Math.round(item.durationMs || 1))}" data-event-field="durationMs" /></label>
          <span class="macro-event-unit">milliseconds</span>
        </div>
      </div>${controls}</article>`;
  }

  if (item.type === "loop") {
    const untilReleased = Number(item.count) === 0;
    const nestedCards = macroEventCards(item.children, depth + 1);
    const loopButtons = depth < 3
      ? `<button type="button" data-loop-add="input">+ Input</button>
         <button type="button" data-loop-add="delay">+ Delay</button>
         <button type="button" data-loop-add="loop">+ Loop</button>
         <button type="button" data-loop-add="note">+ Note</button>`
      : `<button type="button" data-loop-add="input">+ Input</button>
         <button type="button" data-loop-add="delay">+ Delay</button>
         <button type="button" data-loop-add="note">+ Note</button>`;
    return `<article class="macro-event-card${selected ? " is-selected" : ""}${folded ? " is-folded" : ""}" data-event-id="${escapeHtml(item.id)}" data-event-type="loop" aria-selected="${selected}">
      <span class="macro-event-icon" draggable="true" title="Click to select; drag to move the selection">↻</span>
      <div class="macro-event-main">
        <div class="macro-event-title"><strong>Loop</strong><small>Repeat a group of events</small></div>
        <div class="macro-event-fields">
          <label>Mode <select data-event-field="loopMode">
            <option value="finite"${untilReleased ? "" : " selected"}>Repeat count</option>
            <option value="infinite"${untilReleased ? " selected" : ""}>Until trigger released</option>
          </select></label>
          ${untilReleased ? "" : `<label>Times <input type="number" min="1" max="1000" step="1" value="${Math.max(1, Math.round(item.count || 2))}" data-event-field="count" /></label>`}
        </div>
      </div>${controls}
      <div class="macro-loop-body" data-event-container="${escapeHtml(item.id)}">
        <div class="macro-loop-events">${nestedCards}</div>
        ${item.children.length ? "" : `<div class="macro-loop-empty">Add at least one event to this loop.</div>`}
        <div class="macro-loop-add" data-loop-parent="${escapeHtml(item.id)}">${loopButtons}</div>
      </div>
    </article>`;
  }

  if (item.type === "note") {
    return `<article class="macro-event-card${selected ? " is-selected" : ""}" data-event-id="${escapeHtml(item.id)}" data-event-type="note" aria-selected="${selected}">
      <span class="macro-event-icon" draggable="true" title="Click to select; drag to move the selection">✎</span>
      <div class="macro-event-main">
        <div class="macro-event-title"><strong>Note</strong><small>A readable label that does not send input</small></div>
        <div class="macro-event-fields"><input type="text" maxlength="120" value="${escapeHtml(item.text)}" data-event-field="text" /></div>
      </div>${controls}</article>`;
  }

  if (item.type === "raw") {
    return `<article class="macro-event-card${selected ? " is-selected" : ""}" data-event-id="${escapeHtml(item.id)}" data-event-type="raw" aria-selected="${selected}">
      <span class="macro-event-icon" draggable="true" title="Click to select; drag to move the selection">◇</span>
      <div class="macro-event-main">
        <div class="macro-event-title"><strong>Advanced step</strong><small>Preserved from the original macro</small></div>
        <span class="macro-raw-summary">${escapeHtml(item.summary || "Preserved advanced action")}</span>
        <span class="macro-raw-lock">Its internal AHK stays unchanged and hidden.</span>
      </div>${controls}</article>`;
  }

  const wheelOnly = item.key === "WheelUp" || item.key === "WheelDown";
  if (wheelOnly) item.action = "tap";
  const showDuration = item.action === "tap" && !wheelOnly;
  return `<article class="macro-event-card${selected ? " is-selected" : ""}" data-event-id="${escapeHtml(item.id)}" data-event-type="input" aria-selected="${selected}">
    <span class="macro-event-icon" draggable="true" title="Click to select; drag to move the selection">⌨</span>
    <div class="macro-event-main">
      <div class="macro-event-title"><strong>Input</strong><small>Keyboard or mouse action</small></div>
      <div class="macro-event-fields">
        <label>Control <select data-event-field="key">${macroKeyOptions(item.key || "LButton")}</select></label>
        <label>Action <select data-event-field="action">${macroActionOptions(item.action || "tap", wheelOnly)}</select></label>
        ${showDuration ? `<label>Hold <input type="number" min="0" max="10000" step="1" value="${macroInteger(item.durationMs, 0, 10000)}" data-event-field="durationMs" /></label><span class="macro-event-unit">ms</span>` : ""}
      </div>
    </div>${controls}</article>`;
}

function captureMacroEventLayout() {
  return new Map(
    $$("#macroEditorEvents .macro-event-card[data-event-id]").map(card => [
      card.dataset.eventId,
      card.getBoundingClientRect()
    ])
  );
}

function macroEventTreeIds(item) {
  return [
    item.id,
    ...(item.type === "loop"
      ? (item.children || []).flatMap(macroEventTreeIds)
      : [])
  ];
}

function animateMacroEventLayout(previousLayout, enteringIds = []) {
  window.cancelAnimationFrame(macroEventAnimationFrame);
  macroEventAnimationFrame = 0;
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

  const entering = new Set(enteringIds);
  macroEventAnimationFrame = window.requestAnimationFrame(() => {
    macroEventAnimationFrame = 0;
    const cards = $$("#macroEditorEvents .macro-event-card[data-event-id]");
    const totalDeltas = new Map();

    cards.forEach(card => {
      const eventId = card.dataset.eventId;
      const before = previousLayout?.get(eventId);
      if (!before) return;
      const after = card.getBoundingClientRect();
      totalDeltas.set(eventId, {
        x: before.left - after.left,
        y: before.top - after.top
      });
    });

    cards.forEach(card => {
      const eventId = card.dataset.eventId;
      const parentCard = card.parentElement?.closest(".macro-event-card[data-event-id]");
      const parentId = parentCard?.dataset.eventId;
      if (entering.has(eventId)) {
        if (parentId && entering.has(parentId)) return;
        card.animate(
          [
            { opacity: 0, transform: "translate3d(0, 9px, 0) scale(.985)" },
            { opacity: 1, transform: "translate3d(0, 0, 0) scale(1)" }
          ],
          { duration: 220, easing: "cubic-bezier(.2, .78, .24, 1)" }
        );
        return;
      }

      const total = totalDeltas.get(eventId);
      if (!total) return;
      const parentTotal = totalDeltas.get(parentId) || { x: 0, y: 0 };
      const deltaX = total.x - parentTotal.x;
      const deltaY = total.y - parentTotal.y;
      if (Math.abs(deltaX) < .5 && Math.abs(deltaY) < .5) return;

      card.animate(
        [
          { transform: `translate3d(${deltaX}px, ${deltaY}px, 0)`, opacity: .92 },
          { transform: "translate3d(0, 0, 0)", opacity: 1 }
        ],
        { duration: 240, easing: "cubic-bezier(.2, .78, .24, 1)" }
      );
    });
  });
}

function renderMacroEditorEvents({ previousLayout = null, enteringIds = [] } = {}) {
  if (!macroEditorDocument) return;

  pruneMacroEventSelection();

  const list = $("#macroEditorEvents");
  list.innerHTML = macroEditorDocument.canEditEvents
    ? macroEventCards(macroEditorDocument.events, 0)
    : "";

  const eventCount = countMacroEvents();
  $("#macroEditorEventCount").textContent = `${eventCount} event${eventCount === 1 ? "" : "s"}`;
  $("#macroEditorEmpty").classList.toggle("hidden", macroEditorDocument.events.length > 0);
  $("#macroClearAllButton").disabled = eventCount === 0 || macroRecordingState.recording || !macroEditorDocument.canEditEvents;
  renderMacroEditorDuration();
  renderMacroPreviewButton();
  if (previousLayout || enteringIds.length) {
    animateMacroEventLayout(previousLayout, enteringIds);
  }
}

function addMacroEditorEvent(type, parentLoopId = "") {
  if (!macroEditorDocument?.canSave || !macroEditorDocument.canEditEvents || macroRecordingState.recording) return;
  const previousLayout = captureMacroEventLayout();
  const event = createMacroEvent(type);
  if (!parentLoopId) {
    recordMacroEventHistory("add");
    macroEditorDocument.events.push(event);
  } else {
    const parent = findMacroEvent(parentLoopId);
    if (!parent || parent.item.type !== "loop") return;
    if (type === "loop" && parent.depth >= 3) {
      showToast("Loops can be nested up to four levels.", true);
      return;
    }
    recordMacroEventHistory("add");
    parent.item.children.push(event);
  }
  renderMacroEditorEvents({ previousLayout, enteringIds: macroEventTreeIds(event) });
}

function moveMacroEditorEvent(eventId, direction) {
  if (!macroEditorDocument?.canEditEvents || macroRecordingState.recording) return;
  const location = findMacroEvent(eventId);
  if (!location) return;
  const nextIndex = location.index + direction;
  if (nextIndex < 0 || nextIndex >= location.list.length) return;
  const previousLayout = captureMacroEventLayout();
  recordMacroEventHistory("move");
  [location.list[location.index], location.list[nextIndex]] =
    [location.list[nextIndex], location.list[location.index]];
  renderMacroEditorEvents({ previousLayout });
}

function deleteMacroEditorEvent(eventId) {
  if (!macroEditorDocument?.canEditEvents || macroRecordingState.recording) return;
  const location = findMacroEvent(eventId);
  if (!location) return;
  recordMacroEventHistory("delete");
  location.list.splice(location.index, 1);
  renderMacroEditorEvents();
}

function clearAllMacroEditorEvents() {
  if (!macroEditorDocument?.canEditEvents || macroRecordingState.recording || countMacroEvents() === 0) return;
  recordMacroEventHistory("clear");
  macroEditorDocument.events = [];
  macroRecordingBaseline = null;
  renderMacroEditorEvents();
}

function duplicateMacroEventTree(item) {
  return {
    ...item,
    id: newMacroEventId(),
    children: (item.children || []).map(duplicateMacroEventTree)
  };
}

function duplicateMacroEditorEvent(eventId) {
  if (!macroEditorDocument?.canEditEvents || macroRecordingState.recording) return;
  const location = findMacroEvent(eventId);
  if (!location) return;
  const previousLayout = captureMacroEventLayout();
  const duplicate = duplicateMacroEventTree(location.item);
  recordMacroEventHistory("duplicate");
  location.list.splice(location.index + 1, 0, duplicate);
  renderMacroEditorEvents({ previousLayout, enteringIds: macroEventTreeIds(duplicate) });
}

function macroEventContainsId(item, eventId) {
  if (item.id === eventId) return true;
  return item.type === "loop" && (item.children || []).some(child => macroEventContainsId(child, eventId));
}

function selectedMacroEventRoots() {
  const selected = macroEventSelection.size
    ? new Set(macroEventSelection)
    : new Set(macroEventDragId ? [macroEventDragId] : []);
  const roots = [];
  const visit = (events, ancestorSelected = false) => {
    for (const item of events) {
      const itemSelected = selected.has(item.id);
      if (itemSelected && !ancestorSelected) roots.push(item);
      if (item.type === "loop") visit(item.children || [], ancestorSelected || itemSelected);
    }
  };
  visit(macroEditorDocument?.events || []);
  return roots;
}

function macroEventLoopLevels(item) {
  if (item.type !== "loop") return 0;
  return 1 + (item.children || []).reduce(
    (maximum, child) => Math.max(maximum, macroEventLoopLevels(child)),
    0
  );
}

function macroEventContainerLocation(container) {
  if (!container || container.dataset.eventContainer === "root") {
    return { list: macroEditorDocument?.events || [], parentLoop: null, depth: 0 };
  }

  const parent = findMacroEvent(container.dataset.eventContainer);
  if (!parent || parent.item.type !== "loop") return null;
  return { list: parent.item.children, parentLoop: parent.item, depth: parent.depth + 1 };
}

function clearMacroEventDropState() {
  $$(".macro-event-card.drag-before, .macro-event-card.drag-after, .macro-event-card.drag-over").forEach(card => {
    card.classList.remove("drag-before", "drag-after", "drag-over");
  });
  $$("[data-event-container].drag-target-container").forEach(container => {
    container.classList.remove("drag-target-container");
  });
}

function resolveMacroEventDrop(event) {
  const sources = selectedMacroEventRoots()
    .map(item => findMacroEvent(item.id))
    .filter(Boolean);
  const container = event.target.closest("[data-event-container]") || $("#macroEditorEvents");
  const destination = macroEventContainerLocation(container);
  if (!sources.length || !destination) return null;

  if (destination.parentLoop && sources.some(source =>
      macroEventContainsId(source.item, destination.parentLoop.id))) {
    return null;
  }
  if (sources.some(source => destination.depth + macroEventLoopLevels(source.item) > 4)) {
    return null;
  }

  let targetCard = event.target.closest("[data-event-id]");
  let target = targetCard ? findMacroEvent(targetCard.dataset.eventId) : null;
  if (target && sources.some(source =>
      source.item === target.item || macroEventContainsId(source.item, target.item.id))) {
    return null;
  }
  if (!target || target.list !== destination.list) {
    target = null;
    targetCard = null;
  }

  const placeAfter = targetCard
    ? event.clientY > targetCard.getBoundingClientRect().top + targetCard.getBoundingClientRect().height / 2
    : true;
  const insertionIndex = target ? target.index + (placeAfter ? 1 : 0) : destination.list.length;
  return { sources, destination, container, target, targetCard, placeAfter, insertionIndex };
}

function applyMacroEventDrop(drop) {
  recordMacroEventHistory("drag");
  const movingItems = drop.sources.map(source => source.item);
  const removals = new Map();
  drop.sources.forEach(source => {
    if (!removals.has(source.list)) removals.set(source.list, []);
    removals.get(source.list).push(source.index);
  });
  removals.forEach((indices, list) => {
    indices.sort((left, right) => right - left).forEach(index => list.splice(index, 1));
  });

  let insertionIndex;
  if (drop.target && drop.destination.list.includes(drop.target.item)) {
    insertionIndex = drop.destination.list.indexOf(drop.target.item) + (drop.placeAfter ? 1 : 0);
  } else {
    insertionIndex = drop.destination.list.length;
  }
  drop.destination.list.splice(insertionIndex, 0, ...movingItems);
}

function updateMacroEditorEvent(eventId, field, value) {
  if (!macroEditorDocument?.canEditEvents || macroRecordingState.recording) return;
  const location = findMacroEvent(eventId);
  if (!location) return;
  const item = location.item;
  recordMacroEventHistory(`field:${eventId}:${field}`);

  if (field === "loopMode") {
    item.count = value === "infinite" ? 0 : Math.max(1, Number(item.count) || 2);
    renderMacroEditorEvents();
    return;
  }
  if (field === "durationMs") {
    item.durationMs = macroInteger(value, 0, item.type === "input" ? 10000 : 600000);
  } else if (field === "count") {
    item.count = Math.max(1, macroInteger(value, 1, 1000));
  } else item[field] = value;

  if (field === "key" && (value === "WheelUp" || value === "WheelDown")) {
    item.action = "tap";
    renderMacroEditorEvents();
  } else if (field === "action") {
    if (value === "tap" && !item.durationMs) item.durationMs = 30;
    renderMacroEditorEvents();
  } else {
    renderMacroEditorDuration();
  }
}

function cleanMacroEditorEvents(events) {
  return events.map(item => ({
    id: item.id,
    type: item.type,
    key: item.key || "",
    action: item.action || "",
    durationMs: macroInteger(item.durationMs, 0, item.type === "input" ? 10000 : 600000),
    count: macroInteger(item.count, 0, 1000),
    text: item.text || "",
    rawId: item.rawId || "",
    summary: item.summary || "",
    timingUnknown: item.timingUnknown !== false,
    children: item.type === "loop" ? cleanMacroEditorEvents(item.children || []) : []
  }));
}

function macroEditorRequest() {
  return {
    sessionId: macroEditorDocument?.sessionId || "",
    comboId: macroEditorDocument?.comboId || "",
    character: macroEditorDocument?.character || "",
    name: $("#macroEditorName").value.trim(),
    description: $("#macroEditorDescription").value.trim(),
    fpsTag: $("#macroEditorFpsTag").value,
    testing: $("#macroEditorTestingTag").checked,
    macroTrigger: macroEditorDocument?.macroTrigger || "",
    events: macroEditorDocument?.canEditEvents
      ? cleanMacroEditorEvents(macroEditorDocument.events)
      : []
  };
}

function renderMacroPreviewButton() {
  const button = $("#previewMacroEditorButton");
  if (!button) return;
  button.textContent = macroPreviewRunning ? "Stop test" : "Test changes";
  button.classList.toggle("is-running", macroPreviewRunning);
  button.disabled = macroEditorSaving || macroRecordingState.recording ||
    !macroEditorDocument?.canEditEvents || countMacroEvents() === 0;
}

function invalidateMacroPreview() {
  if (!macroPreviewRunning) return;
  macroPreviewRunning = false;
  post("stopMacroPreview");
  renderMacroPreviewButton();
}

function toggleMacroPreview() {
  if (!macroEditorDocument?.canEditEvents || macroEditorSaving || macroRecordingState.recording) return;
  if (macroPreviewRunning) {
    post("stopMacroPreview");
    return;
  }
  if (macroEditorDocument.events.length === 0) {
    showToast("Add at least one event before testing.", true);
    return;
  }
  post("testMacroDefinition", macroEditorRequest());
}

function submitMacroEditor(event) {
  event.preventDefault();
  if (!macroEditorDocument?.canSave || macroEditorSaving) return;
  if (macroRecordingState.recording) {
    showToast("Stop recording before saving the macro.", true);
    return;
  }

  const name = $("#macroEditorName").value.trim();
  const description = $("#macroEditorDescription").value.trim();
  if (!name) {
    showToast("Macro name is required.", true);
    $("#macroEditorName").focus();
    return;
  }
  if (/[\r\n\t=|]/.test(name) || /[\r\n\t=|]/.test(description)) {
    showToast("Names cannot contain tabs, line breaks, =, or |.", true);
    return;
  }
  if (macroEditorDocument.canEditEvents && macroEditorDocument.events.length === 0) {
    showToast("Add at least one event before saving.", true);
    return;
  }

  setMacroEditorSaving(true);
  if (macroPreviewRunning) post("stopMacroPreview");
  const sent = post("saveMacroDefinition", macroEditorRequest());
  if (!sent) setMacroEditorSaving(false);
}

function openMacroDelete(combo) {
  if (!combo || combo.builtIn) return;

  macroDeleteTarget = {
    comboId: combo.value,
    name: combo.label,
    character: state.character
  };

  $("#macroDeleteName").textContent = combo.label;
  $("#macroDeleteCharacter").textContent = state.character;
  $("#macroDeleteModal").classList.remove("hidden");
  setTimeout(() => $("#confirmMacroDeleteButton").focus(), 0);
}

function closeMacroDelete() {
  $("#macroDeleteModal").classList.add("hidden");
  macroDeleteTarget = null;
}

function confirmMacroDelete() {
  if (!macroDeleteTarget) return;

  const target = macroDeleteTarget;
  closeMacroDelete();
  post("deleteMacro", { comboId: target.comboId });
}

function showToast(message, error = false) {
  const signature = `${error ? "error" : "notice"}:${message}`;
  const now = Date.now();
  if (signature === lastToastSignature && now - lastToastAt <= DUPLICATE_TOAST_WINDOW_MS) {
    return;
  }

  lastToastSignature = signature;
  lastToastAt = now;

  const container = $("#toastContainer");
  while (container.children.length >= MAX_VISIBLE_TOASTS) {
    container.firstElementChild?.remove();
  }

  const toast = document.createElement("div");
  toast.className = `toast${error ? " error" : ""}`;
  toast.textContent = message;
  container.appendChild(toast);
  setTimeout(() => toast.remove(), 3600);
}

function escapeHtml(value) {
  return String(value).replace(/[&<>'"]/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" }[char]));
}

function navigateToPage(pageName) {
  const nextPage = $(`.page[data-page-panel="${pageName}"]`);
  const currentPage = $(".page.active");
  if (!nextPage || nextPage === currentPage) return;

  $$(".nav-item").forEach(item => {
    const selected = item.dataset.page === pageName;
    item.classList.toggle("active", selected);
    item.setAttribute("aria-current", selected ? "page" : "false");
  });

  currentPage?.classList.remove("active", "is-entering");
  nextPage.classList.remove("is-entering");
  nextPage.classList.add("active");

  if (!window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    void nextPage.offsetWidth;
    nextPage.classList.add("is-entering");
    window.setTimeout(() => nextPage.classList.remove("is-entering"), 560);
  }

  requestAnimationFrame(updateAllSegmentedIndicators);
}

$$('.nav-item').forEach(button => button.addEventListener('click', () => navigateToPage(button.dataset.page)));

$$('[data-window-action]').forEach(button => button.addEventListener('click', () => {
  if (button.dataset.windowAction === 'close') post('windowClose');
  if (button.dataset.windowAction === 'minimize') post('windowMinimize');
  if (button.dataset.windowAction === 'maximize') post('windowToggleMaximize');
}));

$('#titlebar').addEventListener('mousedown', event => {
  if (event.target.closest('button')) return;
  post(event.detail >= 2 ? 'windowToggleMaximize' : 'windowDrag');
});

$('#startGameButton').addEventListener('click', () => {
  post('startGame');
});
$('#soundToggle').addEventListener('change', event => post('setSoundsEnabled', { value: event.target.checked }));
$$('[data-mode]').forEach(button => button.addEventListener('click', () => {
  previewSegmentedSelection(button);
  post('setAppMode', { value: button.dataset.mode });
}));

$$('[data-skip-mode]').forEach(button => button.addEventListener('click', () => {
  previewSegmentedSelection(button);
  post('setSkipStopMode', { value: button.dataset.skipMode });
}));
$('#browseExecutableButton').addEventListener('click', () => post('browseAutoLaunch'));
$('#clearExecutableButton').addEventListener('click', () => post('clearAutoLaunch'));
$('#autoLaunchToggle').addEventListener('change', event => {
  post('setAutoLaunchEnabled', { value: event.target.checked });
});
$('#resetHotkeysButton').addEventListener('click', () => {
  if (!state.macroRunning) post('resetHotkeys');
});
$$('[data-hotkey-scope]').forEach(button => button.addEventListener('click', () => {
  if (state.macroRunning) return;
  previewSegmentedSelection(button);
  post('setHotkeyScope', { value: button.dataset.hotkeyScope });
}));
$('#fpsUnlockToggle').addEventListener('change', event => {
  post('setFpsUnlockEnabled', { value: event.target.checked });
});
$('#fpsTargetSlider').addEventListener('pointerdown', () => { fpsTargetEditing = true; });
$('#fpsTargetSlider').addEventListener('input', event => queueFpsTarget(event.target.value));
$('#fpsTargetSlider').addEventListener('change', event => {
  fpsTargetEditing = false;
  queueFpsTarget(event.target.value, true);
});
$('#fpsTargetSlider').addEventListener('pointercancel', () => {
  fpsTargetEditing = false;
  renderFps();
});
$('#fpsTargetInput').addEventListener('focus', () => { fpsTargetEditing = true; });
$('#fpsTargetInput').addEventListener('input', event => {
  const parsed = Number(event.target.value);
  if (Number.isFinite(parsed) && parsed >= 10 && parsed <= 420) queueFpsTarget(parsed);
});
$('#fpsTargetInput').addEventListener('change', event => {
  fpsTargetEditing = false;
  queueFpsTarget(event.target.value, true);
});
$('#fpsTargetInput').addEventListener('blur', event => {
  if (!fpsTargetEditing) return;
  fpsTargetEditing = false;
  queueFpsTarget(event.target.value, true);
});
$$('[data-fps-preset]').forEach(button => button.addEventListener('click', () => {
  queueFpsTarget(button.dataset.fpsPreset, true);
}));
$('#themeToggle').addEventListener('click', toggleTheme);
$$('[data-community-link]').forEach(button => button.addEventListener('click', () => openCommunityLink(button.dataset.communityLink)));
$('#checkUpdateButton').addEventListener('click', () => post('checkForUpdates'));
$('#installUpdateButton').addEventListener('click', () => {
  if (!state.macroRunning) post('installUpdate');
});
$('#viewReleaseButton').addEventListener('click', () => {
  post('openExternal', { url: updateState.releaseUrl || releasesUrl });
});
$('#remindUpdateLaterButton').addEventListener('click', snoozeAvailableUpdate);
$('#updateNowButton').addEventListener('click', acceptAvailableUpdate);
$('#cancelHotkeyButton').addEventListener('click', endHotkeyCapture);
$('#hotkeyModal').addEventListener('pointerdown', event => {
  if (!captureTarget || (event.button !== 3 && event.button !== 4)) return;

  event.preventDefault();
  event.stopPropagation();
  const mappedKey = event.button === 3 ? 'XButton1' : 'XButton2';
  commitCapturedHotkey(mappedKey);
});
$('#addMacroButton').addEventListener('click', openMacroImport);
$('#createMacroButton').addEventListener('click', openMacroCreate);
$('#editMacroButton').addEventListener('click', () => {
  const selectedCombo = getSelectedCombo();
  if (selectedCombo && !state.macroRunning) {
    openMacroEdit(selectedCombo);
  }
});
$('#exportMacroButton').addEventListener('click', () => {
  const selectedCombo = getSelectedCombo();
  if (selectedCombo && !state.macroRunning) {
    post("exportMacro", { comboId: selectedCombo.value });
  }
});

$('#deleteMacroButton').addEventListener('click', () => {
  const selectedCombo = getSelectedCombo();
  if (selectedCombo && !selectedCombo.builtIn && !state.macroRunning) {
    openMacroDelete(selectedCombo);
  }
});
$('#cancelMacroEditorButton').addEventListener('click', () => closeMacroEditor());
$('#closeMacroEditorButton').addEventListener('click', () => closeMacroEditor());
$('#macroEditorForm').addEventListener('submit', submitMacroEditor);
$('#previewMacroEditorButton').addEventListener('click', toggleMacroPreview);
$('#macroEditorModal').addEventListener('mousedown', event => {
  if (event.target === $('#macroEditorModal')) closeMacroEditor();
});
$$('[data-macro-add]').forEach(button => button.addEventListener('click', () => {
  addMacroEditorEvent(button.dataset.macroAdd);
}));

const macroEditorEventsElement = $('#macroEditorEvents');
macroEditorEventsElement.addEventListener('click', event => {
  const commandButton = event.target.closest('[data-event-command]');
  if (commandButton) {
    const card = commandButton.closest('[data-event-id]');
    if (!card) return;
    const command = commandButton.dataset.eventCommand;
    if (command === 'up') moveMacroEditorEvent(card.dataset.eventId, -1);
    else if (command === 'down') moveMacroEditorEvent(card.dataset.eventId, 1);
    else if (command === 'duplicate') duplicateMacroEditorEvent(card.dataset.eventId);
    else if (command === 'delete') deleteMacroEditorEvent(card.dataset.eventId);
    else if (command === 'fold') {
      if (collapsedMacroLoops.has(card.dataset.eventId)) collapsedMacroLoops.delete(card.dataset.eventId);
      else collapsedMacroLoops.add(card.dataset.eventId);
      renderMacroEditorEvents();
    }
    return;
  }

  const addButton = event.target.closest('[data-loop-add]');
  if (addButton) {
    const parent = addButton.closest('[data-loop-parent]');
    if (parent) addMacroEditorEvent(addButton.dataset.loopAdd, parent.dataset.loopParent);
    return;
  }

  const card = event.target.closest('[data-event-id]');
  if (!card || event.target.closest('input, select, button')) return;
  selectMacroEvent(card.dataset.eventId, {
    additive: event.ctrlKey || event.metaKey,
    range: event.shiftKey
  });
});

function handleMacroEditorFieldChange(event) {
  const field = event.target.closest('[data-event-field]');
  if (!field) return;
  const card = field.closest('[data-event-id]');
  if (!card) return;
  updateMacroEditorEvent(card.dataset.eventId, field.dataset.eventField, field.value);
}

macroEditorEventsElement.addEventListener('change', handleMacroEditorFieldChange);
macroEditorEventsElement.addEventListener('input', event => {
  if (['text', 'durationMs', 'count'].includes(event.target.dataset.eventField)) {
    handleMacroEditorFieldChange(event);
  }
});

macroEditorEventsElement.addEventListener('dragstart', event => {
  if (macroRecordingState.recording) {
    event.preventDefault();
    return;
  }
  const card = event.target.closest('[data-event-id]');
  if (!card || event.target.closest('input, select, button')) {
    event.preventDefault();
    return;
  }
  macroEventDragId = card.dataset.eventId;
  if (!macroEventSelection.has(macroEventDragId)) {
    macroEventSelection = new Set([macroEventDragId]);
    macroEventSelectionAnchor = macroEventDragId;
    syncMacroEventSelectionClasses();
  }
  macroEventDragIds = selectedMacroEventRoots().map(item => item.id);
  macroEventDragIds.forEach(id => {
    macroEditorEventsElement.querySelector(`[data-event-id="${CSS.escape(id)}"]`)?.classList.add('is-dragging');
  });
  event.dataTransfer.effectAllowed = 'move';
  event.dataTransfer.setData('text/plain', macroEventDragIds.join(','));
});

macroEditorEventsElement.addEventListener('dragover', event => {
  clearMacroEventDropState();
  const drop = resolveMacroEventDrop(event);
  if (!drop) return;
  event.preventDefault();
  event.dataTransfer.dropEffect = 'move';
  drop.container.classList.add('drag-target-container');
  if (drop.targetCard) {
    drop.targetCard.classList.add(drop.placeAfter ? 'drag-after' : 'drag-before');
  }
});

macroEditorEventsElement.addEventListener('drop', event => {
  const drop = resolveMacroEventDrop(event);
  if (!drop) return;
  event.preventDefault();

  const previousLayout = captureMacroEventLayout();
  applyMacroEventDrop(drop);
  macroEventDragId = '';
  macroEventDragIds = [];
  clearMacroEventDropState();
  renderMacroEditorEvents({ previousLayout });
});

macroEditorEventsElement.addEventListener('dragend', () => {
  macroEventDragId = '';
  macroEventDragIds = [];
  clearMacroEventDropState();
  $$('.macro-event-card.is-dragging').forEach(card => {
    card.classList.remove('is-dragging');
  });
});

$('#toggleMacroDetailsButton').addEventListener('click', () => {
  const shell = $('#macroEditorForm');
  const collapsed = shell.classList.toggle('details-collapsed');
  $('#toggleMacroDetailsButton').setAttribute('aria-pressed', String(collapsed));
  $('#toggleMacroDetailsButton').textContent = collapsed ? 'Expand' : 'Collapse';
  $('#toggleMacroDetailsButton').title = collapsed ? 'Expand macro details' : 'Collapse macro details';
});

$('#macroTriggerCaptureButton').addEventListener('click', beginMacroTriggerCapture);
$('#macroTriggerClearButton').addEventListener('click', () => {
  if (!macroEditorDocument || macroRecordingState.recording) return;
  macroEditorDocument.macroTrigger = '';
  renderMacroTrigger();
});
$('#macroClearAllButton').addEventListener('click', clearAllMacroEditorEvents);

$('#macroRecorderToggleButton').addEventListener('click', () => {
  post(macroRecordingState.recording ? 'stopMacroRecording' : 'startMacroRecording');
});
$('#macroRecorderLastWindow').addEventListener('change', event => {
  $('#macroRecorderWindowSeconds').disabled = !event.target.checked;
  queueMacroRecordingSettings();
});
$('#macroRecorderWindowSeconds').addEventListener('change', queueMacroRecordingSettings);
$('#macroRecorderKeys').addEventListener('change', queueMacroRecordingSettings);
$('#macroRecorderSelectAll').addEventListener('click', () => {
  $$('#macroRecorderKeys input').forEach(input => { input.checked = true; });
  queueMacroRecordingSettings();
});
$('#macroRecorderSelectNone').addEventListener('click', () => {
  $$('#macroRecorderKeys input').forEach(input => { input.checked = false; });
  queueMacroRecordingSettings();
});

$('#cancelMacroDeleteButton').addEventListener('click', closeMacroDelete);
$('#confirmMacroDeleteButton').addEventListener('click', confirmMacroDelete);
$('#macroDeleteModal').addEventListener('mousedown', event => {
  if (event.target === $('#macroDeleteModal')) closeMacroDelete();
});

window.addEventListener('resize', () => requestAnimationFrame(updateAllSegmentedIndicators));
window.addEventListener('pointermove', moveComboDuringReorder, { passive: false });
window.addEventListener('pointerup', event => finishComboReorder(event, false));
window.addEventListener('pointercancel', event => finishComboReorder(event, true));
window.addEventListener('blur', () => {
  if (!comboPressState) return;

  const syntheticEvent = {
    pointerId: comboPressState.pointerId,
    preventDefault() {}
  };
  finishComboReorder(syntheticEvent, true);
});

window.addEventListener('keydown', event => {
  if (event.key === 'Escape' && comboPressState?.active) {
    const syntheticEvent = {
      pointerId: comboPressState.pointerId,
      preventDefault() {}
    };
    finishComboReorder(syntheticEvent, true);
    return;
  }

  if (captureTarget) {
    event.preventDefault();
    event.stopPropagation();

    if (event.key === 'Escape') {
      endHotkeyCapture();
      return;
    }

    const mappedKey = mapKeyboardEvent(event);
    if (!mappedKey) {
      $('#capturedKey').textContent = t("unsupported");
      return;
    }

    commitCapturedHotkey(mappedKey);
    return;
  }

  const macroEditorOpen = !$('#macroEditorModal').classList.contains('hidden');
  const historyShortcut = (event.ctrlKey || event.metaKey) && !event.altKey;
  const historyKey = event.key.toLowerCase();
  const textEditing = event.target instanceof HTMLElement &&
    (event.target.isContentEditable || event.target.matches('input[type="text"], textarea'));
  if (macroEditorOpen && historyShortcut && !textEditing &&
      (historyKey === 'z' || historyKey === 'y')) {
    event.preventDefault();
    if (historyKey === 'y' || (historyKey === 'z' && event.shiftKey)) redoMacroEditorEvents();
    else undoMacroEditorEvents();
    return;
  }

  if (event.key === 'Escape' && !$('#macroEditorModal').classList.contains('hidden')) {
    closeMacroEditor();
    return;
  }

  if (event.key === 'Escape' && !$('#macroDeleteModal').classList.contains('hidden')) {
    closeMacroDelete();
    return;
  }

  if (event.key === 'Escape' && !$('#updatePromptModal').classList.contains('hidden')) {
    snoozeAvailableUpdate();
    return;
  }

});

const savedTheme = localStorage.getItem(THEME_STORAGE_KEY);
const systemPrefersLight = window.matchMedia?.('(prefers-color-scheme: light)').matches;
applyTheme(savedTheme || (systemPrefersLight ? 'light' : 'dark'), false);

document.documentElement.lang = "en";
document.documentElement.dir = "ltr";
applyStaticTranslations();
loadBuildInfo();

bridge?.addEventListener('message', event => applyMessage(event.data));
post('closeMacroEditorSession');
requestState();
render();

function runStartupAnimation() {
  const body = document.body;
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (reducedMotion) {
    body.classList.remove("app-starting");
    return;
  }

  requestAnimationFrame(() => {
    body.classList.remove("app-starting");
    body.classList.add("app-ready");
    window.setTimeout(() => body.classList.remove("app-ready"), 850);
  });
}

runStartupAnimation();
