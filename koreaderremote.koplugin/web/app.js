import { t, applyDocumentI18n, initI18n } from "./i18n.js";

const FAVORITES_KEY = "koreader.remote.hub.favorites";
const LAST_KEY = "koreader.remote.hub.last";
const PREFS_KEY = "koreader.remote.hub.prefs";
const BAR_TIP_KEY = "koreader.remote.hub.bottomBar.tipSeen";

/** Hosted same-origin by the plugin's HTTP server (not a public static site) */
const EMBEDDED_IN_PLUGIN = true;

const ACTIONS = [
  { id: "bookmarks", title: "Bookmarks", cap: "bookmarks" },
  { id: "toc", title: "Contents", cap: "toc" },
  { id: "footnotes", title: "Footnotes", cap: "footnotes" },
  { id: "pageJump", title: "Go to page", cap: "pageJump" },
  { id: "fullRefresh", title: "Full refresh", cap: "fullRefresh" },
  { id: "nightMode", title: "Night mode", cap: "nightMode" },
  { id: "keyboard", title: "Keyboard", cap: "remoteInput" },
  { id: "frontlight", title: "Frontlight", cap: "frontlight" },
];

const DEFAULT_PREFS = {
  pageTurnLayout: "vertical",
  barLayout: "single",
  visibleOrder: ACTIONS.map((a) => a.id),
  hiddenOrder: [],
  haptic: true,
  appearance: "system",
  ttsRate: 1,
  /** Page-boundary turn offset in seconds: negative = early, positive = late; default 1s early */
  ttsPageTurnOffsetSec: -1,
};

const ICONS = {
  bookmarks: `<svg viewBox="0 0 24 24" fill="currentColor"><path d="M6.5 3.75A1.75 1.75 0 0 0 4.75 5.5v14.1l6.5-3.25 6.5 3.25V5.5A1.75 1.75 0 0 0 16 3.75H6.5Z"/></svg>`,
  toc: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M5 7h14M5 12h14M5 17h10"/></svg>`,
  footnotes: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M7 7h10M7 12h7M7 17h5"/><path d="M17 15v4l2-1.2"/></svg>`,
  pageJump: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M8 7h3.5a2.5 2.5 0 0 1 0 5H8v5M15 17V7h4"/></svg>`,
  fullRefresh: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 1 1-2.6-6.3"/><polyline points="21 3 21 9 15 9"/></svg>`,
  nightMode: `<svg viewBox="0 0 24 24" fill="currentColor"><path d="M14.5 3.1A8.5 8.5 0 1 0 20.9 14a7 7 0 0 1-6.4-10.9Z"/></svg>`,
  dayMode: `<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 7.5a4.5 4.5 0 1 1 0 9 4.5 4.5 0 0 1 0-9Zm0-4.75a.75.75 0 0 1 .75.75v1.5a.75.75 0 0 1-1.5 0V3.5A.75.75 0 0 1 12 2.75Zm0 15a.75.75 0 0 1 .75.75v1.5a.75.75 0 0 1-1.5 0v-1.5a.75.75 0 0 1 .75-.75ZM3.5 11.25a.75.75 0 0 0 0 1.5h1.5a.75.75 0 0 0 0-1.5H3.5Zm15.5 0a.75.75 0 0 0 0 1.5h1.5a.75.75 0 0 0 0-1.5H19ZM5.4 5.4a.75.75 0 0 0 0 1.06l1.06 1.06a.75.75 0 1 0 1.06-1.06L6.46 5.4A.75.75 0 0 0 5.4 5.4Zm11.08 11.08a.75.75 0 0 0 0 1.06l1.06 1.06a.75.75 0 1 0 1.06-1.06l-1.06-1.06a.75.75 0 0 0-1.06 0Zm1.06-11.08a.75.75 0 0 0-1.06 0l-1.06 1.06a.75.75 0 1 0 1.06 1.06l1.06-1.06a.75.75 0 0 0 0-1.06ZM6.46 16.48a.75.75 0 0 0-1.06 0L4.34 17.54a.75.75 0 1 0 1.06 1.06l1.06-1.06a.75.75 0 0 0 0-1.06Z"/></svg>`,
  keyboard: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3" y="6" width="18" height="12" rx="2"/><path d="M7 10h.01M11 10h.01M15 10h.01M7 14h10"/></svg>`,
  frontlight: `<svg viewBox="0 0 24 24" fill="currentColor"><path d="M10.5 2.75a.75.75 0 0 1 1.5 0V4a.75.75 0 0 1-1.5 0V2.75ZM8.2 8.2a5.25 5.25 0 1 1 7.6 7.24c-.5.4-.8.98-.8 1.6v.21H9.5v-.21c0-.62-.3-1.2-.8-1.6A5.25 5.25 0 0 1 8.2 8.2Zm1.8 10.55h4.5a.75.75 0 0 1 0 1.5H10a.75.75 0 0 1 0-1.5Zm.75 2.5h3a.75.75 0 0 1 0 1.5h-3a.75.75 0 0 1 0-1.5Z"/></svg>`,
  book: `<svg viewBox="0 0 24 24" fill="currentColor"><path d="M4.75 5.5A2.75 2.75 0 0 1 7.5 2.75h10.25a.75.75 0 0 1 0 1.5H7.5a1.25 1.25 0 0 0 0 2.5h10.25a.75.75 0 0 1 .75.75v12.25a2.75 2.75 0 0 1-2.75 2.75H7.5A2.75 2.75 0 0 1 4.75 19.75V5.5Zm1.5 2.75V19.75c0 .69.56 1.25 1.25 1.25h8.25c.69 0 1.25-.56 1.25-1.25V8.25H6.25Z"/></svg>`,
  chevron: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 6 15 12 9 18"/></svg>`,
  up: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.75" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 15 12 9 18 15"/></svg>`,
  down: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.75" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9"/></svg>`,
  left: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.75" stroke-linecap="round" stroke-linejoin="round"><polyline points="15 6 9 12 15 18"/></svg>`,
  right: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.75" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 6 15 12 9 18"/></svg>`,
  play: `<svg viewBox="0 0 24 24" fill="currentColor"><path d="M8 5.5v13l11-6.5L8 5.5Z"/></svg>`,
  pause: `<svg viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="5" width="4" height="14" rx="1"/><rect x="14" y="5" width="4" height="14" rx="1"/></svg>`,
};

function loadJSON(key, fallback) {
  try {
    const raw = localStorage.getItem(key);
    return raw ? JSON.parse(raw) : fallback;
  } catch {
    return fallback;
  }
}

function saveJSON(key, value) {
  localStorage.setItem(key, JSON.stringify(value));
}

function escapeHTML(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function loadPrefs() {
  const prefs = { ...DEFAULT_PREFS, ...loadJSON(PREFS_KEY, {}) };
  if (!Array.isArray(prefs.visibleOrder) || !prefs.visibleOrder.length) {
    prefs.visibleOrder = [...DEFAULT_PREFS.visibleOrder];
  }
  if (!Array.isArray(prefs.hiddenOrder)) prefs.hiddenOrder = [];
  const offset = Number(prefs.ttsPageTurnOffsetSec);
  prefs.ttsPageTurnOffsetSec = Number.isFinite(offset)
    ? Math.min(3, Math.max(-3, offset))
    : DEFAULT_PREFS.ttsPageTurnOffsetSec;
  const rate = Number(prefs.ttsRate);
  prefs.ttsRate = Number.isFinite(rate)
    ? Math.min(3, Math.max(0.25, rate))
    : DEFAULT_PREFS.ttsRate;
  return prefs;
}

function ttsPageTurnOffsetSec() {
  const v = Number(state.prefs.ttsPageTurnOffsetSec);
  if (!Number.isFinite(v)) return DEFAULT_PREFS.ttsPageTurnOffsetSec;
  return Math.min(3, Math.max(-3, v));
}

function formatTurnOffsetLabel(sec) {
  const n = Number(sec);
  if (!Number.isFinite(n) || Math.abs(n) < 0.05) return t("On time");
  if (n < 0) return t("Early {sec}s", { sec: Math.abs(n).toFixed(1) });
  return t("Late {sec}s", { sec: n.toFixed(1) });
}

const state = {
  favorites: loadJSON(FAVORITES_KEY, []),
  current: null,
  capabilities: {},
  deviceState: {},
  pollTimer: null,
  turning: false,
  prefs: loadPrefs(),
  tts: {
    active: false,
    state: "idle", // idle | loading | speaking | paused | turningPage
    runID: 0,
    preview: "",
    statusText: t("Not started"),
    pageKey: null,
    contentHash: null,
    speechFp: null,
    sentenceQueue: [],
    nextConsumedPrefix: "",
    nextConsumedMeta: null,
    presetRemainder: null,
    pendingCrossTurn: null,
    crossPage: null, // { turnCount, completion, consumed, peekedPage, turnPromise, turnedPage }
    awaitingCrossPeek: false,
    ignoreEnd: false,
    speakToken: 0,
    pageSpeakGen: 0,
    advanceLock: false,
    utterance: null,
    autoAdvance: true,
    preload: null, // { anchorKey, promise, result }
    preloadTimer: null,
  },
  coverURL: null,
};

const els = {
  homeTopbar: document.getElementById("home-topbar"),
  btnManual: document.getElementById("btn-manual"),
  btnScan: document.getElementById("btn-scan"),
  btnGuide: document.getElementById("btn-guide"),
  favoritesList: document.getElementById("favorites-list"),
  favoritesEmpty: document.getElementById("favorites-empty"),
  thisDeviceList: document.getElementById("this-device-list"),
  viewHome: document.getElementById("view-home"),
  viewRemote: document.getElementById("view-remote"),
  btnBack: document.getElementById("btn-back"),
  btnDeviceInfo: document.getElementById("btn-device-info"),
  btnAppMenu: document.getElementById("btn-app-menu"),
  btnPrev: document.getElementById("btn-prev"),
  btnNext: document.getElementById("btn-next"),
  pagePad: document.getElementById("page-pad"),
  remoteTitle: document.getElementById("remote-title"),
  remoteSubtitle: document.getElementById("remote-subtitle"),
  remoteOnlineDot: document.getElementById("remote-online-dot"),
  remoteStatus: document.getElementById("remote-status"),
  remoteError: document.getElementById("remote-error"),
  bottomBar: document.getElementById("bottom-bar"),
  bottomBarTip: document.getElementById("bottom-bar-tip"),
  ttsPlay: document.getElementById("btn-tts-play"),
  ttsStop: document.getElementById("btn-tts-stop"),
  ttsSettings: document.getElementById("btn-tts-settings"),
  ttsTitle: document.getElementById("tts-title"),
  ttsSubtitle: document.getElementById("tts-subtitle"),
  ttsCoverImg: document.getElementById("tts-cover-img"),
  ttsCoverFallback: document.getElementById("tts-cover-fallback"),
  ttsPlayIcon: document.getElementById("tts-play-icon"),
  sheetRoot: document.getElementById("sheet-root"),
  sheetTitle: document.getElementById("sheet-title"),
  sheetBody: document.getElementById("sheet-body"),
  menuRoot: document.getElementById("menu-root"),
};

function savePrefs() {
  saveJSON(PREFS_KEY, state.prefs);
  applyAppearance();
}

function applyAppearance() {
  const mode = state.prefs.appearance || "system";
  if (mode === "system") document.documentElement.removeAttribute("data-theme");
  else document.documentElement.setAttribute("data-theme", mode);
}

function vibrateLight() {
  if (!state.prefs.haptic) return;
  try {
    navigator.vibrate?.(12);
  } catch {
    // ignore
  }
}

function deviceTitle(device) {
  return device.deviceName?.trim() || device.host;
}

function isFavorite(device) {
  return state.favorites.some((item) => item.id === device.id);
}

function upsertFavorite(device) {
  const next = state.favorites.filter((item) => item.id !== device.id);
  next.unshift(device);
  state.favorites = next;
  saveJSON(FAVORITES_KEY, state.favorites);
  renderLists();
}

function removeFavorite(device) {
  state.favorites = state.favorites.filter((item) => item.id !== device.id);
  saveJSON(FAVORITES_KEY, state.favorites);
  renderLists();
}

const DEFAULT_DEVICE_PORT = 43917;

/** Chromium Local Network Access / Private Network Access compatibility.
 * New LNA: RFC1918 → "local", loopback → "loopback"
 * Legacy PNA: RFC1918 → "private", loopback → "local"
 * Private IP literals may omit the field once access is granted.
 */
let preferredFetchMode = null; // "omit" | "private" | "local" | "loopback"

function withLocalNetworkFetchInit(init = {}, mode = preferredFetchMode) {
  const next = { ...init };
  if (!mode || mode === "omit") return next;
  next.targetAddressSpace = mode;
  return next;
}

function isLoopbackHost(host) {
  const h = String(host || "").toLowerCase();
  return h === "localhost" || h.startsWith("127.");
}

function fetchModesForHost(host) {
  if (isLoopbackHost(host)) return ["loopback", "local", "omit"];
  // Prefer omit: Safari / already-authorized LNA usually doesn't need targetAddressSpace for IP literals
  const modes = ["omit", "private", "local"];
  if (preferredFetchMode && !modes.includes(preferredFetchMode)) {
    modes.unshift(preferredFetchMode);
  } else if (preferredFetchMode) {
    return [preferredFetchMode, ...modes.filter((m) => m !== preferredFetchMode)];
  }
  return modes;
}

function describeFetchError(error, host, port) {
  const raw = error?.message || String(error || "Load failed");
  return t(
    "Could not connect to http://{host}:{port}/ ({message}). Check the port (plugin default {defaultPort}), make sure the reader is online, and allow this site to access the local network. You can verify by opening http://{host}:{port}/api/ping in a new tab first.",
    { host, port, message: raw, defaultPort: DEFAULT_DEVICE_PORT },
  );
}

/**
 * Retry LAN HTTP with omit / private / local modes to avoid address-space
 * or mixed-content false failures.
 */
async function localNetworkFetch(url, init = {}, hostHint = "") {
  let host = hostHint;
  try {
    host = host || new URL(url).hostname;
  } catch {
    /* ignore */
  }
  const modes = fetchModesForHost(host);
  let lastError = null;
  for (const mode of modes) {
    const controller = init.signal ? null : new AbortController();
    const signal = init.signal || controller.signal;
    const timer =
      controller &&
      window.setTimeout(() => controller.abort(), init.timeoutMs || 8000);
    try {
      const { timeoutMs, ...rest } = init;
      const response = await fetch(
        url,
        withLocalNetworkFetchInit(
          {
            cache: "no-store",
            ...rest,
            signal,
          },
          mode,
        ),
      );
      preferredFetchMode = mode;
      return response;
    } catch (error) {
      lastError = error;
      // 超时不一定是模式错误；其它模式再试
      if (error?.name === "AbortError" && init.signal) throw error;
    } finally {
      if (timer) window.clearTimeout(timer);
    }
  }
  throw lastError || new Error("Load failed");
}

async function calibrateLocalFetchMode(sampleHost, port = DEFAULT_DEVICE_PORT) {
  // Allows recalibrating the fetch mode when connecting to a new host.
  const host = String(sampleHost || "").trim();
  if (!host) {
    preferredFetchMode = preferredFetchMode || "omit";
    return preferredFetchMode;
  }
  const modes = fetchModesForHost(host);
  for (const mode of modes) {
    const controller = new AbortController();
    const started = performance.now();
    const timer = window.setTimeout(() => controller.abort(), 1200);
    try {
      await fetch(
        `http://${host}:${port}/api/ping`,
        withLocalNetworkFetchInit(
          {
            method: "GET",
            cache: "no-store",
            signal: controller.signal,
          },
          mode,
        ),
      );
      preferredFetchMode = mode;
      return mode;
    } catch (error) {
      const elapsed = performance.now() - started;
      if (error?.name === "AbortError" && elapsed >= 900) {
        preferredFetchMode = mode;
        return mode;
      }
    } finally {
      window.clearTimeout(timer);
    }
  }
  preferredFetchMode = "omit";
  return preferredFetchMode;
}

function servingDevice() {
  const host = String(location.hostname || "").trim();
  let port = Number(location.port);
  if (!port) {
    port = location.protocol === "https:" ? 443 : DEFAULT_DEVICE_PORT;
  }
  // file:// 等非 http 场景下无有效主机
  if (!host || host === "null") return null;
  return {
    id: `${host}:${port}`,
    host,
    port,
    deviceName: "",
    version: "",
    documentOpen: false,
    isServing: true,
  };
}

function isSameOriginDevice(device) {
  const self = servingDevice();
  if (!self || !device) return false;
  return (
    String(device.host) === String(self.host) &&
    Number(device.port) === Number(self.port)
  );
}

function directDeviceURL(device, apiPath, extraQuery = {}) {
  const path = apiPath.startsWith("/") ? apiPath : `/${apiPath}`;
  // 插件内嵌：对当前提供页面的设备用相对路径，彻底避开跨域/混合内容
  if (EMBEDDED_IN_PLUGIN && (!device || isSameOriginDevice(device))) {
    const url = new URL(path, location.origin);
    for (const [k, v] of Object.entries(extraQuery || {})) {
      if (v != null) url.searchParams.set(k, String(v));
    }
    return url.pathname + url.search;
  }
  const host = String(device?.host || "").trim();
  const port = Number(device?.port) || DEFAULT_DEVICE_PORT;
  const url = new URL(`http://${host}:${port}${path}`);
  for (const [k, v] of Object.entries(extraQuery || {})) {
    if (v != null) url.searchParams.set(k, String(v));
  }
  return url.toString();
}

async function parseDeviceResponse(response) {
  const text = await response.text();
  let data = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = { raw: text };
  }
  if (!response.ok || data?.ok === false) {
    throw new Error(data?.message || data?.error || `HTTP ${response.status}`);
  }
  return data;
}

async function deviceFetch(device, apiPath, options = {}) {
  const url = directDeviceURL(device, apiPath, options.query || {});
  const init = {
    method: options.method || "GET",
    headers: {
      Accept: options.accept || "application/json",
      ...(options.headers || {}),
    },
    body: options.body,
    cache: "no-store",
  };

  let response;
  if (EMBEDDED_IN_PLUGIN && isSameOriginDevice(device)) {
    response = await fetch(url, init);
  } else {
    try {
      response = await localNetworkFetch(url, init, device?.host);
    } catch (error) {
      throw new Error(describeFetchError(error, device?.host, device?.port));
    }
  }
  if (options.raw) return response;
  return parseDeviceResponse(response);
}


function capEnabled(capKey) {
  const c = state.capabilities || {};
  if (capKey === "frontlight") {
    return Boolean(c.frontlight || c.brightness || c.warmth);
  }
  if (capKey === "pageJump") return c.page_jump ?? c.pageJump ?? c.page_turn ?? true;
  if (capKey === "fullRefresh") return c.full_refresh ?? c.fullRefresh;
  if (capKey === "nightMode") return c.night_mode ?? c.nightMode;
  if (capKey === "remoteInput") return c.remote_input ?? c.remoteInput;
  if (capKey === "pageText") return c.page_text ?? c.pageText;
  if (capKey === "bookCover") return c.book_cover ?? c.bookCover;
  if (capKey === "tts") return (c.tts ?? false) || (c.page_text ?? c.pageText);
  return Boolean(c[capKey]);
}

function normalizeCaps(raw) {
  const c = raw || {};
  return {
    page_turn: c.page_turn ?? true,
    frontlight: c.frontlight ?? false,
    brightness: c.brightness ?? false,
    warmth: c.warmth ?? false,
    night_mode: c.night_mode ?? false,
    full_refresh: c.full_refresh ?? false,
    bookmarks: c.bookmarks ?? false,
    footnotes: c.footnotes ?? false,
    toc: c.toc ?? false,
    remote_input: c.remote_input ?? false,
    page_text: c.page_text ?? false,
    tts: c.tts ?? c.page_text ?? false,
    book_cover: c.book_cover ?? false,
    page_jump: c.page_jump ?? c.page_turn ?? true,
  };
}

function openSheet(title, html) {
  els.sheetTitle.textContent = title;
  els.sheetBody.innerHTML = html;
  els.sheetRoot.classList.remove("hidden");
  els.sheetRoot.setAttribute("aria-hidden", "false");
}

function closeSheet() {
  els.sheetRoot.classList.add("hidden");
  els.sheetRoot.setAttribute("aria-hidden", "true");
  els.sheetBody.innerHTML = "";
}

function openMenu() {
  const layoutLabel =
    state.prefs.pageTurnLayout === "vertical"
      ? t("Page turn layout: vertical")
      : t("Page turn layout: horizontal");
  els.menuRoot.querySelector('[data-menu="layout"]').textContent = layoutLabel;
  els.menuRoot.querySelector('[data-menu="edit-bar"]').textContent = t("Edit bottom bar");
  els.menuRoot.querySelector('[data-menu="haptic"]').textContent = state.prefs.haptic
    ? t("Page turn haptics: on")
    : t("Page turn haptics: off");
  const appearanceMap = { system: t("System"), light: t("Light"), dark: t("Dark") };
  els.menuRoot.querySelector('[data-menu="appearance"]').textContent = t("Appearance: {value}", {
    value: appearanceMap[state.prefs.appearance] || t("System"),
  });
  els.menuRoot.classList.remove("hidden");
}

function closeMenu() {
  els.menuRoot.classList.add("hidden");
}

function renderDeviceCard(device, { saved = false } = {}) {
  const card = document.createElement("button");
  card.type = "button";
  card.className = "device-card";
  const status = device.documentOpen
    ? device.bookTitle
      ? t("Reading · {title}", { title: device.bookTitle })
      : t("Reading")
    : device.version
      ? t("Online · v{version}", { version: device.version })
      : t("Online");
  card.innerHTML = `
    <div class="device-icon">${ICONS.book}</div>
    <div class="device-copy">
      <strong>${escapeHTML(deviceTitle(device))}</strong>
      <span class="meta">${escapeHTML(`${device.host}:${device.port}`)}</span>
      <span class="status${device.documentOpen ? " open" : ""}">${escapeHTML(status)}</span>
    </div>
    <div class="device-actions">
      <span class="star" title="${escapeHTML(saved ? t("Unsave") : t("Save"))}">${saved ? "★" : "☆"}</span>
      <span class="chevron">${ICONS.chevron}</span>
    </div>
  `;
  card.addEventListener("click", (event) => {
    if (event.target.closest(".star")) {
      event.preventDefault();
      event.stopPropagation();
      if (isFavorite(device)) removeFavorite(device);
      else upsertFavorite(device);
      return;
    }
    openRemote(device);
  });
  return card;
}

function renderLists() {
  els.favoritesList.innerHTML = "";
  if (els.thisDeviceList) {
    els.thisDeviceList.innerHTML = "";
    const self = state.serving || servingDevice();
    if (self) {
      els.thisDeviceList.appendChild(
        renderDeviceCard(
          {
            ...self,
            deviceName: self.deviceName || t("This reader"),
          },
          { saved: isFavorite(self) },
        ),
      );
    }
  }
  const otherFavorites = state.favorites.filter((d) => !isSameOriginDevice(d));
  if (!otherFavorites.length) els.favoritesEmpty.classList.remove("hidden");
  else {
    els.favoritesEmpty.classList.add("hidden");
    for (const device of otherFavorites) {
      els.favoritesList.appendChild(renderDeviceCard(device, { saved: true }));
    }
  }
}

let refreshingDevices = false;

/** Lightweight refresh: re-ping the current device and saved favorites, no LAN scanning. */
async function refreshDevices() {
  if (refreshingDevices) return;
  refreshingDevices = true;
  els.btnScan.disabled = true;
  els.btnScan.classList.add("spinning");
  try {
    const self = servingDevice();
    if (self) {
      try {
        const ping = await deviceFetch(self, "/api/ping");
        state.serving = enrichFromPing(self, ping);
      } catch (error) {
        console.warn("refreshDevices: serving device ping failed", error);
      }
    }

    await Promise.all(
      (state.favorites || []).map(async (device) => {
        try {
          const ping = await deviceFetch(device, "/api/ping");
          Object.assign(device, enrichFromPing(device, ping));
        } catch (error) {
          console.warn("refreshDevices: favorite ping failed", device.id, error);
        }
      }),
    );
    saveJSON(FAVORITES_KEY, state.favorites);
    renderLists();
  } finally {
    refreshingDevices = false;
    els.btnScan.disabled = false;
    els.btnScan.classList.remove("spinning");
  }
}

function showManualAdd() {
  openSheet(
    t("Add manually"),
    `
    <form id="manual-form" class="manual-form" style="grid-template-columns:1fr">
      <label><span>${escapeHTML(t("IP / hostname"))}</span><input id="manual-host" required placeholder="192.168.1.42" /></label>
      <label><span>${escapeHTML(t("Port"))}</span><input id="manual-port" type="number" value="43917" min="1" max="65535" required /></label>
      <button class="btn btn-primary" type="submit">${escapeHTML(t("Detect & connect"))}</button>
    </form>
    <p class="hint">${escapeHTML(
      t(
        "Connects directly from your browser. Enter the reader's local IP (see \"Show QR code\" in the plugin), make sure your phone and reader are on the same Wi-Fi, and allow this site to access the local network.",
      ),
    )}</p>
  `
  );
  document.getElementById("manual-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    const host = document.getElementById("manual-host").value.trim();
    const port = Number(document.getElementById("manual-port").value || 43917);
    const device = {
      id: `${host}:${port}`,
      host,
      port,
      deviceName: "",
      version: "",
      documentOpen: false,
    };
    try {
      // Lightweight, user-gesture-triggered probe to warm up the Local Network Access mode.
      await calibrateLocalFetchMode(host, port).catch(() => {});
      const ping = await deviceFetch(device, "/api/ping");
      const found = enrichFromPing(device, ping);
      upsertFavorite(found);
      closeSheet();
      openRemote(found);
    } catch (error) {
      alert(t("Could not connect: {message}", { message: error.message }));
    }
  });
}

function showGuide() {
  openSheet(
    t("How to use"),
    `
    <div class="field">
      <strong>${escapeHTML(t("1. Start the remote server"))}</strong>
      <p class="hint">${escapeHTML(
        t("In KOReader: Tools → KOReader Remote → Start remote server. You can also enable Auto start."),
      )}</p>
    </div>
    <div class="field">
      <strong>${escapeHTML(t("2. Open this page on your phone"))}</strong>
      <p class="hint">${escapeHTML(
        t(
          "On the same Wi-Fi/hotspot as the reader, open the address from the plugin's QR code (like http://reader-ip:port/) in your phone's browser. This page is served directly by the plugin, so the connection is same-origin and needs no public site.",
        ),
      )}</p>
    </div>
    <div class="field">
      <strong>${escapeHTML(t("3. Start controlling"))}</strong>
      <p class="hint">${escapeHTML(
        t('Tap "This reader" to start. To connect to another reader on the network, add it manually with "+".'),
      )}</p>
    </div>
    <a class="btn btn-primary" style="display:block;text-align:center;text-decoration:none" href="https://github.com/helitra/koreader-remote/releases/latest" target="_blank" rel="noopener">${escapeHTML(
      t("Open plugin download page"),
    )}</a>
  `
  );
}

function enrichFromPing(device, ping) {
  const found = {
    ...device,
    port: Number(ping.port) || device.port,
    deviceName: ping.device_name || device.deviceName || "",
    version: ping.version || "",
    documentOpen: Boolean(ping.document_open),
    bookTitle: ping.book_title || "",
    page: ping.page || ping.page_key || "",
  };
  found.id = `${found.host}:${found.port}`;
  return found;
}

function showHome() {
  stopPolling();
  stopTTS(false);
  revokeCover();
  state.current = null;
  els.homeTopbar.classList.remove("hidden");
  els.viewHome.classList.remove("hidden");
  els.viewRemote.classList.add("hidden");
}

async function openRemote(device) {
  upsertFavorite(device);
  saveJSON(LAST_KEY, device.id);
  state.current = device;
  state.capabilities = {};
  state.deviceState = {};
  els.homeTopbar.classList.add("hidden");
  els.viewHome.classList.add("hidden");
  els.viewRemote.classList.remove("hidden");
  els.remoteTitle.textContent = deviceTitle(device);
  els.remoteSubtitle.textContent = t("Connecting…");
  els.remoteOnlineDot.className = "online-dot";
  els.remoteError.classList.add("hidden");
  els.remoteStatus.textContent = t("Connected, ready to turn pages");
  updatePageLayout();
  renderBottomBar();
  updateTTSChrome();
  scheduleBarTip();
  await refreshRemoteStatus();
  loadCover();
  startPolling();
}

function startPolling() {
  stopPolling();
  state.pollTimer = window.setInterval(() => {
    refreshRemoteStatus().catch(() => {});
  }, 4000);
}

function stopPolling() {
  if (state.pollTimer) {
    window.clearInterval(state.pollTimer);
    state.pollTimer = null;
  }
}

async function refreshRemoteStatus() {
  const device = state.current;
  if (!device) return;
  try {
    const [ping, capsRes, stateRes] = await Promise.all([
      deviceFetch(device, "/api/ping"),
      deviceFetch(device, "/api/v1/capabilities").catch(() => null),
      deviceFetch(device, "/api/v1/device-state").catch(() => null),
    ]);
    Object.assign(device, enrichFromPing(device, ping));
    if (capsRes?.capabilities) state.capabilities = normalizeCaps(capsRes.capabilities);
    if (stateRes?.state) {
      state.deviceState = stateRes.state;
      if (stateRes.state.capabilities) {
        state.capabilities = normalizeCaps({
          ...state.capabilities,
          ...stateRes.state.capabilities,
        });
      }
    }
    els.remoteTitle.textContent = deviceTitle(device);
    if (device.documentOpen && device.bookTitle) {
      els.remoteSubtitle.textContent = t("Online · {title}", { title: device.bookTitle });
    } else if (device.documentOpen) {
      els.remoteSubtitle.textContent = t("Online · Reading");
    } else {
      els.remoteSubtitle.textContent = t("Online · tap for details");
    }
    els.remoteOnlineDot.className = "online-dot on";
    els.remoteError.classList.add("hidden");
    setRemoteEnabled(true);
    renderBottomBar();
    updateTTSChrome();
    const pageKey = ping.page_key || ping.page || device.page || null;
    // TTS 自动朗读中不要靠轮询抢同步，否则 page_key 格式差异会整页重开、首词念两遍
    // 手动翻页仍走 turnPage → syncAfterManualPageTurn
    if (!state.tts.active) {
      syncTTSIfReadingPositionChanged(pageKey, ping.page || null).catch(() => {});
    } else if (device.page) {
      // 仅更新展示用页码，不触发重读
      state.current.page = device.page;
    }
  } catch (error) {
    els.remoteOnlineDot.className = "online-dot off";
    els.remoteSubtitle.textContent = t("Offline");
    els.remoteError.textContent = error.message || t("Reader not responding");
    els.remoteError.classList.remove("hidden");
    els.remoteStatus.textContent = error.message || t("Reader not responding");
    setRemoteEnabled(false);
  }
}

function setRemoteEnabled(enabled) {
  els.btnPrev.disabled = !enabled;
  els.btnNext.disabled = !enabled;
}

function updatePageLayout() {
  const horizontal = state.prefs.pageTurnLayout === "horizontal";
  els.pagePad.classList.toggle("layout-horizontal", horizontal);
  els.pagePad.classList.toggle("layout-vertical", !horizontal);
  const prevIcon = els.btnPrev.querySelector(".page-btn-icon");
  const nextIcon = els.btnNext.querySelector(".page-btn-icon");
  prevIcon.innerHTML = horizontal ? ICONS.left : ICONS.up;
  nextIcon.innerHTML = horizontal ? ICONS.right : ICONS.down;
}

function actionAvailable(id) {
  const meta = ACTIONS.find((a) => a.id === id);
  if (!meta) return false;
  return capEnabled(meta.cap);
}

function renderBottomBar() {
  const visible = state.prefs.visibleOrder.filter((id) => id !== "tts");
  if (!visible.length) {
    els.bottomBar.className = "bottom-bar glass-card glass-elevated";
    els.bottomBar.innerHTML = `<p class="muted" style="margin:8px;text-align:center">${escapeHTML(
      t('The bottom bar is empty. Open "Edit bottom bar" from the menu.'),
    )}</p>`;
    return;
  }

  const makeBtn = (id) => {
    const meta = ACTIONS.find((a) => a.id === id);
    if (!meta) return "";
    let title = t(meta.title);
    let icon = ICONS[id] || ICONS.bookmarks;
    const enabled = actionAvailable(id);
    if (id === "nightMode") {
      const night = Boolean(state.deviceState.night_mode);
      title = night ? t("Day mode") : t("Night mode");
      icon = night ? ICONS.dayMode : ICONS.nightMode;
    }
    if (id === "frontlight") {
      const on = Boolean(state.deviceState.frontlight_on);
      if (capEnabled("brightness") || state.capabilities.brightness) {
        const value = Math.round(Number(state.deviceState.brightness) || 0);
        title = on ? `${value}%` : t("Frontlight");
      } else {
        title = on ? t("On") : t("Off");
      }
    }
    return `
      <button class="quick-btn" type="button" data-action="${id}" ${enabled ? "" : "disabled"}>
        <span class="well">${icon}</span>
        <span>${escapeHTML(title)}</span>
      </button>
    `;
  };

  if (state.prefs.barLayout === "double") {
    const mid = Math.ceil(visible.length / 2);
    const top = visible.slice(0, mid).map(makeBtn).join("");
    const bottom = visible.slice(mid).map(makeBtn).join("");
    els.bottomBar.className = "bottom-bar double glass-card glass-elevated";
    els.bottomBar.innerHTML = `<div class="bottom-bar-row">${top}</div>${
      bottom ? `<div class="bottom-bar-row">${bottom}</div>` : ""
    }`;
  } else {
    els.bottomBar.className = "bottom-bar glass-card glass-elevated";
    els.bottomBar.innerHTML = visible.map(makeBtn).join("");
  }

  for (const btn of els.bottomBar.querySelectorAll("[data-action]")) {
    let longPressTimer = null;
    let longPressed = false;
    btn.addEventListener("click", (event) => {
      if (longPressed) {
        event.preventDefault();
        longPressed = false;
        return;
      }
      handleAction(btn.dataset.action);
    });
    btn.addEventListener("pointerdown", () => {
      longPressed = false;
      longPressTimer = window.setTimeout(() => {
        longPressed = true;
        longPressTimer = null;
        showBarEditor();
        dismissBarTip(true);
      }, 450);
    });
    const clear = () => {
      if (longPressTimer) window.clearTimeout(longPressTimer);
      longPressTimer = null;
    };
    btn.addEventListener("pointerup", clear);
    btn.addEventListener("pointerleave", clear);
    btn.addEventListener("pointercancel", clear);
  }
}

function scheduleBarTip() {
  if (localStorage.getItem(BAR_TIP_KEY) === "1") return;
  if (!state.prefs.visibleOrder.length) return;
  els.bottomBarTip.classList.remove("hidden");
  window.setTimeout(() => dismissBarTip(true), 4500);
}

function dismissBarTip(markSeen) {
  els.bottomBarTip.classList.add("hidden");
  if (markSeen) localStorage.setItem(BAR_TIP_KEY, "1");
}

async function handleAction(id) {
  const device = state.current;
  if (!device) return;
  try {
    switch (id) {
      case "bookmarks":
        await showBookmarks();
        break;
      case "toc":
        await showTOC();
        break;
      case "footnotes":
        await showFootnotes();
        break;
      case "pageJump":
        await showPageJump();
        break;
      case "fullRefresh":
        await deviceFetch(device, "/api/v1/full-refresh", { method: "POST" });
        els.remoteStatus.textContent = t("Full refresh done");
        break;
      case "nightMode":
        await deviceFetch(device, "/api/v1/night-mode/toggle", { method: "POST" });
        await refreshRemoteStatus();
        break;
      case "frontlight":
        await showFrontlight();
        break;
      case "keyboard":
        await showKeyboard();
        break;
      default:
        break;
    }
  } catch (error) {
    els.remoteStatus.textContent = error.message || t("Action failed");
  }
}

async function showBookmarks() {
  const data = await deviceFetch(state.current, "/api/v1/bookmarks");
  const items = data.book?.items || [];
  if (!items.length) {
    openSheet(t("Bookmarks"), `<p class="empty">${escapeHTML(t("No bookmarks, highlights, or notes yet"))}</p>`);
    return;
  }
  openSheet(
    t("Bookmarks"),
    `
    <div class="sheet-actions" style="margin-bottom:12px">
      <button class="btn btn-secondary" type="button" id="bm-return">${escapeHTML(t("Return to reading position"))}</button>
    </div>
    ${items
      .map((item) => {
        const type =
          item.type === "note" ? t("Note") : item.type === "highlight" ? t("Highlight") : t("Bookmark");
        return `
        <button class="list-item" type="button" data-bm="${escapeHTML(item.id)}">
          <div>
            <strong>${escapeHTML(item.chapter || item.page || type)}</strong>
            <div class="meta">${escapeHTML(type)}${item.page ? ` · ${escapeHTML(item.page)}` : ""}</div>
            ${item.excerpt ? `<div class="excerpt">${escapeHTML(item.excerpt)}</div>` : ""}
            ${item.note ? `<div class="excerpt">${escapeHTML(item.note)}</div>` : ""}
          </div>
        </button>`;
      })
      .join("")}
  `
  );
  document.getElementById("bm-return")?.addEventListener("click", async () => {
    await deviceFetch(state.current, "/api/v1/bookmarks/return", { method: "POST" });
    closeSheet();
    refreshRemoteStatus();
  });
  for (const btn of els.sheetBody.querySelectorAll("[data-bm]")) {
    btn.addEventListener("click", async () => {
      await deviceFetch(state.current, "/api/v1/bookmarks/open", {
        method: "POST",
        query: { id: btn.dataset.bm },
      });
      closeSheet();
      refreshRemoteStatus();
    });
  }
}

async function showTOC() {
  const data = await deviceFetch(state.current, "/api/v1/toc");
  const items = data.toc?.items || [];
  if (!items.length) {
    openSheet(t("Contents"), `<p class="empty">${escapeHTML(t("No table of contents"))}</p>`);
    return;
  }
  openSheet(
    t("Contents"),
    `
    <div class="sheet-actions" style="margin-bottom:12px">
      <button class="btn btn-secondary" type="button" id="toc-return">${escapeHTML(t("Return to reading position"))}</button>
    </div>
    ${items
      .map((item) => {
        const depth = Math.min(3, Number(item.depth) || 0);
        return `
        <button class="list-item${item.current ? " current" : ""}" type="button" data-toc="${escapeHTML(item.id)}">
          <div class="depth-${depth}">
            <strong>${escapeHTML(item.title || t("Chapter"))}</strong>
            <div class="meta">${item.page ? escapeHTML(String(item.page)) : ""}${item.current ? ` · ${escapeHTML(t("Current"))}` : ""}</div>
          </div>
        </button>`;
      })
      .join("")}
  `
  );
  document.getElementById("toc-return")?.addEventListener("click", async () => {
    await deviceFetch(state.current, "/api/v1/toc/return", { method: "POST" });
    closeSheet();
    refreshRemoteStatus();
  });
  for (const btn of els.sheetBody.querySelectorAll("[data-toc]")) {
    btn.addEventListener("click", async () => {
      await deviceFetch(state.current, "/api/v1/toc/open", {
        method: "POST",
        query: { id: btn.dataset.toc },
      });
      closeSheet();
      refreshRemoteStatus();
    });
  }
}

async function showFootnotes() {
  const data = await deviceFetch(state.current, "/api/v1/footnotes");
  const items = data.footnotes || [];
  openSheet(
    t("Footnotes"),
    `
    <div class="sheet-actions" style="margin-bottom:12px">
      <button class="btn btn-secondary" type="button" id="fn-close">${escapeHTML(t("Close footnote popup"))}</button>
    </div>
    ${
      items.length
        ? items
            .map(
              (item) => `
      <button class="list-item" type="button" data-fn="${item.id}">
        <div>
          <strong>${escapeHTML(item.marker || `[${item.id}]`)}</strong>
          <div class="excerpt">${escapeHTML(item.preview || "")}</div>
        </div>
      </button>`
            )
            .join("")
        : `<p class="empty">${escapeHTML(t("No footnotes on this page"))}</p>`
    }
  `
  );
  document.getElementById("fn-close")?.addEventListener("click", async () => {
    await deviceFetch(state.current, "/api/v1/footnote/close", { method: "POST" });
    closeSheet();
  });
  for (const btn of els.sheetBody.querySelectorAll("[data-fn]")) {
    btn.addEventListener("click", async () => {
      await deviceFetch(state.current, "/api/v1/footnote/open", {
        method: "POST",
        query: { id: btn.dataset.fn },
      });
    });
  }
}

async function showPageJump() {
  const data = await deviceFetch(state.current, "/api/v1/page-jump");
  const jump = data.jump || {};
  const current = jump.current_page ?? jump.current ?? "";
  const total = jump.total_pages ?? jump.total ?? "";
  const currentLabel = total
    ? t("Current {current} / {total}", { current, total })
    : t("Current {current}", { current });
  openSheet(
    t("Go to page"),
    `
    <p class="hint">${escapeHTML(currentLabel)}</p>
    <div class="field">
      <label>${escapeHTML(t("Jump to page"))}</label>
      <input id="jump-page" type="number" min="1" ${total ? `max="${Number(total)}"` : ""} value="${escapeHTML(String(current || 1))}" />
    </div>
    <button class="btn btn-primary" type="button" id="jump-go" style="width:100%">${escapeHTML(t("Go"))}</button>
  `
  );
  document.getElementById("jump-go").addEventListener("click", async () => {
    const page = Number(document.getElementById("jump-page").value);
    if (!page) return;
    await deviceFetch(state.current, "/api/v1/page-jump", {
      method: "POST",
      query: { page },
    });
    closeSheet();
    await refreshRemoteStatus();
    await syncAfterManualPageTurn();
  });
}

async function showFrontlight() {
  const s = state.deviceState;
  const canBright = Boolean(state.capabilities.brightness);
  const canWarm = Boolean(state.capabilities.warmth);
  openSheet(
    t("Frontlight"),
    `
    <div class="sheet-actions">
      <button class="btn btn-secondary" type="button" id="fl-toggle">${escapeHTML(t("Toggle"))}</button>
      <button class="btn btn-primary" type="button" id="fl-on">${escapeHTML(t("Turn on"))}</button>
      <button class="btn btn-secondary" type="button" id="fl-off">${escapeHTML(t("Turn off"))}</button>
    </div>
    ${
      canBright
        ? `<div class="slider-row"><label><span>${escapeHTML(t("Brightness"))}</span><span id="br-val">${Math.round(s.brightness || 0)}</span></label>
           <input id="fl-brightness" type="range" min="0" max="100" value="${Math.round(s.brightness || 0)}" /></div>`
        : ""
    }
    ${
      canWarm
        ? `<div class="slider-row"><label><span>${escapeHTML(t("Warmth"))}</span><span id="wm-val">${Math.round(s.warmth || 0)}</span></label>
           <input id="fl-warmth" type="range" min="0" max="100" value="${Math.round(s.warmth || 0)}" /></div>`
        : ""
    }
  `
  );
  const post = async (path, query) => {
    await deviceFetch(state.current, path, { method: "POST", query });
    await refreshRemoteStatus();
  };
  document.getElementById("fl-toggle").onclick = () => post("/api/v1/frontlight/toggle");
  document.getElementById("fl-on").onclick = () =>
    post("/api/v1/frontlight", { enabled: "true" });
  document.getElementById("fl-off").onclick = () =>
    post("/api/v1/frontlight", { enabled: "false" });
  const br = document.getElementById("fl-brightness");
  if (br) {
    br.addEventListener("input", () => {
      document.getElementById("br-val").textContent = br.value;
    });
    br.addEventListener("change", () => post("/api/v1/brightness", { value: br.value }));
  }
  const wm = document.getElementById("fl-warmth");
  if (wm) {
    wm.addEventListener("input", () => {
      document.getElementById("wm-val").textContent = wm.value;
    });
    wm.addEventListener("change", () => post("/api/v1/warmth", { value: wm.value }));
  }
}

async function showKeyboard() {
  let status = { text: "", available: false, editable: false };
  try {
    const data = await deviceFetch(state.current, "/api/v1/input");
    status = data.input || status;
  } catch {
    // ignore
  }
  openSheet(
    t("Keyboard input"),
    `
    <p class="hint">${escapeHTML(
      status.available
        ? status.editable
          ? t("The reader currently has an editable input field")
          : t("An input field was detected, but it may not be editable")
        : t("No active input field detected; you can still try sending text"),
    )}</p>
    <div class="field">
      <label>${escapeHTML(t("Text"))}</label>
      <textarea id="kb-text">${escapeHTML(status.text || "")}</textarea>
    </div>
    <div class="sheet-actions">
      <button class="btn btn-primary" type="button" id="kb-send">${escapeHTML(t("Send to reader"))}</button>
    </div>
  `
  );
  document.getElementById("kb-send").onclick = async () => {
    const text = document.getElementById("kb-text").value;
    const encoded = btoa(unescape(encodeURIComponent(text)));
    await deviceFetch(state.current, "/api/v1/input/push", {
      method: "POST",
      query: { mode: "replace" },
      headers: {
        "X-KOReader-Input-Base64": encoded,
        "X-KOReader-Input-Mode": "replace",
      },
    });
    els.remoteStatus.textContent = t("Text sent");
    closeSheet();
  };
}

function showDeviceInfo() {
  const d = state.current;
  const s = state.deviceState;
  openSheet(
    t("Device info"),
    `
    <div class="settings-row"><div class="label">${escapeHTML(t("Name"))}</div><div class="value">${escapeHTML(deviceTitle(d))}</div></div>
    <div class="settings-row"><div class="label">${escapeHTML(t("Address"))}</div><div class="value">${escapeHTML(`${d.host}:${d.port}`)}</div></div>
    <div class="settings-row"><div class="label">${escapeHTML(t("Version"))}</div><div class="value">${escapeHTML(d.version || "—")}</div></div>
    <div class="settings-row"><div class="label">${escapeHTML(t("Book"))}</div><div class="value">${escapeHTML(d.bookTitle || "—")}</div></div>
    <div class="settings-row"><div class="label">${escapeHTML(t("Page"))}</div><div class="value">${escapeHTML(String(d.page || "—"))}</div></div>
    <div class="settings-row"><div class="label">${escapeHTML(t("Night mode"))}</div><div class="value">${s.night_mode ? escapeHTML(t("On")) : escapeHTML(t("Off"))}</div></div>
    <div class="settings-row"><div class="label">${escapeHTML(t("Frontlight"))}</div><div class="value">${s.frontlight_on ? escapeHTML(t("On")) : escapeHTML(t("Off"))}</div></div>
  `
  );
}

function showBarEditor() {
  closeMenu();
  const visible = state.prefs.visibleOrder;
  const hidden = state.prefs.hiddenOrder;
  openSheet(
    t("Edit bottom bar"),
    `
    <div class="chip-row">
      <button type="button" class="chip ${state.prefs.barLayout === "single" ? "active" : ""}" data-bar-layout="single">${escapeHTML(t("Single row"))}</button>
      <button type="button" class="chip ${state.prefs.barLayout === "double" ? "active" : ""}" data-bar-layout="double">${escapeHTML(t("Double row"))}</button>
    </div>
    <p class="hint">${escapeHTML(t("Visible"))}</p>
    <div id="bar-visible">
      ${visible
        .map((id) => {
          const meta = ACTIONS.find((a) => a.id === id);
          if (!meta) return "";
          return `<div class="bar-editor-item" data-id="${id}"><span>${escapeHTML(t(meta.title))}</span>
            <button type="button" data-hide="${id}">${escapeHTML(t("Hide"))}</button>
            <button type="button" data-up="${id}">${escapeHTML(t("Move up"))}</button>
            <button type="button" data-down="${id}">${escapeHTML(t("Move down"))}</button></div>`;
        })
        .join("")}
    </div>
    <p class="hint">${escapeHTML(t("Hidden"))}</p>
    <div id="bar-hidden">
      ${
        hidden.length
          ? hidden
              .map((id) => {
                const meta = ACTIONS.find((a) => a.id === id);
                if (!meta) return "";
                return `<div class="bar-editor-item" data-id="${id}"><span>${escapeHTML(t(meta.title))}</span>
                  <button type="button" data-show="${id}">${escapeHTML(t("Show"))}</button></div>`;
              })
              .join("")
          : `<p class="empty">${escapeHTML(t("None"))}</p>`
      }
    </div>
  `
  );
  const move = (id, delta) => {
    const list = [...state.prefs.visibleOrder];
    const i = list.indexOf(id);
    const j = i + delta;
    if (i < 0 || j < 0 || j >= list.length) return;
    [list[i], list[j]] = [list[j], list[i]];
    state.prefs.visibleOrder = list;
    savePrefs();
    showBarEditor();
    renderBottomBar();
  };
  for (const btn of els.sheetBody.querySelectorAll("[data-bar-layout]")) {
    btn.onclick = () => {
      state.prefs.barLayout = btn.dataset.barLayout;
      savePrefs();
      showBarEditor();
      renderBottomBar();
    };
  }
  for (const btn of els.sheetBody.querySelectorAll("[data-hide]")) {
    btn.onclick = () => {
      const id = btn.dataset.hide;
      state.prefs.visibleOrder = state.prefs.visibleOrder.filter((x) => x !== id);
      if (!state.prefs.hiddenOrder.includes(id)) state.prefs.hiddenOrder.push(id);
      savePrefs();
      showBarEditor();
      renderBottomBar();
    };
  }
  for (const btn of els.sheetBody.querySelectorAll("[data-show]")) {
    btn.onclick = () => {
      const id = btn.dataset.show;
      state.prefs.hiddenOrder = state.prefs.hiddenOrder.filter((x) => x !== id);
      if (!state.prefs.visibleOrder.includes(id)) state.prefs.visibleOrder.push(id);
      savePrefs();
      showBarEditor();
      renderBottomBar();
    };
  }
  for (const btn of els.sheetBody.querySelectorAll("[data-up]")) {
    btn.onclick = () => move(btn.dataset.up, -1);
  }
  for (const btn of els.sheetBody.querySelectorAll("[data-down]")) {
    btn.onclick = () => move(btn.dataset.down, 1);
  }
}

function revokeCover() {
  if (state.coverURL) {
    URL.revokeObjectURL(state.coverURL);
    state.coverURL = null;
  }
  els.ttsCoverImg.classList.add("hidden");
  els.ttsCoverFallback.classList.remove("hidden");
  els.ttsCoverImg.removeAttribute("src");
}

async function loadCover() {
  revokeCover();
  if (!state.current || !capEnabled("bookCover")) return;
  try {
    const response = await deviceFetch(state.current, "/api/v1/book-cover", {
      raw: true,
      accept: "*/*",
    });
    if (!response.ok) return;
    const blob = await response.blob();
    if (!blob.size) return;
    state.coverURL = URL.createObjectURL(blob);
    els.ttsCoverImg.src = state.coverURL;
    els.ttsCoverImg.classList.remove("hidden");
    els.ttsCoverFallback.classList.add("hidden");
  } catch {
    // ignore
  }
}

function updateTTSChrome() {
  const available = capEnabled("tts") || capEnabled("pageText");
  const tts = state.tts;
  const speakingLike = tts.state === "speaking";
  els.ttsPlay.disabled = !available;
  els.ttsSettings.disabled = !available;
  const title = state.current?.bookTitle?.trim();
  els.ttsTitle.textContent = title || (tts.active ? t("Speaking") : t("Read aloud"));
  if (!available) {
    els.ttsSubtitle.textContent = t("This document doesn't support read-aloud");
  } else if (!tts.active) {
    els.ttsSubtitle.textContent = t("Tap to start reading this page aloud");
  } else if (tts.state === "turningPage" || tts.state === "loading") {
    els.ttsSubtitle.textContent = tts.statusText || t("Syncing…");
  } else if (tts.preview) {
    els.ttsSubtitle.textContent = tts.preview;
  } else {
    els.ttsSubtitle.textContent = tts.statusText || t("Reading aloud");
  }
  els.ttsPlayIcon.innerHTML = speakingLike ? ICONS.pause : ICONS.play;
  els.ttsStop.classList.toggle("hidden", !tts.active);
  if (tts.active && tts.statusText) {
    els.remoteStatus.textContent = tts.statusText;
  }
}

const MAX_AUTO_SKIP = 12;
const BOUNDARY = new Set(["。", "！", "？", "；", "…", ".", "!", "?", ";"]);
const TRAILING_CLOSERS = new Set(['"', "'", "”", "’", "」", "』", "）", ")", "】", "》"]);

function stripFootnoteMarkers(value) {
  return String(value)
    .replace(/[\[［〔【]\s*\d{1,3}\s*[\]］〕】]/g, "")
    .replace(/[\u00B9\u00B2\u00B3\u2070\u2074-\u2079]+/g, "");
}

function normalizeForSpeech(value) {
  let text = String(value || "")
    .replace(/\u00a0/g, " ")
    .replace(/[\u00ad\u200b\u200c\u200d]/g, "")
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n");
  text = stripFootnoteMarkers(text);
  const chinese = /[\u3400-\u9FFF]/.test(text);
  if (chinese) {
    text = text.replace(/\n{2,}/g, "。").replace(/\n/g, "，");
    text = text.replace(/，{2,}/g, "，").replace(/。{2,}/g, "。");
  } else {
    text = text.replace(/\n{2,}/g, ". ").replace(/\n/g, ", ");
    text = text.replace(/,{2,}/g, ",");
  }
  return text.replace(/[ \t]{2,}/g, " ").trim();
}

function textForSpeech(page) {
  const raw = page?.speech_text?.trim() ? page.speech_text : page?.text || "";
  return normalizeForSpeech(raw);
}

function pageFingerprint(page) {
  if (page?.content_hash) return page.content_hash;
  return speechFingerprint(textForSpeech(page));
}

function speechFingerprint(text) {
  const trimmed = String(text || "").trim();
  if (!trimmed) return "empty";
  let hash = 0;
  for (let i = 0; i < trimmed.length; i += 1) {
    hash = (hash * 31 + trimmed.charCodeAt(i)) | 0;
  }
  return `s${hash}_${trimmed.length}`;
}

function endsWithSentenceBoundary(text) {
  const trimmed = String(text || "").trim();
  if (!trimmed) return true;
  for (let i = trimmed.length - 1; i >= 0; i -= 1) {
    const ch = trimmed[i];
    if (/\s/.test(ch)) continue;
    if (TRAILING_CLOSERS.has(ch)) continue;
    return BOUNDARY.has(ch);
  }
  return false;
}

function splitSentences(text) {
  const trimmed = String(text || "").trim();
  if (!trimmed) return [];
  const result = [];
  let current = "";
  const chars = Array.from(trimmed);
  let i = 0;
  while (i < chars.length) {
    const ch = chars[i];
    current += ch;
    if (BOUNDARY.has(ch)) {
      let j = i + 1;
      while (j < chars.length && TRAILING_CLOSERS.has(chars[j])) {
        current += chars[j];
        j += 1;
      }
      const sentence = current.trim();
      if (sentence) result.push(sentence);
      current = "";
      i = j;
      continue;
    }
    i += 1;
  }
  const tail = current.trim();
  if (tail) result.push(tail);
  return result;
}

function takeSentenceCompletion(nextPageText) {
  const trimmed = String(nextPageText || "").trim();
  if (!trimmed) return { segment: "", consumed: "" };
  let buffer = "";
  const chars = Array.from(trimmed);
  let i = 0;
  while (i < chars.length) {
    buffer += chars[i];
    if (BOUNDARY.has(chars[i])) {
      let j = i + 1;
      while (j < chars.length && TRAILING_CLOSERS.has(chars[j])) {
        buffer += chars[j];
        j += 1;
      }
      const raw = chars.slice(0, j).join("");
      return { segment: raw, consumed: raw };
    }
    i += 1;
  }
  return { segment: trimmed, consumed: trimmed };
}

/**
 * 拼接跨页句，并去掉页末/页首重叠字符。
 * 例如页末「你是我的」+ 页首「的父亲。」→「你是我的父亲。」（只保留一个「的」）
 */
function joinCrossPageSentence(onPageTail, completion) {
  const tail = String(onPageTail || "");
  const comp = String(completion || "");
  if (!comp) {
    return { fullText: tail, boundaryIndex: tail.length, overlap: 0 };
  }
  const tChars = Array.from(tail);
  const cChars = Array.from(comp);
  let overlap = 0;
  const max = Math.min(tChars.length, cChars.length);
  for (let n = max; n >= 1; n -= 1) {
    let matched = true;
    for (let i = 0; i < n; i += 1) {
      if (tChars[tChars.length - n + i] !== cChars[i]) {
        matched = false;
        break;
      }
    }
    if (matched) {
      overlap = n;
      break;
    }
  }
  const fullText = tail + cChars.slice(overlap).join("");
  return {
    fullText,
    // SpeechSynthesis charIndex 按 UTF-16，与 String.length 一致
    boundaryIndex: tail.length,
    overlap,
  };
}

/** 剥离跨页已朗读前缀；兼容 consumed / completion 及轻微空白差异 */
function stripSpokenCrossPagePrefix(text, { consumed, completion } = {}) {
  let result = String(text || "");
  const candidates = [consumed, completion]
    .filter(Boolean)
    .flatMap((p) => [p, p.trim()])
    .filter(Boolean);
  candidates.sort((a, b) => b.length - a.length);
  for (const prefix of candidates) {
    if (result.startsWith(prefix)) {
      return result.slice(prefix.length).trim();
    }
    const trimmed = result.trimStart();
    if (trimmed.startsWith(prefix)) {
      return trimmed.slice(prefix.length).trim();
    }
  }

  // 逐字匹配 completion，避免归一化后仍残留首词
  const completionText = String(completion || consumed || "").trim();
  if (completionText) {
    const trimmed = result.trimStart();
    const tChars = Array.from(trimmed);
    const cChars = Array.from(completionText);
    let i = 0;
    while (i < cChars.length && i < tChars.length && tChars[i] === cChars[i]) {
      i += 1;
    }
    if (i === cChars.length) {
      return tChars.slice(i).join("").trim();
    }
  }
  return result.trim();
}

function stripConsumedPrefix(text, consumed) {
  return stripSpokenCrossPagePrefix(text, { consumed });
}

function readingPositionChanged(prevKey, prevHash, prevSpeech, page) {
  const nextKey = page?.page_key || page?.page || null;
  const nextHash = pageFingerprint(page);
  const nextSpeech = speechFingerprint(textForSpeech(page));
  if (prevKey && nextKey && prevKey !== nextKey) return true;
  if (prevHash && prevHash !== nextHash) return true;
  if (prevSpeech && prevSpeech !== nextSpeech) return true;
  return false;
}

function sleep(ms) {
  return new Promise((resolve) => window.setTimeout(resolve, ms));
}

function ttsNewRun() {
  state.tts.runID += 1;
  return state.tts.runID;
}

function ttsIsCurrent(runID) {
  return state.tts.active && state.tts.runID === runID;
}

function stopSpeakingSilently() {
  // 递增 token，使已 cancel 的 utterance.onend/onerror 全部失效
  state.tts.speakToken += 1;
  state.tts.ignoreEnd = true;
  state.tts.utterance = null;
  clearCrossPageTurnTimer();
  try {
    window.speechSynthesis?.cancel();
  } catch {
    // ignore
  }
}

function stopTTS(update = true) {
  state.tts.active = false;
  state.tts.state = "idle";
  state.tts.statusText = t("Not started");
  state.tts.preview = "";
  state.tts.sentenceQueue = [];
  state.tts.nextConsumedPrefix = "";
  state.tts.nextConsumedMeta = null;
  state.tts.presetRemainder = null;
  state.tts.pendingCrossTurn = null;
  state.tts.crossPage = null;
  state.tts.awaitingCrossPeek = false;
  state.tts.advanceLock = false;
  state.tts.pageKey = null;
  state.tts.contentHash = null;
  state.tts.speechFp = null;
  invalidatePeekPreload();
  ttsNewRun();
  stopSpeakingSilently();
  if (update) updateTTSChrome();
}

function invalidatePeekPreload() {
  if (state.tts.preloadTimer) {
    window.clearTimeout(state.tts.preloadTimer);
    state.tts.preloadTimer = null;
  }
  state.tts.preload = null;
}

function schedulePeekPreload(runID) {
  if (!state.tts.autoAdvance || !ttsIsCurrent(runID)) return;
  if (!capEnabled("pageText") && !state.capabilities.page_text_peek) {
    // 仍尝试 peek；不支持时会静默失败
  }
  invalidatePeekPreload();
  const anchorKey = state.tts.pageKey;
  const textLen = state.tts.sentenceQueue.reduce((n, s) => n + s.length, 0);
  let delayMs = 200;
  if (textLen >= 600) delayMs = 800;
  else if (textLen >= 240) delayMs = 450;
  else if (textLen >= 80) delayMs = 280;

  const preload = { anchorKey, promise: null, result: null };
  state.tts.preload = preload;
  state.tts.preloadTimer = window.setTimeout(() => {
    if (!ttsIsCurrent(runID) || state.tts.preload !== preload) return;
    preload.promise = peekNextPageText().then((response) => {
      if (!ttsIsCurrent(runID) || state.tts.preload !== preload) return null;
      if (!response || response.end_of_book === true || !response.page) {
        preload.result = { kind: "end" };
      } else {
        preload.result = {
          kind: "ready",
          page: response.page,
          turnCount: Math.max(1, Number(response.turn_count) || 1),
        };
      }
      return preload.result;
    }).catch(() => null);
  }, delayMs);
}

async function takePeekPreload(anchorKey) {
  const preload = state.tts.preload;
  if (!preload || preload.anchorKey !== anchorKey) return null;
  if (preload.result) {
    const value = preload.result;
    state.tts.preload = null;
    return value;
  }
  if (preload.promise) {
    const value = await preload.promise;
    if (state.tts.preload === preload) state.tts.preload = null;
    return value;
  }
  // 预取尚未启动：立刻 peek 一次
  if (state.tts.preloadTimer) {
    window.clearTimeout(state.tts.preloadTimer);
    state.tts.preloadTimer = null;
  }
  const response = await peekNextPageText();
  state.tts.preload = null;
  if (!response || response.end_of_book === true || !response.page) {
    return { kind: "end" };
  }
  return {
    kind: "ready",
    page: response.page,
    turnCount: Math.max(1, Number(response.turn_count) || 1),
  };
}

async function loadPageText() {
  const data = await deviceFetch(state.current, "/api/v1/page-text");
  return data.page || {};
}

async function waitForPageChange(prevKey, prevHash, prevSpeech, { initialMs = 0, attemptMs = 60, attempts = 10 } = {}) {
  if (initialMs > 0) await sleep(initialMs);
  let last = null;
  for (let i = 0; i < attempts; i += 1) {
    if (i > 0) await sleep(attemptMs);
    const page = await loadPageText();
    last = page;
    if (readingPositionChanged(prevKey, prevHash, prevSpeech, page)) return page;
  }
  if (last) return last;
  throw new Error(t("Could not get new page text after turning the page"));
}

async function turnPageForTTS(delta, anchor) {
  const steps = Math.max(1, Math.abs(Number(delta) || 1));
  const signed = delta < 0 ? -steps : steps;
  try {
    const query = { delta: signed, include_text: "true" };
    const response = await fetch(
      directDeviceURL(state.current, "/api/v1/page-turn", query),
      withLocalNetworkFetchInit({ method: "GET", headers: { Accept: "application/json" } }),
    );
    if (response.status === 404) {
      throw Object.assign(new Error("page-turn unsupported"), { status: 404 });
    }
    const data = await response.json().catch(() => ({}));
    if (!response.ok || data.ok === false) {
      throw new Error(data.page_error || data.message || data.error || `HTTP ${response.status}`);
    }
    if (data.page) return data.page;
    return await waitForPageChange(anchor.key, anchor.hash, anchor.speech, {
      initialMs: 0,
      attemptMs: 50,
      attempts: 8,
    });
  } catch (error) {
    if (error.status !== 404 && !String(error.message || "").includes("unsupported")) {
      // fall through
    }
    const path = signed >= 0 ? "/api/next" : "/api/previous";
    for (let i = 0; i < steps; i += 1) {
      await deviceFetch(state.current, path);
    }
    return waitForPageChange(anchor.key, anchor.hash, anchor.speech, {
      initialMs: 0,
      attemptMs: 50,
      attempts: 8,
    });
  }
}

async function peekNextPageText() {
  try {
    return await deviceFetch(state.current, "/api/v1/page-text/peek", {
      query: { max_skip: MAX_AUTO_SKIP },
    });
  } catch {
    return null;
  }
}

async function fetchNextSpeakablePage(runID, anchor, updateStatus) {
  let key = anchor.key;
  let hash = anchor.hash;
  let speech = anchor.speech;

  for (let skip = 0; skip < MAX_AUTO_SKIP; skip += 1) {
    if (!ttsIsCurrent(runID)) throw new Error("cancelled");
    if (updateStatus) {
      state.tts.state = "turningPage";
      state.tts.statusText = skip === 0 ? t("Syncing page turn…") : t("Skipping blank page…");
      updateTTSChrome();
    }

    const page = await turnPageForTTS(1, { key, hash, speech });
    if (!ttsIsCurrent(runID)) throw new Error("cancelled");

    if (!readingPositionChanged(key, hash, speech, page)) {
      if (skip === 0) {
        await deviceFetch(state.current, "/api/next");
        const retry = await waitForPageChange(key, hash, speech, {
          initialMs: 0,
          attemptMs: 50,
          attempts: 8,
        });
        if (readingPositionChanged(key, hash, speech, retry)) {
          const speechText = textForSpeech(retry);
          if (speechText) return { kind: "ready", page: retry };
          key = retry.page_key || retry.page || key;
          hash = pageFingerprint(retry);
          speech = speechFingerprint(speechText);
          continue;
        }
      }
      return { kind: "end" };
    }

    const speechText = textForSpeech(page);
    if (speechText) return { kind: "ready", page };

    key = page.page_key || page.page || key;
    hash = pageFingerprint(page);
    speech = speechFingerprint(speechText);
  }
  throw new Error(t("No text found after {count} pages, stopped", { count: MAX_AUTO_SKIP }));
}

function currentTTSAnchor() {
  return {
    key: state.tts.pageKey,
    hash: state.tts.contentHash,
    speech: state.tts.speechFp,
  };
}

function adoptPageAnchor(page) {
  state.tts.pageKey = page.page_key || page.page || null;
  state.tts.contentHash = pageFingerprint(page);
  state.tts.speechFp = speechFingerprint(textForSpeech(page));
  if (state.current) {
    state.current.page = page.page || page.page_key || state.current.page;
    if (page.title) state.current.bookTitle = page.title;
  }
}

function estimateSpeechUnits(text) {
  if (!text) {
    return { chinese: 0, latin: 0, digits: 0, punct: 0, other: 0, chars: 0, secAtRate1: 0 };
  }
  let chinese = 0;
  let latin = 0;
  let digits = 0;
  let punct = 0;
  let other = 0;
  for (const ch of text) {
    if (/[\u3400-\u9FFF]/.test(ch)) chinese += 1;
    else if (/[A-Za-z]/.test(ch)) latin += 1;
    else if (/\d/.test(ch)) digits += 1;
    else if (/[\s\u3000]/.test(ch)) continue;
    else if (BOUNDARY.has(ch) || TRAILING_CLOSERS.has(ch) || /[，、：:；;]/.test(ch)) punct += 1;
    else other += 1;
  }
  // rate=1 时经验语速（字/秒）
  const secAtRate1 =
    chinese / 4.4 + latin / 13.5 + digits / 9 + punct / 8 + other / 10;
  const chars = chinese + latin + digits + punct + other;
  return { chinese, latin, digits, punct, other, chars, secAtRate1 };
}

/** 系统 TTS 倍速非线性：略缓于线性，避免高速估太短、低速估太长 */
function effectiveSpeechRate(rate) {
  const r = Math.min(3, Math.max(0.25, Number(rate) || 1));
  return 0.85 * r + 0.15;
}

function estimateSpeechDurationSec(text, rate = 1) {
  const units = estimateSpeechUnits(text);
  return units.secAtRate1 / effectiveSpeechRate(rate);
}

/**
 * 根据页内尾巴计算翻页触发点。
 * offset<0：换算为提前字符数（charIndex 主触发）；offset>0：页界后再延后墙钟秒。
 */
function computeCrossPageTurnTiming(onPageTail, boundaryIndex, rate) {
  const r = Math.min(3, Math.max(0.25, Number(rate) || 1));
  const units = estimateSpeechUnits(onPageTail);
  const boundarySec = units.secAtRate1 / effectiveSpeechRate(r);
  const offsetSec = ttsPageTurnOffsetSec();
  const expectedCps =
    boundarySec > 0.05 ? units.chars / boundarySec : units.chars > 0 ? units.chars / 0.05 : 4.4;

  // 提前量随语速缩放，且不超过页尾时长的 45%
  let leadSec = 0;
  let delayAfterBoundarySec = 0;
  if (offsetSec < 0) {
    leadSec = Math.max(offsetSec / r, -0.45 * Math.max(boundarySec, 0.01));
  } else if (offsetSec > 0) {
    delayAfterBoundarySec = Math.min(3, offsetSec);
  }

  const leadChars =
    leadSec < 0 ? Math.max(0, Math.round((-leadSec) * expectedCps)) : 0;
  const triggerCharIndex = Math.max(0, (boundaryIndex || 0) - leadChars);
  const turnAtSec = Math.max(0, boundarySec + leadSec);

  return {
    boundarySec,
    offsetSec,
    leadSec,
    delayAfterBoundarySec,
    expectedCps,
    leadChars,
    triggerCharIndex,
    turnAtSec,
    boundaryChars: units.chars,
  };
}

async function beginSpeakingPage(page, runID, { skipCrossPeek = false, schedulePreload = true } = {}) {
  if (!ttsIsCurrent(runID)) return;
  const gen = (state.tts.pageSpeakGen += 1);
  invalidatePeekPreload();
  adoptPageAnchor(page);
  state.tts.suppressPositionSyncUntil = Date.now() + 5000;
  state.tts.state = "loading";
  state.tts.statusText = t("Preparing sentences…");
  state.tts.pendingCrossTurn = null;
  state.tts.crossPage = null;
  updateTTSChrome();

  const consumedMeta = state.tts.nextConsumedMeta;
  const consumed = state.tts.nextConsumedPrefix;
  const presetRemainder = state.tts.presetRemainder;
  state.tts.nextConsumedPrefix = "";
  state.tts.nextConsumedMeta = null;
  state.tts.presetRemainder = null;

  let text;
  if (typeof presetRemainder === "string") {
    // 跨页补全后余下文本已算好，禁止再剥一次或重新 peek
    text = presetRemainder.trim();
  } else {
    text = stripSpokenCrossPagePrefix(textForSpeech(page), {
      consumed,
      completion: consumedMeta?.completion,
    }).trim();
  }

  if (gen !== state.tts.pageSpeakGen || !ttsIsCurrent(runID)) return;

  if (!text) {
    state.tts.preview = "";
    state.tts.sentenceQueue = [];
    state.tts.awaitingCrossPeek = false;
    if (state.tts.autoAdvance) {
      state.tts.statusText = t("No text on this page, turning the page…");
      updateTTSChrome();
      await advanceAfterPageSpeech(runID);
    } else {
      stopTTS();
      els.remoteStatus.textContent = t("No readable text on this page");
    }
    return;
  }

  let sentences = splitSentences(text);
  if (!sentences.length) sentences = [text];

  // 余下文本（presetRemainder）若仍未完句，也必须 peek 合并，否则翻页后会把补全再念一遍
  const incomplete =
    state.tts.autoAdvance &&
    !skipCrossPeek &&
    !endsWithSentenceBoundary(sentences[sentences.length - 1]);

  const attachCrossPage = (onPageTail, peek) => {
    const nextSpeech = textForSpeech(peek?.page || {});
    if (!peek || peek.end_of_book === true || !nextSpeech) return null;
    const completion = takeSentenceCompletion(nextSpeech);
    if (!completion.segment) return null;
    const joined = joinCrossPageSentence(onPageTail, completion.segment);
    const rate = Math.min(3, Math.max(0.25, Number(state.prefs.ttsRate) || 1));
    const timing = computeCrossPageTurnTiming(onPageTail, joined.boundaryIndex, rate);
    let remainder = "";
    if (nextSpeech.startsWith(completion.consumed)) {
      remainder = nextSpeech.slice(completion.consumed.length).trim();
    } else {
      remainder = stripSpokenCrossPagePrefix(nextSpeech, {
        consumed: completion.consumed,
        completion: completion.segment,
      }).trim();
    }
    state.tts.crossPage = {
      turnCount: Math.max(1, Number(peek.turn_count) || 1),
      onPageTail,
      completion: completion.segment,
      consumed: completion.consumed,
      remainderAfterCompletion: remainder,
      // 整句一次读完，避免「你是我」+「的父亲」在句界把「的」念两遍
      fullText: joined.fullText,
      boundaryIndex: joined.boundaryIndex,
      overlap: joined.overlap,
      rate,
      ...timing,
      observedCps: null,
      boundarySamples: 0,
      peekedPage: peek.page,
      turnPromise: null,
      turnedPage: null,
      turnFired: false,
      turnTimer: null,
      phase: "merged",
    };
    return state.tts.crossPage;
  };

  if (incomplete && sentences.length > 1) {
    const ready = sentences.slice(0, -1);
    const tail = sentences[sentences.length - 1];
    state.tts.awaitingCrossPeek = true;
    startSpeakingSentences(ready, page, runID, { schedulePreload: false });
    peekNextPageText()
      .then((peek) => {
        if (!ttsIsCurrent(runID) || gen !== state.tts.pageSpeakGen) return;
        state.tts.awaitingCrossPeek = false;
        const cp = attachCrossPage(tail, peek);
        state.tts.sentenceQueue.push(cp ? cp.fullText : tail);
        if (!state.tts.utterance && !window.speechSynthesis?.speaking) {
          speakNextSentence(runID);
        }
      })
      .catch(() => {
        if (!ttsIsCurrent(runID) || gen !== state.tts.pageSpeakGen) return;
        state.tts.awaitingCrossPeek = false;
        state.tts.sentenceQueue.push(tail);
        if (!state.tts.utterance && !window.speechSynthesis?.speaking) {
          speakNextSentence(runID);
        }
      });
    return;
  }

  if (incomplete && sentences.length === 1) {
    const peek = await peekNextPageText();
    if (ttsIsCurrent(runID) && gen === state.tts.pageSpeakGen) {
      const cp = attachCrossPage(sentences[0], peek);
      if (cp) sentences = [cp.fullText];
    }
  }

  if (!ttsIsCurrent(runID) || gen !== state.tts.pageSpeakGen) return;
  state.tts.awaitingCrossPeek = false;
  startSpeakingSentences(sentences, page, runID, { schedulePreload });
}

function clearCrossPageTurnTimer() {
  const cp = state.tts.crossPage;
  if (cp?.turnTimer) {
    window.clearTimeout(cp.turnTimer);
    cp.turnTimer = null;
  }
}

function startCrossPageTurn(runID, reason = "timer") {
  const cp = state.tts.crossPage;
  if (!cp || !ttsIsCurrent(runID)) return cp?.turnPromise;
  if (cp.turnFired) return cp.turnPromise;
  cp.turnFired = true;
  clearCrossPageTurnTimer();
  const anchor = currentTTSAnchor();
  cp.turnReason = reason;
  cp.turnPromise = turnPageForTTS(cp.turnCount, anchor)
    .then((page) => {
      cp.turnedPage = page;
      if (page) adoptPageAnchor(page);
      return page;
    })
    .catch((error) => {
      cp.turnError = error;
      throw error;
    });
  return cp.turnPromise;
}

function armCrossPageTurnSchedule(runID) {
  const cp = state.tts.crossPage;
  if (!cp || !ttsIsCurrent(runID) || cp.phase !== "merged") return null;

  const rate = Math.min(3, Math.max(0.25, Number(state.prefs.ttsRate) || 1));
  const timing = computeCrossPageTurnTiming(cp.onPageTail, cp.boundaryIndex, rate);
  Object.assign(cp, timing, {
    rate,
    boundaryReached: false,
    observedCps: null,
    boundarySamples: 0,
  });

  const scheduleFallbackTimer = (delaySec, reason = "timer") => {
    clearCrossPageTurnTimer();
    const delayMs = Math.max(0, Math.round(delaySec * 1000));
    cp.turnTimer = window.setTimeout(() => {
      startCrossPageTurn(runID, reason);
    }, delayMs);
  };

  // 兜底：开读时用估时；收到 boundary 校准后会重排
  scheduleFallbackTimer(cp.turnAtSec, "timer");

  state.tts.statusText = t("Cross-page sentence · page turn: {offset}", {
    offset: formatTurnOffsetLabel(cp.offsetSec),
  });
  updateTTSChrome();

  return (event) => {
    if (cp.turnFired) return;

    const charIndex = Math.max(0, Number(event.charIndex) || 0);
    const elapsed =
      typeof event.elapsedTime === "number" && event.elapsedTime > 0
        ? event.elapsedTime
        : null;

    // 在线校准语速，重排兜底定时器
    if (elapsed != null && charIndex > 0) {
      const cps = charIndex / Math.max(elapsed, 0.05);
      if (Number.isFinite(cps) && cps > 0.5) {
        cp.boundarySamples = (cp.boundarySamples || 0) + 1;
        cp.observedCps =
          cp.observedCps == null ? cps : cp.observedCps * 0.6 + cps * 0.4;
        if (cp.boundarySamples >= 2 && !cp.boundaryReached) {
          const remainChars = Math.max(0, cp.triggerCharIndex - charIndex);
          const remainSec = remainChars / Math.max(cp.observedCps, 0.5);
          scheduleFallbackTimer(remainSec, "timer-recalibrated");
        }
      }
    }

    const triggerAt = Number.isFinite(cp.triggerCharIndex)
      ? cp.triggerCharIndex
      : cp.boundaryIndex;

    // 提前 / 准时：以 charIndex 为主
    if (cp.delayAfterBoundarySec > 0) {
      if (charIndex < cp.boundaryIndex) return;
      if (cp.boundaryReached) return;
      cp.boundaryReached = true;
      scheduleFallbackTimer(cp.delayAfterBoundarySec, "boundary-delay");
      return;
    }

    if (charIndex >= triggerAt) {
      startCrossPageTurn(runID, "boundary");
    }
  };
}

function startSpeakingSentences(sentences, page, runID, { schedulePreload = true } = {}) {
  if (!ttsIsCurrent(runID)) return;
  state.tts.speechFp = speechFingerprint(textForSpeech(page));
  state.tts.preview = (page.text || sentences.join("")).slice(0, 120);
  state.tts.statusText = page.page
    ? t("Reading aloud · page {page}", { page: page.page })
    : t("Reading aloud");
  if (state.tts.crossPage) {
    state.tts.crossPage.pageLabel = page.page || page.page_key || "";
  }
  state.tts.sentenceQueue = [...sentences];
  state.tts.state = "speaking";
  const synth = window.speechSynthesis;
  if (state.tts.utterance || synth?.speaking || synth?.pending) {
    stopSpeakingSilently();
  }
  updateTTSChrome();
  speakNextSentence(runID);
  if (schedulePreload && !state.tts.crossPage) schedulePeekPreload(runID);
}

function speakUtterance(text, runID, { onEnd, crossPageMerged = false } = {}) {
  const utterance = new SpeechSynthesisUtterance(text);
  utterance.rate = Math.min(3, Math.max(0.25, Number(state.prefs.ttsRate) || 1));
  utterance.lang = /[\u3400-\u9FFF]/.test(text) ? "zh-CN" : "en-US";
  const token = state.tts.speakToken + 1;
  state.tts.speakToken = token;
  state.tts.ignoreEnd = false;
  state.tts.utterance = utterance;
  state.tts.state = "speaking";
  state.tts.preview = text.slice(0, 48);
  updateTTSChrome();

  const onBoundary = crossPageMerged ? armCrossPageTurnSchedule(runID) : null;
  if (onBoundary) {
    utterance.onboundary = (event) => {
      if (state.tts.speakToken !== token || state.tts.ignoreEnd) return;
      onBoundary({
        charIndex: event.charIndex || 0,
        charLength: event.charLength,
        elapsedTime: event.elapsedTime,
      });
    };
  }

  utterance.onend = () => {
    if (state.tts.speakToken !== token) return;
    if (state.tts.ignoreEnd) return;
    if (state.tts.utterance !== utterance) return;
    state.tts.utterance = null;
    clearCrossPageTurnTimer();
    if (!ttsIsCurrent(runID)) return;
    onEnd?.();
  };
  utterance.onerror = (event) => {
    if (state.tts.speakToken !== token) return;
    if (state.tts.ignoreEnd) return;
    if (state.tts.utterance !== utterance) return;
    state.tts.utterance = null;
    clearCrossPageTurnTimer();
    if (event?.error === "interrupted" || event?.error === "canceled") return;
    if (ttsIsCurrent(runID)) {
      state.tts.statusText = t("Read aloud interrupted");
      stopTTS();
    }
  };

  try {
    window.speechSynthesis.speak(utterance);
  } catch (error) {
    els.remoteStatus.textContent = error.message || t("Read aloud failed");
    stopTTS();
  }
}

function speakNextSentence(runID) {
  if (!ttsIsCurrent(runID)) return;
  if (!state.tts.sentenceQueue.length) {
    if (state.tts.awaitingCrossPeek) return;
    handlePageSpeechFinished(runID);
    return;
  }

  const sentence = state.tts.sentenceQueue.shift();
  const cp = state.tts.crossPage;
  const isCrossMerged =
    Boolean(cp) &&
    cp.phase === "merged" &&
    state.tts.sentenceQueue.length === 0 &&
    sentence === cp.fullText;

  if (!isCrossMerged && !state.tts.sentenceQueue.length && state.tts.autoAdvance && !cp) {
    const preload = state.tts.preload;
    if (preload && !preload.promise && !preload.result) {
      if (state.tts.preloadTimer) {
        window.clearTimeout(state.tts.preloadTimer);
        state.tts.preloadTimer = null;
      }
      preload.promise = peekNextPageText()
        .then((response) => {
          if (!ttsIsCurrent(runID) || state.tts.preload !== preload) return null;
          if (!response || response.end_of_book === true || !response.page) {
            preload.result = { kind: "end" };
          } else {
            preload.result = {
              kind: "ready",
              page: response.page,
              turnCount: Math.max(1, Number(response.turn_count) || 1),
            };
          }
          return preload.result;
        })
        .catch(() => null);
    }
  }

  speakUtterance(sentence, runID, {
    crossPageMerged: isCrossMerged,
    onEnd: () => {
      if (isCrossMerged) {
        finishCrossPageMerged(runID);
        return;
      }
      if (state.tts.sentenceQueue.length || state.tts.awaitingCrossPeek) {
        speakNextSentence(runID);
        return;
      }
      handlePageSpeechFinished(runID);
    },
  });
}

async function finishCrossPageMerged(runID) {
  if (!ttsIsCurrent(runID)) return;
  const cp = state.tts.crossPage;
  if (!cp) {
    await advanceAfterPageSpeech(runID);
    return;
  }
  if (!cp.turnFired) {
    startCrossPageTurn(runID, "merged-end");
  }
  await continueAfterCrossPageCompletion(runID);
}

async function continueAfterCrossPageCompletion(runID) {
  if (!ttsIsCurrent(runID)) return;
  const cp = state.tts.crossPage;
  if (!cp) {
    await advanceAfterPageSpeech(runID);
    return;
  }

  try {
    let page = cp.turnedPage;
    if (!page && cp.turnPromise) {
      state.tts.statusText = t("Syncing page turn…");
      updateTTSChrome();
      try {
        page = await cp.turnPromise;
      } catch {
        page = null;
      }
    }
    if (!page) {
      state.tts.statusText = t("Syncing page turn…");
      updateTTSChrome();
      page = await turnPageForTTS(cp.turnCount, currentTTSAnchor());
    }
    if (!ttsIsCurrent(runID)) return;

    const remainder = cp.remainderAfterCompletion || "";
    const target = page || cp.peekedPage;
    state.tts.crossPage = null;
    state.tts.nextConsumedPrefix = "";
    state.tts.nextConsumedMeta = null;

    // 用 peek 时算好的余下文本继续；允许再跨页合并（余下部分末句未完时）
    state.tts.presetRemainder = remainder;
    await beginSpeakingPage(target, runID, {
      skipCrossPeek: false,
      schedulePreload: true,
    });
  } catch (error) {
    if (ttsIsCurrent(runID)) {
      els.remoteStatus.textContent = error.message || t("Page turn failed");
      stopTTS();
    }
  }
}

async function handlePageSpeechFinished(runID) {
  if (!ttsIsCurrent(runID)) return;

  if (state.tts.crossPage) {
    if (state.tts.crossPage.phase === "merged") {
      await finishCrossPageMerged(runID);
    } else {
      await continueAfterCrossPageCompletion(runID);
    }
    return;
  }

  const pending = state.tts.pendingCrossTurn;
  state.tts.pendingCrossTurn = null;
  if (pending) {
    state.tts.state = "turningPage";
    state.tts.statusText = t("Syncing page turn…");
    updateTTSChrome();
    try {
      const page = await turnPageForTTS(pending.turnCount, currentTTSAnchor());
      if (!ttsIsCurrent(runID)) return;
      await beginSpeakingPage(page, runID);
    } catch (error) {
      if (ttsIsCurrent(runID)) {
        els.remoteStatus.textContent = error.message || t("Page turn failed");
        stopTTS();
      }
    }
    return;
  }

  await advanceAfterPageSpeech(runID);
}

async function advanceAfterPageSpeech(runID) {
  if (!ttsIsCurrent(runID)) return;
  if (state.tts.advanceLock) return;
  if (!state.tts.autoAdvance) {
    state.tts.state = "idle";
    state.tts.active = false;
    state.tts.statusText = t("Read-aloud finished");
    updateTTSChrome();
    return;
  }

  state.tts.advanceLock = true;
  state.tts.state = "turningPage";
  state.tts.statusText = t("Syncing page turn…");
  updateTTSChrome();

  try {
    const anchor = currentTTSAnchor();
    const preloaded = await takePeekPreload(anchor.key);
    if (!ttsIsCurrent(runID)) return;

    if (preloaded?.kind === "end") {
      state.tts.statusText = t("Reached the end");
      stopTTS();
      els.remoteStatus.textContent = t("Reached the end");
      return;
    }

    if (preloaded?.kind === "ready") {
      const turned = await turnPageForTTS(preloaded.turnCount, anchor);
      if (!ttsIsCurrent(runID)) return;
      const page = turned && textForSpeech(turned) ? turned : preloaded.page;
      // 必须允许跨页 peek：否则只有开读第一页会合并，后续页末未完句会与下页首句拆开叠读
      await beginSpeakingPage(page, runID, {
        skipCrossPeek: false,
        schedulePreload: true,
      });
      return;
    }

    const result = await fetchNextSpeakablePage(runID, anchor, true);
    if (!ttsIsCurrent(runID)) return;
    if (result.kind === "end") {
      state.tts.statusText = t("Reached the end");
      stopTTS();
      els.remoteStatus.textContent = t("Reached the end");
      return;
    }
    await beginSpeakingPage(result.page, runID);
  } catch (error) {
    if (!ttsIsCurrent(runID)) return;
    if (error.message === "cancelled") return;
    els.remoteStatus.textContent = error.message || t("Page turn failed, stopped reading aloud");
    stopTTS();
  } finally {
    state.tts.advanceLock = false;
  }
}

async function syncAfterManualPageTurn() {
  if (!state.tts.active) return;
  if (!["speaking", "paused", "turningPage", "loading"].includes(state.tts.state)) {
    return;
  }

  const runID = state.tts.runID;
  const prevKey = state.tts.pageKey;
  const prevHash = state.tts.contentHash;
  const prevSpeech = state.tts.speechFp;

  invalidatePeekPreload();
  state.tts.sentenceQueue = [];
  state.tts.nextConsumedPrefix = "";
  state.tts.nextConsumedMeta = null;
  state.tts.pendingCrossTurn = null;
  state.tts.crossPage = null;
  state.tts.awaitingCrossPeek = false;
  stopSpeakingSilently();
  state.tts.state = "turningPage";
  state.tts.statusText = t("Syncing new page…");
  updateTTSChrome();

  try {
    const page = await waitForPageChange(prevKey, prevHash, prevSpeech, {
      initialMs: 0,
      attemptMs: 50,
      attempts: 12,
    });
    if (!ttsIsCurrent(runID)) return;
    await beginSpeakingPage(page, runID);
  } catch (error) {
    if (ttsIsCurrent(runID)) {
      els.remoteStatus.textContent = error.message || t("Sync failed");
      stopTTS();
    }
  }
}

async function syncTTSIfReadingPositionChanged(pageKey, pageLabel) {
  if (!state.tts.active) return;
  if (state.tts.state !== "speaking" && state.tts.state !== "paused") return;
  if (Date.now() < (state.tts.suppressPositionSyncUntil || 0)) return;
  // 本端自动翻页 / 跨页翻页进行中，不抢同步
  if (state.tts.crossPage) return;
  const key = pageKey?.trim?.() || pageKey || null;
  const label = pageLabel?.trim?.() || pageLabel || null;
  if (!key && !label) return;
  if (key && key === state.tts.pageKey) return;
  if (label && label === state.tts.pageKey) return;
  // 显示页码一致时忽略 page_key 格式差异，避免误触发整页重读
  if (label && state.current?.page && String(label) === String(state.current.page)) return;
  await syncAfterManualPageTurn();
}

async function startTTS() {
  if (!capEnabled("tts") && !capEnabled("pageText")) return;
  if (!window.speechSynthesis) {
    alert(t("This browser doesn't support speech synthesis"));
    return;
  }
  const runID = ttsNewRun();
  state.tts.active = true;
  state.tts.autoAdvance = true;
  state.tts.state = "loading";
  state.tts.statusText = t("Loading page text…");
  state.tts.nextConsumedPrefix = "";
  state.tts.pendingCrossTurn = null;
  updateTTSChrome();
  try {
    const page = await loadPageText();
    if (!ttsIsCurrent(runID)) return;
    await beginSpeakingPage(page, runID);
  } catch (error) {
    if (ttsIsCurrent(runID)) {
      els.remoteStatus.textContent = error.message || t("Read aloud failed");
      stopTTS();
    }
  }
}

function toggleTTS() {
  if (!capEnabled("tts") && !capEnabled("pageText")) return;
  if (!window.speechSynthesis) {
    alert(t("This browser doesn't support speech synthesis"));
    return;
  }
  const tts = state.tts;
  if (tts.active && tts.state === "speaking") {
    window.speechSynthesis.pause();
    tts.state = "paused";
    tts.statusText = t("Paused");
    updateTTSChrome();
    return;
  }
  if (tts.active && tts.state === "paused") {
    window.speechSynthesis.resume();
    tts.state = "speaking";
    tts.statusText = t("Reading aloud");
    updateTTSChrome();
    return;
  }
  startTTS();
}

function showTTSSettings() {
  const offset = ttsPageTurnOffsetSec();
  openSheet(
    t("Read-aloud settings"),
    `
    <div class="slider-row">
      <label><span>${escapeHTML(t("Speed"))}</span><span id="rate-val">${Number(state.prefs.ttsRate).toFixed(2).replace(/\.?0+$/, "") || "1"}x</span></label>
      <input id="tts-rate" type="range" min="0.25" max="3" step="0.05" value="${state.prefs.ttsRate}" />
    </div>
    <div class="slider-row">
      <label><span>${escapeHTML(t("Page turn offset"))}</span><span id="offset-val">${formatTurnOffsetLabel(offset)}</span></label>
      <input id="tts-turn-offset" type="range" min="-3" max="3" step="0.1" value="${offset}" />
    </div>
    <p class="hint">${escapeHTML(
      t(
        "Uses your browser's built-in speech synthesis. The page turn offset applies at cross-page sentence boundaries: turning early is converted to characters based on speed, turning late uses wall-clock seconds (default: 1.0s early). Speed range: 0.25x–3x.",
      ),
    )}</p>
    <div class="sheet-actions">
      <button class="btn btn-primary" type="button" id="tts-start">${escapeHTML(t("Start reading aloud"))}</button>
      <button class="btn btn-danger" type="button" id="tts-stop2">${escapeHTML(t("Stop"))}</button>
    </div>
  `
  );
  const rate = document.getElementById("tts-rate");
  const offsetEl = document.getElementById("tts-turn-offset");
  const formatRate = (v) => `${Number(v).toFixed(2).replace(/\.?0+$/, "")}x`;
  rate.addEventListener("input", () => {
    document.getElementById("rate-val").textContent = formatRate(rate.value);
  });
  rate.addEventListener("change", () => {
    state.prefs.ttsRate = Math.min(3, Math.max(0.25, Number(rate.value)));
    savePrefs();
  });
  offsetEl.addEventListener("input", () => {
    document.getElementById("offset-val").textContent = formatTurnOffsetLabel(offsetEl.value);
  });
  offsetEl.addEventListener("change", () => {
    state.prefs.ttsPageTurnOffsetSec = Math.min(3, Math.max(-3, Number(offsetEl.value)));
    savePrefs();
  });
  document.getElementById("tts-start").onclick = () => {
    closeSheet();
    startTTS();
  };
  document.getElementById("tts-stop2").onclick = () => {
    stopTTS();
    closeSheet();
  };
}

async function turnPage(direction) {
  const device = state.current;
  if (!device || state.turning) return;
  const path = direction === "next" ? "/api/next" : "/api/previous";
  const label = direction === "next" ? t("Next page") : t("Previous page");
  state.turning = true;
  vibrateLight();
  els.remoteStatus.textContent = t("Sent · {label}", { label });
  try {
    await deviceFetch(device, path);
    await refreshRemoteStatus();
    await syncAfterManualPageTurn();
  } catch (error) {
    els.remoteStatus.textContent = error.message || t("{label} failed", { label });
  } finally {
    state.turning = false;
  }
}

// events
els.btnScan.addEventListener("click", () => refreshDevices());
els.btnManual.addEventListener("click", showManualAdd);
els.btnGuide.addEventListener("click", showGuide);
els.btnBack.addEventListener("click", showHome);
els.btnDeviceInfo.addEventListener("click", showDeviceInfo);
els.btnAppMenu.addEventListener("click", openMenu);
els.btnPrev.addEventListener("click", () => turnPage("prev"));
els.btnNext.addEventListener("click", () => turnPage("next"));
els.ttsPlay.addEventListener("click", () => toggleTTS());
els.ttsStop.addEventListener("click", () => stopTTS());
els.ttsSettings.addEventListener("click", showTTSSettings);
els.bottomBarTip.addEventListener("click", () => dismissBarTip(true));

els.sheetRoot.addEventListener("click", (event) => {
  if (event.target.closest("[data-close-sheet]")) closeSheet();
});
els.menuRoot.addEventListener("click", (event) => {
  if (event.target.closest("[data-close-menu]")) {
    closeMenu();
    return;
  }
  const item = event.target.closest("[data-menu]");
  if (!item) return;
  const key = item.dataset.menu;
  closeMenu();
  if (key === "layout") {
    state.prefs.pageTurnLayout =
      state.prefs.pageTurnLayout === "vertical" ? "horizontal" : "vertical";
    savePrefs();
    updatePageLayout();
  } else if (key === "edit-bar") {
    showBarEditor();
  } else if (key === "haptic") {
    state.prefs.haptic = !state.prefs.haptic;
    savePrefs();
  } else if (key === "appearance") {
    const order = ["system", "light", "dark"];
    const i = order.indexOf(state.prefs.appearance);
    state.prefs.appearance = order[(i + 1) % order.length];
    savePrefs();
  }
});

document.addEventListener("keydown", (event) => {
  if (els.viewRemote.classList.contains("hidden")) return;
  if (event.target && ["INPUT", "TEXTAREA"].includes(event.target.tagName)) return;
  if (event.key === "ArrowRight" || event.key === "PageDown" || event.key === " ") {
    event.preventDefault();
    turnPage("next");
  } else if (event.key === "ArrowLeft" || event.key === "PageUp") {
    event.preventDefault();
    turnPage("prev");
  } else if (event.key === "Escape") {
    if (!els.sheetRoot.classList.contains("hidden")) closeSheet();
    else if (!els.menuRoot.classList.contains("hidden")) closeMenu();
    else showHome();
  }
});

async function bootstrapEmbeddedDevice() {
  if (!EMBEDDED_IN_PLUGIN) return;
  const self = servingDevice();
  if (!self) return;
  try {
    const ping = await deviceFetch(self, "/api/ping");
    state.serving = enrichFromPing(self, ping);
    renderLists();
    // 打开插件页即进入当前设备遥控
    openRemote(state.serving);
  } catch (error) {
    state.serving = { ...self, deviceName: t("This reader (offline?)") };
    renderLists();
    console.warn("bootstrap serving device failed", error);
  }
}

async function main() {
  await initI18n();
  applyDocumentI18n(document);
  applyAppearance();
  updatePageLayout();
  renderLists();
  await bootstrapEmbeddedDevice();
}
void main();

