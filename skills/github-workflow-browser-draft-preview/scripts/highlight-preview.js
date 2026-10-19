// Pass this file's text to Claude in Chrome's javascript_tool after the
// editor is switched to Preview. It finds every GitHub markdown editor whose
// Preview tab is selected, plus a PR title field when one is on the page,
// draws a red box around each, and scrolls the first into the middle of the
// viewport. Re-running it clears the old boxes first; `clearDraftHighlight()`
// clears them without drawing new ones. Returns what it boxed, so a result of
// `[]` means the Preview tab was not selected.
(() => {
  const MARK = "data-claude-draft-highlight";
  window.clearDraftHighlight = () =>
    document.querySelectorAll(`[${MARK}]`).forEach((el) => {
      el.style.outline = el.getAttribute(MARK);
      el.style.outlineOffset = "";
      el.removeAttribute(MARK);
    });
  window.clearDraftHighlight();

  const box = (el) => {
    el.setAttribute(MARK, el.style.outline || "");
    el.style.outline = "4px solid #e5091d";
    el.style.outlineOffset = "4px";
    return el;
  };

  // A selected Preview tab: GitHub's editors mark it with aria-selected or
  // aria-pressed, depending on the editor generation.
  const selected = [...document.querySelectorAll('[role="tab"], button')].filter(
    (b) =>
      /^\s*preview\s*$/i.test(b.textContent) &&
      (b.getAttribute("aria-selected") === "true" || b.getAttribute("aria-pressed") === "true") &&
      b.offsetParent !== null,
  );
  // The editor is the nearest ancestor of the tab that also holds the textarea.
  const editors = selected
    .map((tab) => {
      let el = tab.parentElement;
      while (el && !el.querySelector("textarea")) el = el.parentElement;
      return el;
    })
    .filter(Boolean);

  const title = document.querySelector(
    'input[name="pull_request[title]"], input[name="issue[title]"], input[aria-label="Title"]',
  );
  const boxed = [...new Set(editors)].map(box);
  if (title && title.offsetParent !== null) boxed.unshift(box(title.closest("div") || title));
  if (boxed.length) boxed[0].scrollIntoView({ block: "center", behavior: "instant" });
  return boxed.map((el) => el.tagName.toLowerCase() + (el.id ? "#" + el.id : ""));
})();
