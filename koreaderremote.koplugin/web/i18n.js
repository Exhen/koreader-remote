/** Web UI i18n: English msgids by default; zh catalogs load from i18n-zh_CN.json. */

let catalog = null;
let locale = "en";

function detectLocale() {
  const candidates = [
    ...(navigator.languages || []),
    navigator.language,
    document.documentElement.lang,
  ]
    .filter(Boolean)
    .map((value) => String(value).toLowerCase());
  for (const tag of candidates) {
    if (tag === "zh" || tag.startsWith("zh-")) return "zh_CN";
  }
  return "en";
}

function interpolate(template, vars) {
  if (!vars) return template;
  return String(template).replace(/\{(\w+)\}/g, (match, key) =>
    Object.prototype.hasOwnProperty.call(vars, key) ? String(vars[key]) : match,
  );
}

export function t(msgid, vars) {
  const key = String(msgid ?? "");
  const translated =
    catalog && Object.prototype.hasOwnProperty.call(catalog, key)
      ? catalog[key]
      : key;
  return interpolate(translated, vars);
}

function applyAttrI18n(el) {
  const attrs = (el.getAttribute("data-i18n-attr") || "")
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);
  for (const attr of attrs) {
    const raw = el.getAttribute(attr);
    if (raw) el.setAttribute(attr, t(raw));
  }
}

export function applyDocumentI18n(root = document) {
  const scope = root || document;
  for (const el of scope.querySelectorAll("[data-i18n]")) {
    const msgid = el.getAttribute("data-i18n");
    if (msgid != null && msgid !== "") el.textContent = t(msgid);
  }
  for (const el of scope.querySelectorAll("[data-i18n-html]")) {
    const msgid = el.getAttribute("data-i18n-html");
    if (msgid != null && msgid !== "") el.innerHTML = t(msgid);
  }
  for (const el of scope.querySelectorAll("[data-i18n-attr]")) {
    applyAttrI18n(el);
  }
  if (locale.startsWith("zh")) {
    document.documentElement.lang = "zh-Hans";
  } else {
    document.documentElement.lang = "en";
  }
}

export async function initI18n() {
  locale = detectLocale();
  catalog = null;
  if (locale !== "zh_CN") return locale;

  try {
    const response = await fetch("./i18n-zh_CN.json", {
      cache: "no-store",
      headers: { Accept: "application/json" },
    });
    if (!response.ok) return locale;
    const data = await response.json();
    if (data && typeof data === "object") catalog = data;
  } catch (error) {
    console.warn("i18n: failed to load zh_CN catalog", error);
  }
  return locale;
}

export function getLocale() {
  return locale;
}
