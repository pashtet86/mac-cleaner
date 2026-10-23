// Disk map demo: a sample developer disk drawn as a squarified treemap.
// "Clean" removes the tiles that rebuild themselves; the rest reflow into the freed space.

const DISK_TOTAL = 494;

const SAFETY = {
  rebuildable: "rebuilds itself",
  likely: "probably safe to remove",
  review: "your call",
  yours: "your files — never selected for you",
};

// Sample data (GB). Sizes are typical for an iOS and React Native developer's Mac.
const ITEMS = [
  { id: "photos", name: "Photos and documents", size: 38.0, safety: "yours", detail: "Your own files. Disk Cleaner can map them, but never picks them for you." },
  { id: "projects", name: "Your projects", size: 18.5, safety: "yours", detail: "Source code and assets. Only the build output inside them is ever suggested." },
  { id: "simruntimes", name: "Old simulator runtimes", size: 16.2, safety: "review", detail: "iOS 26.5 and tvOS 26.5. Remove the ones you no longer test on — Xcode downloads them again if needed." },
  { id: "deriveddata", name: "Xcode DerivedData", size: 11.7, safety: "rebuildable", detail: "Build products and indexes. Xcode rebuilds them on the next build." },
  { id: "nodemodules", name: "node_modules (14 projects)", size: 9.4, safety: "rebuildable", detail: "JavaScript dependencies. npm, Yarn or pnpm install restores them." },
  { id: "ndk", name: "Android NDK versions", size: 9.9, safety: "review", detail: "Four NDK versions side by side. Keep the one your projects pin with ndkVersion." },
  { id: "xip", name: "Xcode_27.xip in Downloads", size: 5.9, safety: "likely", detail: "An installer that already did its job. Not needed once Xcode is installed." },
  { id: "devicesupport", name: "iOS DeviceSupport", size: 5.6, safety: "review", detail: "Debug symbols copied from your iPhones. Copied again, slowly, the next time a device connects." },
  { id: "gradle", name: "Gradle caches", size: 4.6, safety: "rebuildable", detail: "Dependencies and Gradle distributions. The next Android build downloads them again." },
  { id: "orphans", name: "Unavailable simulators", size: 3.5, safety: "rebuildable", detail: "Devices whose runtime was already removed. They can't boot anymore." },
  { id: "docker", name: "Docker build cache", size: 2.4, safety: "rebuildable", detail: "Layers cached by docker build. The next build is slower once." },
  { id: "expo", name: "Expo and Metro caches", size: 1.8, safety: "likely", detail: "Expo Go builds and bundler caches. Login and signing data are kept." },
  { id: "npm", name: "npm cache", size: 1.3, safety: "rebuildable", detail: "Downloaded package tarballs, the same as npm cache clean --force." },
];

const USED_OTHER = 318; // System, apps and everything outside the map.

const map = document.getElementById("map");
const detail = document.getElementById("detail");
const clean = document.getElementById("clean");
const diskFree = document.getElementById("disk-free");
const diskUsed = document.getElementById("disk-used");

let cleaned = false;
// After Clean, the result message stays put even though tiles slide under the pointer.
let holdMessageUntil = 0;
const tiles = new Map();

const gb = (value) => `${value.toFixed(1)} GB`;
const visible = () => ITEMS.filter((item) => !(cleaned && item.safety === "rebuildable"));
const cleanableTotal = ITEMS.filter((i) => i.safety === "rebuildable").reduce((sum, i) => sum + i.size, 0);

// Squarified treemap (Bruls, Huizing, van Wijk). `values` sorted largest first.
function squarify(values, rect) {
  const result = [];
  const total = values.reduce((a, b) => a + b, 0);
  if (!total || rect.w <= 0 || rect.h <= 0) return values.map(() => ({ x: 0, y: 0, w: 0, h: 0 }));
  const scale = (rect.w * rect.h) / total;
  const areas = values.map((v) => v * scale);
  let { x, y, w, h } = rect;
  let start = 0;

  const worst = (row, sum, side) => {
    const s2 = sum * sum;
    const side2 = side * side;
    return row.reduce((m, a) => Math.max(m, (side2 * a) / s2, s2 / (side2 * a)), 0);
  };

  while (start < areas.length) {
    const side = Math.min(w, h);
    let end = start + 1;
    let sum = areas[start];
    while (end < areas.length) {
      const next = sum + areas[end];
      if (worst(areas.slice(start, end + 1), next, side) > worst(areas.slice(start, end), sum, side)) break;
      sum = next;
      end += 1;
    }
    const thickness = sum / side;
    let offset = 0;
    for (let i = start; i < end; i += 1) {
      const length = areas[i] / thickness;
      result[i] = w >= h
        ? { x, y: y + offset, w: thickness, h: length }
        : { x: x + offset, y, w: length, h: thickness };
      offset += length;
    }
    if (w >= h) {
      x += thickness;
      w -= thickness;
    } else {
      y += thickness;
      h -= thickness;
    }
    start = end;
  }
  return result;
}

function tileFor(item) {
  if (tiles.has(item.id)) return tiles.get(item.id);
  const tile = document.createElement("button");
  tile.type = "button";
  tile.className = "tile";
  tile.dataset.safety = item.safety;
  tile.setAttribute("aria-label", `${item.name}, ${gb(item.size)}, ${SAFETY[item.safety]}`);
  const name = document.createElement("span");
  name.className = "tile__name";
  name.textContent = item.name;
  const size = document.createElement("span");
  size.className = "tile__size";
  size.textContent = gb(item.size);
  tile.append(name, size);

  tile.addEventListener("mouseenter", () => {
    if (Date.now() >= holdMessageUntil) describe(item);
  });
  tile.addEventListener("focus", () => describe(item));
  tile.addEventListener("click", () => describe(item));
  map.append(tile);
  tiles.set(item.id, tile);
  return tile;
}

function describe(item) {
  for (const [id, tile] of tiles) tile.setAttribute("aria-current", String(id === item.id));
  detail.replaceChildren();
  const strong = document.createElement("strong");
  strong.textContent = `${item.name}, ${gb(item.size)}.`;
  detail.append(strong, ` ${item.detail}`);
}

function layout() {
  const gap = 4;
  const bounds = map.getBoundingClientRect();
  const items = visible().sort((a, b) => b.size - a.size);
  const rects = squarify(items.map((i) => i.size), { x: 0, y: 0, w: bounds.width, h: bounds.height });

  items.forEach((item, index) => {
    const r = rects[index];
    const tile = tileFor(item);
    tile.classList.remove("tile--gone");
    tile.style.left = `${r.x + gap / 2}px`;
    tile.style.top = `${r.y + gap / 2}px`;
    tile.style.width = `${Math.max(0, r.w - gap)}px`;
    tile.style.height = `${Math.max(0, r.h - gap)}px`;
    tile.classList.toggle("tile--compact", r.w < 92 || r.h < 52);
    tile.tabIndex = 0;
  });

  // Cleaned tiles fade where they stood; the others grow into the space.
  for (const item of ITEMS) {
    if (cleaned && item.safety === "rebuildable") {
      const tile = tileFor(item);
      tile.classList.add("tile--gone");
      tile.tabIndex = -1;
    }
  }
}

function updateDisk() {
  const mapped = visible().reduce((sum, item) => sum + item.size, 0);
  const used = USED_OTHER + mapped;
  diskFree.textContent = gb(DISK_TOTAL - used);
  diskUsed.style.width = `${(used / DISK_TOTAL) * 100}%`;
  clean.textContent = cleaned ? "Put it back" : `Clean ${gb(cleanableTotal)}`;
}

clean.addEventListener("click", () => {
  cleaned = !cleaned;
  layout();
  updateDisk();
  detail.replaceChildren();
  if (cleaned) {
    holdMessageUntil = Date.now() + 2500;
    const strong = document.createElement("strong");
    strong.textContent = `${gb(cleanableTotal)} moved to the Trash.`;
    detail.append(strong, " Everything blue comes back by itself the next time you build or install. The rest waits for you to decide.");
  } else {
    detail.textContent = "Point at a tile to see what it is and whether it comes back on its own.";
  }
});

new ResizeObserver(layout).observe(map);
updateDisk();
layout();
