// Google Analytics 4 (gtag.js only, no Tag Manager container), loaded only after the visitor agrees.
// The site Worker prepends `self.GA_MEASUREMENT_ID = "G-…";` from its GA_MEASUREMENT_ID variable; without it
// (local preview, or the variable unset) this file does nothing and no banner appears.

(() => {
  const id = self.GA_MEASUREMENT_ID;
  if (typeof id !== "string" || !/^G-[A-Z0-9]{4,16}$/.test(id)) return;

  const KEY = "analytics-consent"; // "granted" | "denied"
  const read = () => {
    try {
      return localStorage.getItem(KEY);
    } catch {
      return null;
    }
  };
  const write = (value) => {
    try {
      localStorage.setItem(KEY, value);
    } catch {
      // Private mode: the choice lasts for this page only.
    }
  };

  let loaded = false;
  function load() {
    if (loaded) return;
    loaded = true;
    window.dataLayer = window.dataLayer || [];
    window.gtag = function gtag() {
      window.dataLayer.push(arguments);
    };
    window.gtag("js", new Date());
    window.gtag("config", id);
    const script = document.createElement("script");
    script.async = true;
    script.src = `https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(id)}`;
    document.head.append(script);
  }

  // Downloads go through /download (no .dmg in the link), so GA's automatic download tracking can't see them.
  document.addEventListener("click", (event) => {
    const link = event.target instanceof Element ? event.target.closest('a[href="/download"]') : null;
    if (link && loaded) window.gtag("event", "file_download", { file_name: "DiskCleaner.dmg", link_url: link.href });
  });

  function banner() {
    const box = document.createElement("div");
    box.className = "consent-banner";
    box.setAttribute("role", "dialog");
    box.setAttribute("aria-label", "Analytics cookies");

    const text = document.createElement("p");
    text.append("We'd like to use Google Analytics cookies to see how people find this site. The app itself is not affected. ");
    const more = document.createElement("a");
    more.href = "/privacy#analytics";
    more.textContent = "Learn more";
    text.append(more);

    const actions = document.createElement("div");
    actions.className = "consent-banner__actions";
    const decline = document.createElement("button");
    decline.type = "button";
    decline.className = "button button--small button--ghost";
    decline.textContent = "Decline";
    const accept = document.createElement("button");
    accept.type = "button";
    accept.className = "button button--small";
    accept.textContent = "Accept";
    actions.append(decline, accept);

    const close = (choice) => {
      write(choice);
      box.remove();
      if (choice === "granted") load();
    };
    decline.addEventListener("click", () => close("denied"));
    accept.addEventListener("click", () => close("granted"));

    box.append(text, actions);
    document.body.append(box);
  }

  // "Cookie settings" in the footer reopens the choice. Withdrawing takes full effect on the next page load.
  for (const link of document.querySelectorAll("[data-cookie-settings]")) {
    link.hidden = false;
    link.addEventListener("click", (event) => {
      event.preventDefault();
      if (!document.querySelector(".consent-banner")) banner();
    });
  }

  const choice = read();
  if (choice === "granted") load();
  else if (choice !== "denied") banner();
})();
