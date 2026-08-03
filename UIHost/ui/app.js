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
  charactersTitle: "Characters & combos",
  activeCharacter: "ACTIVE CHARACTER",
  inputSettings: "INPUT SETTINGS",
  hotkeysTitle: "Hotkeys",
  hotkeyInfo: "Hotkeys are active only while the selected game window is focused. Gameplay keys and duplicate assignments are rejected.",
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
let macroEditTarget = null;
let macroDeleteTarget = null;

const hotkeyCatalog = [
  { target: "Trigger", title: "Trigger", description: "Run the selected action", stateKey: "triggerKey" },
  { target: "ModeToggle", title: "Mode", description: "Switch application mode", stateKey: "modeToggleKey" },
  { target: "CharacterToggle", title: "Character", description: "Cycle through characters", stateKey: "characterToggleKey" },
  { target: "ComboToggle", title: "Combo", description: "Cycle the current character combos", stateKey: "comboToggleKey" }
];

let state = {
  macroEnabled: false,
  soundsEnabled: true,
  macroRunning: false,
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
  autoLaunchPath: "",
  autoLaunchEnabled: true,
  version: "—"
};

let captureTarget = null;

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
      macroEnabled: boolValue(message.macroEnabled),
      soundsEnabled: boolValue(message.soundsEnabled),
      macroRunning: boolValue(message.macroRunning),
      autoLaunchEnabled: boolValue(message.autoLaunchEnabled)
    };
    render();
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

  const macroStateButton = $("#macroStateButton");
  macroStateButton.textContent = state.macroEnabled ? "ON" : "OFF";
  macroStateButton.classList.toggle("off", !state.macroEnabled);
  macroStateButton.classList.toggle("running", state.macroRunning);
  macroStateButton.disabled = state.macroRunning;
  macroStateButton.setAttribute("aria-pressed", state.macroEnabled ? "true" : "false");
  macroStateButton.title = state.macroRunning
    ? "Release the trigger before changing macro state."
    : (state.macroEnabled ? "Turn macros OFF" : "Turn macros ON");

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
      <img alt="${escapeHtml(name)}" src="${portraitUrl(name)}" />
      <div class="character-card-copy">
        <strong class="preserve-ltr">${escapeHtml(name)}</strong>
      </div>`;

    const image = button.querySelector("img");
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
  if (testing) badges.push({ text: "TESTING", className: "testing-badge" });

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
  addMacroButton.disabled = state.macroRunning || !state.character;
  addMacroButton.title = state.macroRunning
    ? "Release the trigger before importing a macro."
    : `Import an AHK macro for ${state.character}`;

  const selectedCombo = getSelectedCombo();
  const hasSelectedCombo = Boolean(selectedCombo);
  const canManageSelected = hasSelectedCombo && !state.macroRunning;
  const characterMacroCount = characterCatalog[state.character]?.combos?.length || 0;
  const isLastCharacterMacro = characterMacroCount <= 1;
  const canDelete = canManageSelected && !selectedCombo.builtIn && !isLastCharacterMacro;

  const editMacroButton = $("#editMacroButton");
  editMacroButton.disabled = !canManageSelected;
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
    : isLastCharacterMacro
      ? "Import another macro for this character before deleting its last macro."
      : "Release the trigger before deleting this macro.";
  deleteMacroButton.setAttribute(
    "aria-label",
    canDelete
      ? `Delete ${selectedCombo.label}`
      : isLastCharacterMacro
        ? "The final macro for this character cannot be deleted"
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
}

function endHotkeyCapture() {
  captureTarget = null;
  $("#hotkeyModal").classList.add("hidden");
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

function openMacroEdit(combo) {
  if (!combo || state.macroRunning) return;

  macroEditTarget = {
    comboId: combo.value,
    character: state.character
  };

  $("#macroEditCharacter").textContent = state.character;
  $("#macroEditName").value = combo.label || "";
  $("#macroEditDescription").value = combo.tooltip || "";
  $("#macroEditFpsTag").value = combo.fps || "";
  $("#macroEditTestingTag").checked = Boolean(combo.testing);
  $("#macroEditModal").classList.remove("hidden");
  setTimeout(() => {
    $("#macroEditName").focus();
    $("#macroEditName").select();
  }, 0);
}

function closeMacroEdit() {
  $("#macroEditModal").classList.add("hidden");
  macroEditTarget = null;
}

function submitMacroEdit(event) {
  event.preventDefault();

  const target = macroEditTarget;
  const comboName = $("#macroEditName").value.trim();
  const tooltip = $("#macroEditDescription").value.trim();
  const tags = [
    $("#macroEditFpsTag").value,
    $("#macroEditTestingTag").checked ? "TESTING" : ""
  ].filter(Boolean);

  if (!target || !getSelectedCombo() || target.comboId !== getSelectedCombo().value) {
    showToast("The selected macro is no longer available.", true);
    closeMacroEdit();
    return;
  }
  if (!comboName) {
    showToast("Macro name is required.", true);
    return;
  }
  if (/[\r\n\t=|]/.test(comboName) || /[\r\n\t=|]/.test(tooltip)) {
    showToast("Names cannot contain tabs, line breaks, =, or |.", true);
    return;
  }

  closeMacroEdit();
  post("editMacro", {
    comboId: target.comboId,
    comboName,
    tooltip,
    tag: tags.join(", ")
  });
}

function openMacroDelete(combo) {
  if (!combo || combo.builtIn) return;

  const macroCount = characterCatalog[state.character]?.combos?.length || 0;
  if (macroCount <= 1) {
    showToast("Import another macro for this character before deleting its last macro.", true);
    return;
  }

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
}));

$('#titlebar').addEventListener('mousedown', event => {
  if (!event.target.closest('button')) post('windowDrag');
});

$('#macroStateButton').addEventListener('click', () => {
  if (!state.macroRunning) {
    post('setMacroEnabled', { value: !state.macroEnabled });
  }
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
  $('#capturedKey').textContent = mappedKey;
  post('setHotkey', { target: captureTarget.target, value: mappedKey });
  endHotkeyCapture();
});
$('#addMacroButton').addEventListener('click', openMacroImport);
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
$('#cancelMacroEditButton').addEventListener('click', closeMacroEdit);
$('#macroEditForm').addEventListener('submit', submitMacroEdit);
$('#macroEditModal').addEventListener('mousedown', event => {
  if (event.target === $('#macroEditModal')) closeMacroEdit();
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

  if (event.key === 'Escape' && !$('#macroDeleteModal').classList.contains('hidden')) {
    closeMacroDelete();
    return;
  }

  if (event.key === 'Escape' && !$('#macroEditModal').classList.contains('hidden')) {
    closeMacroEdit();
    return;
  }

  if (event.key === 'Escape' && !$('#updatePromptModal').classList.contains('hidden')) {
    snoozeAvailableUpdate();
    return;
  }

  if (!captureTarget) return;
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

  $('#capturedKey').textContent = mappedKey;
  post('setHotkey', { target: captureTarget.target, value: mappedKey });
  endHotkeyCapture();
});

const savedTheme = localStorage.getItem(THEME_STORAGE_KEY);
const systemPrefersLight = window.matchMedia?.('(prefers-color-scheme: light)').matches;
applyTheme(savedTheme || (systemPrefersLight ? 'light' : 'dark'), false);

document.documentElement.lang = "en";
document.documentElement.dir = "ltr";
applyStaticTranslations();
loadBuildInfo();

bridge?.addEventListener('message', event => applyMessage(event.data));
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
