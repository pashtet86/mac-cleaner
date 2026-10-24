// Hero examples: one tool at a time. Every 3.5 s the next one becomes .is-active; the crossfade itself is CSS.
// Pauses on hover, focus, a hidden tab or the Pause button; with reduced motion the global CSS rule makes the
// switch instant.

(() => {
  const root = document.querySelector(".examples");
  if (!root) return;
  const items = [...root.querySelectorAll(".example")];
  const list = root.querySelector(".examples__items");
  const pauseButton = root.querySelector(".examples__pause");
  if (items.length < 2) return;

  const STEP = 3500;
  let index = 0;
  let timer = null;
  let pausedByUser = false;
  let hovering = false;

  function setActive(next) {
    items[index].classList.remove("is-active");
    items[index].setAttribute("aria-hidden", "true");
    index = (next + items.length) % items.length;
    items[index].classList.add("is-active");
    items[index].removeAttribute("aria-hidden");
  }

  const running = () => !pausedByUser && !hovering && !document.hidden;

  function schedule() {
    clearInterval(timer);
    timer = running() ? setInterval(() => setActive(index + 1), STEP) : null;
    root.classList.toggle("is-paused", pausedByUser);
    pauseButton.textContent = pausedByUser ? "Play" : "Pause";
    pauseButton.setAttribute("aria-label", pausedByUser ? "Play examples" : "Pause examples");
    list.setAttribute("aria-live", running() ? "off" : "polite");
  }

  items.forEach((item, i) => {
    item.classList.toggle("is-active", i === 0);
    if (i !== 0) item.setAttribute("aria-hidden", "true");
  });
  root.classList.add("is-ready");

  pauseButton.hidden = false;
  pauseButton.addEventListener("click", () => {
    pausedByUser = !pausedByUser;
    schedule();
  });
  root.addEventListener("mouseenter", () => {
    hovering = true;
    schedule();
  });
  root.addEventListener("mouseleave", () => {
    hovering = false;
    schedule();
  });
  root.addEventListener("focusin", () => {
    hovering = true;
    schedule();
  });
  root.addEventListener("focusout", (event) => {
    if (!root.contains(event.relatedTarget)) {
      hovering = false;
      schedule();
    }
  });
  document.addEventListener("visibilitychange", schedule);

  schedule();
})();
