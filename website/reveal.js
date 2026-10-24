// Scroll reveal for elements marked [data-reveal]: they fade up once, in order, the first time they come into view.
// The hidden state only applies under html.has-reveal, which this script sets, so nothing is hidden without JS.

(() => {
  const targets = [...document.querySelectorAll("[data-reveal]")];
  if (!targets.length || !("IntersectionObserver" in window)) return;
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

  // Stagger siblings: each card waits a beat after the one before it.
  for (const target of targets) {
    const siblings = [...target.parentElement.children].filter((el) => el.hasAttribute("data-reveal"));
    target.style.setProperty("--reveal-index", String(siblings.indexOf(target)));
  }
  document.documentElement.classList.add("has-reveal");

  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      }
    },
    { rootMargin: "0px 0px -10% 0px", threshold: 0.15 },
  );
  targets.forEach((target) => observer.observe(target));
})();
