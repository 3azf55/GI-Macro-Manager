const bridge = window.chrome?.webview;

const communityLinks = {
  github: "https://github.com/3azf55/GI-Macro-Manager",
  discord: "https://discord.gg/H8HNhvqqm"
};

const releasesUrl = "https://github.com/3azf55/GI-Macro-Manager/releases";

const THEME_STORAGE_KEY = "umm-theme";

let buildInfo = {
  version: "—",
  buildDate: "—"
};

let updateState = {
  status: "idle",
  message: "Check GitHub for new releases.",
  currentVersion: "",
  latestVersion: "",
  releaseUrl: releasesUrl,
  canInstall: false,
  progress: null
};

let lastAnnouncedUpdate = "";

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
  hotkeyInfo: "Gameplay keys used by the macros cannot be assigned. Duplicate hotkeys are also rejected by the engine.",
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
  versionLabel: "Version",
  builtLabel: "Built",
  captureHotkey: "CAPTURE HOTKEY",
  pressKey: "Press a key",
  hotkeyModalHelp: "Press Escape to cancel. Mouse side buttons can still be configured from the legacy tray capture if needed.",
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
let macroImportCharacter = "";
let macroDeleteTarget = null;

const hotkeyCatalog = [
  { target: "Trigger", title: "Trigger", description: "Run the selected action", stateKey: "triggerKey" },
  { target: "ModeToggle", title: "Mode", description: "Switch application mode", stateKey: "modeToggleKey" },
  { target: "CharacterToggle", title: "Character", description: "Cycle through characters", stateKey: "characterToggleKey" },
  { target: "ComboToggle", title: "Combo", description: "Cycle the current character combos", stateKey: "comboToggleKey" }
];

let state = {
  connected: false,
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
  version: "—",
  isAdmin: false
};

let captureTarget = null;

const COMBO_LONG_PRESS_MS = 450;
const COMBO_PRESS_MOVE_TOLERANCE = 8;
let comboPressState = null;
let suppressComboClickUntil = 0;

const $ = selector => document.querySelector(selector);
const $$ = selector => [...document.querySelectorAll(selector)];

function post(action, payload = {}) {
  if (!bridge) {
    showToast(t("webviewUnavailable"), true);
    return;
  }
  bridge.postMessage({ action, ...payload });
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

function applyMessage(message) {
  if (message.type === "state") {
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
      connected: boolValue(message.connected),
      macroEnabled: boolValue(message.macroEnabled),
      soundsEnabled: boolValue(message.soundsEnabled),
      macroRunning: boolValue(message.macroRunning),
      autoLaunchEnabled: boolValue(message.autoLaunchEnabled),
      isAdmin: boolValue(message.isAdmin)
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
    } else if (message.status === "installed") {
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
    showToast(message.message || t("engineRejected"), true);
    post("requestState");
    return;
  }

  if (message.type === "notice") {
    // Each success event has a stable ID. It is shown once, even if the host
    // rereads bridge/error.txt or the interface is reopened immediately.
    if (shouldShowNotice(message)) {
      showToast(message.message || "Done");
    }
    post("requestState");
    return;
  }

  if (message.type === "connection") {
    state.connected = boolValue(message.connected);
    state.connectionStatus = message.status || (state.connected ? "connected" : "disconnected");
  }
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
  $("#soundToggle").checked = state.soundsEnabled;
  $("#soundTitle").textContent = state.soundsEnabled ? t("enabled") : t("muted");
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

function updateLocalComboOrder(character, orderedIds) {
  const characterEntry = characterCatalog[character];
  if (!characterEntry) return;

  const comboById = new Map(
    characterEntry.combos.map(combo => [combo.value, combo])
  );

  characterEntry.combos = orderedIds
    .map(comboId => comboById.get(comboId))
    .filter(Boolean);
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
      updateLocalComboOrder(press.character, newOrder);
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
      button.dataset.tooltip = combo.tooltip;
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

    button.style.setProperty("--combo-hold-duration", `${COMBO_LONG_PRESS_MS}ms`);
    button.innerHTML = `
      <strong class="preserve-ltr">${escapeHtml(presentation.label)}</strong>
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
  const canDelete = canManageSelected && !selectedCombo.builtIn;

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
    canDelete ? `Delete ${selectedCombo.label}` : "Delete selected macro"
  );

  $$(".combo-option").forEach(button => {
    const selected = button.dataset.comboValue === state.combo;
    button.classList.toggle("active", selected);
    button.disabled = state.macroRunning;
  });
}

function renderHotkeys() {
  const grid = $("#hotkeyGrid");
  grid.innerHTML = "";

  if (state.macroRunning && captureTarget) {
    endHotkeyCapture();
  }

  hotkeyCatalog.forEach(item => {
    const card = document.createElement("article");
    card.className = `hotkey-card${state.macroRunning ? " is-disabled" : ""}`;
    card.innerHTML = `
      <div class="hotkey-copy">
        <h3 class="hotkey-title">${item.title.toUpperCase()}</h3>
        <p class="hotkey-description">${item.description}</p>
      </div>
      <div class="hotkey-action">
        <div class="hotkey-value">${escapeHtml(state[item.stateKey] || "—")}</div>
        <button class="secondary-button" ${state.macroRunning ? "disabled" : ""}>Change</button>
      </div>`;

    const changeButton = card.querySelector("button");
    changeButton.title = state.macroRunning
      ? t("releaseBeforeHotkeys")
      : t("changeHotkeyTitle", { name: item.title });

    changeButton.addEventListener("click", () => beginHotkeyCapture(item));
    grid.appendChild(card);
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

  const hasProgress = Number.isFinite(updateState.progress) &&
    ["downloading", "installing"].includes(updateState.status);
  progressTrack.classList.toggle("hidden", !hasProgress);
  progressTrack.setAttribute("aria-hidden", hasProgress ? "false" : "true");
  progressBar.style.width = hasProgress
    ? `${Math.max(0, Math.min(100, updateState.progress))}%`
    : "0%";
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

  if (icon) icon.textContent = isDark ? "☾" : "☀";
  if (label) label.textContent = isDark ? "Dark mode" : "Light mode";
  if (hint) hint.textContent = isDark ? "Switch to light" : "Switch to dark";

  if (persist) localStorage.setItem(THEME_STORAGE_KEY, selectedTheme);
}

function toggleTheme() {
  const current = normalizeTheme(document.documentElement.dataset.theme);
  applyTheme(current === "dark" ? "light" : "dark");
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

function fillSelect(select, values, selectedValue = "") {
  select.innerHTML = "";
  values.forEach(value => {
    const option = document.createElement("option");
    option.value = value;
    option.textContent = value;
    option.selected = value === selectedValue;
    select.appendChild(option);
  });
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

  macroImportCharacter = state.character;
  $("#macroImportTitle").textContent = "Add macro";
  $("#macroImportCharacter").textContent = macroImportCharacter;
  $("#macroComboName").value = "";
  $("#macroTooltip").value = "";
  $("#macroTag").value = "";
  $("#macroImportModal").classList.remove("hidden");
  setTimeout(() => $("#macroComboName").focus(), 0);
}

function closeMacroImport() {
  $("#macroImportModal").classList.add("hidden");
  macroImportCharacter = "";
}

function submitMacroImport(event) {
  event.preventDefault();

  const character = macroImportCharacter;
  const comboName = $("#macroComboName").value.trim();
  const tooltip = $("#macroTooltip").value.trim();
  const tag = $("#macroTag").value;

  if (!character || !characterCatalog[character]) {
    showToast("The selected character is no longer available.", true);
    closeMacroImport();
    return;
  }
  if (!comboName) {
    showToast("Combo name is required.", true);
    return;
  }
  if (/[\r\n\t=|]/.test(comboName) || /[\r\n\t=|]/.test(tooltip)) {
    showToast("Names cannot contain tabs, line breaks, =, or |.", true);
    return;
  }

  closeMacroImport();
  post("importMacro", {
    character,
    comboName,
    tooltip,
    tag
  });
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
  const toast = document.createElement("div");
  toast.className = `toast${error ? " error" : ""}`;
  toast.textContent = message;
  $("#toastContainer").appendChild(toast);
  setTimeout(() => toast.remove(), 3600);
}

function escapeHtml(value) {
  return String(value).replace(/[&<>'"]/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" }[char]));
}

$$('.nav-item').forEach(button => button.addEventListener('click', () => {
  $$('.nav-item').forEach(item => item.classList.toggle('active', item === button));
  $$('.page').forEach(page => page.classList.toggle('active', page.dataset.pagePanel === button.dataset.page));
}));

$$('[data-window-action]').forEach(button => button.addEventListener('click', () => {
  if (button.dataset.windowAction === 'close') post('windowClose');
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
$('#cancelHotkeyButton').addEventListener('click', endHotkeyCapture);
$('#addMacroButton').addEventListener('click', openMacroImport);
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
$('#cancelMacroImportButton').addEventListener('click', closeMacroImport);
$('#macroImportForm').addEventListener('submit', submitMacroImport);
$('#macroImportModal').addEventListener('mousedown', event => {
  if (event.target === $('#macroImportModal')) closeMacroImport();
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

  if (event.key === 'Escape' && !$('#macroImportModal').classList.contains('hidden')) {
    closeMacroImport();
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
post('requestState');
render();
