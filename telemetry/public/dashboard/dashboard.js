// Statistics dashboard. Reads GET /v1/stats with the token the owner typed; every value is written with
// textContent, so nothing from the API is ever parsed as HTML.

const STORAGE_KEY = "stats-token";
const $ = (id) => document.getElementById(id);

const form = $("signin");
const tokenInput = $("token");
const errorText = $("error");
const stats = $("stats");

const number = new Intl.NumberFormat("en");
const fmt = (value) => (value == null ? "—" : number.format(value));

function bytes(value) {
  if (!value) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB", "PB"];
  const power = Math.min(Math.floor(Math.log10(value) / 3), units.length - 1);
  return `${(value / 1000 ** power).toFixed(power > 2 ? 1 : 0)} ${units[power]}`;
}

function readToken() {
  try {
    return sessionStorage.getItem(STORAGE_KEY);
  } catch {
    return null;
  }
}

function saveToken(token) {
  try {
    if (token) sessionStorage.setItem(STORAGE_KEY, token);
    else sessionStorage.removeItem(STORAGE_KEY);
  } catch {
    // Private mode: the token just isn't remembered across reloads.
  }
}

let token = readToken();

async function load() {
  errorText.textContent = "";
  let response;
  try {
    response = await fetch("/v1/stats", { headers: { Authorization: `Bearer ${token}` }, cache: "no-store" });
  } catch {
    errorText.textContent = "Couldn't reach the server.";
    return;
  }
  if (response.status === 401) {
    signOut();
    errorText.textContent = "That token isn't right.";
    return;
  }
  if (!response.ok) {
    errorText.textContent = `The server answered ${response.status}.`;
    return;
  }
  render(await response.json());
  form.hidden = true;
  stats.hidden = false;
  $("refresh").hidden = false;
  $("sign-out").hidden = false;
  $("updated").textContent = `Updated ${new Date().toLocaleTimeString()}`;
}

function signOut() {
  token = null;
  saveToken(null);
  form.hidden = false;
  stats.hidden = true;
  $("refresh").hidden = true;
  $("sign-out").hidden = true;
  $("updated").textContent = "";
  tokenInput.value = "";
}

function render(data) {
  const totals = data.totals ?? {};
  const downloads = data.downloads ?? {};
  const cleaned = data.cleaned ?? [];
  $("t-downloads30").textContent = fmt(downloads.last30);
  $("t-downloads").textContent = `${fmt(downloads.total)} all time`;
  $("t-installs").textContent = fmt(totals.installs);
  $("t-weekly").textContent = fmt(totals.weekly_active);
  $("t-monthly").textContent = fmt(totals.monthly_active);
  $("t-churned").textContent = fmt(data.churned?.churned);
  const freed = cleaned.reduce((sum, row) => sum + (row.bytes ?? 0), 0);
  const cleanups = cleaned.reduce((sum, row) => sum + (row.cleanups ?? 0), 0);
  $("t-bytes").textContent = bytes(freed);
  $("t-cleanups").textContent = `${fmt(cleanups)} ${cleanups === 1 ? "cleanup" : "cleanups"}`;

  bars($("c-downloads"), data.downloadsByDay ?? [], "downloads");
  bars($("c-installs"), data.installsByDay ?? [], "installs");
  bars($("c-active"), data.activeByDay ?? [], "active");

  table($("l-cleaned"), cleaned.map((r) => [r.section, bytes(r.bytes), `${fmt(r.cleanups)}×`]));
  table($("l-versions"), (data.appVersions ?? []).map((r) => [r.value, fmt(r.installs)]));
  table($("l-os"), (data.osVersions ?? []).map((r) => [`macOS ${r.value}`, fmt(r.installs)]));
  table($("l-arch"), (data.architectures ?? []).map((r) => [r.value === "arm64" ? "Apple silicon" : "Intel", fmt(r.installs)]));
  table($("l-downloads"), (data.downloadVersions ?? []).map((r) => [r.value, fmt(r.downloads)]));
}

/** One bar per UTC day for the last 30 days, including days with nothing. */
function bars(container, rows, key) {
  const byDay = new Map(rows.map((r) => [r.day, r[key] ?? 0]));
  const days = [];
  const today = new Date();
  for (let i = 29; i >= 0; i--) {
    const d = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate() - i));
    const day = d.toISOString().slice(0, 10);
    days.push([day, byDay.get(day) ?? 0]);
  }
  const max = Math.max(1, ...days.map(([, v]) => v));
  container.replaceChildren(
    ...days.map(([day, value]) => {
      const bar = document.createElement("span");
      bar.className = "bar";
      // A CSSOM custom property: allowed by the style-src 'self' CSP, unlike a style attribute in markup.
      bar.style.setProperty("--h", `${Math.max(value ? 4 : 1, (value / max) * 100)}%`);
      bar.title = `${day}: ${fmt(value)}`;
      return bar;
    }),
  );
  container.setAttribute("aria-label", `${fmt(days.reduce((s, [, v]) => s + v, 0))} in 30 days`);
}

function table(element, rows) {
  const body = document.createElement("tbody");
  if (!rows.length) {
    const row = body.insertRow();
    row.className = "empty";
    row.insertCell().textContent = "No data yet";
  }
  for (const cells of rows) {
    const row = body.insertRow();
    for (const value of cells) row.insertCell().textContent = String(value ?? "—");
  }
  element.replaceChildren(body);
}

form.addEventListener("submit", (event) => {
  event.preventDefault();
  token = tokenInput.value.trim();
  if (!token) return;
  saveToken(token);
  load();
});
$("refresh").addEventListener("click", load);
$("sign-out").addEventListener("click", signOut);

if (token) load();
