(function () {
  var BASE = "https://github.com/AMarcinkiewicz/chatterfix/releases/latest/download/";

  // Official Apple and Windows marks, monochrome so they inherit the button color.
  var APPLE = '<svg class="mark-apple" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M17.05 12.04c-.03-2.6 2.12-3.84 2.22-3.9-1.21-1.78-3.09-2.02-3.78-2.05-1.61-.16-3.14.94-3.95.94-.81 0-2.07-.92-3.4-.9-1.75.03-3.36 1.02-4.26 2.58-1.82 3.15-.46 7.81 1.3 10.37.86 1.25 1.89 2.66 3.24 2.61 1.3-.05 1.79-.84 3.36-.84 1.57 0 2.01.84 3.39.81 1.4-.03 2.29-1.28 3.15-2.54.99-1.46 1.4-2.87 1.42-2.94-.03-.02-2.73-1.05-2.76-4.16zM14.53 4.62c.72-.87 1.2-2.08 1.07-3.29-1.03.04-2.29.69-3.03 1.56-.66.77-1.24 2.01-1.09 3.19 1.15.09 2.32-.59 3.05-1.46z"/></svg>';
  var WINDOWS = '<svg class="mark-win" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M3 3h8v8H3zM13 3h8v8h-8zM3 13h8v8H3zM13 13h8v8h-8z"/></svg>';

  var MAC = { url: BASE + "ChatterFix-macOS.dmg", label: "Download for macOS", icon: APPLE };
  var WIN = { url: BASE + "ChatterFix-Windows.exe", label: "Download for Windows", icon: WINDOWS };

  function detect() {
    var p = (navigator.userAgentData && navigator.userAgentData.platform) || "";
    var s = (p + " " + navigator.platform + " " + navigator.userAgent).toLowerCase();
    if (s.indexOf("win") !== -1) return WIN;
    if (s.indexOf("mac") !== -1 || s.indexOf("iphone") !== -1 || s.indexOf("ipad") !== -1) return MAC;
    return null; // unknown: leave buttons pointing at the Releases page
  }

  var here = detect();
  if (here) {
    var there = here === MAC ? WIN : MAC;

    var primary = document.getElementById("primary-download");
    var primaryLabel = document.getElementById("primary-label");
    var primaryIcon = document.getElementById("primary-icon");
    if (primary) primary.href = here.url;
    if (primaryLabel) primaryLabel.textContent = here.label;
    if (primaryIcon) primaryIcon.innerHTML = here.icon;

    var secondary = document.getElementById("secondary-download");
    var secondaryLabel = document.getElementById("secondary-label");
    if (secondary) secondary.href = there.url;
    if (secondaryLabel) secondaryLabel.textContent = there.label;
  }

  // Show the mockup that matches the visitor's OS. Mac stays the default so a
  // no-JS or unknown-OS visitor still sees a valid screenshot.
  if (here === WIN) {
    var macStage = document.querySelector(".stage-mac");
    var winStage = document.querySelector(".stage-win");
    if (macStage && winStage) {
      macStage.hidden = true;
      winStage.hidden = false;
    }
  }

  // Typing demo: several phrases typed on a chattering keyboard vs with ChatterFix.
  var bad = document.getElementById("demo-bad");
  var good = document.getElementById("demo-good");
  if (bad && good) {
    var examples = [
      { text: "hello world", doubleAt: { 3: true, 8: true } },
      { text: "good morning", doubleAt: { 2: true, 7: true } },
      { text: "type it once", doubleAt: { 2: true, 9: true } },
      { text: "double check", doubleAt: { 3: true, 10: true } }
    ];
    function buildBad(ex) {
      var s = "";
      for (var i = 0; i < ex.text.length; i++) {
        s += ex.text[i];
        if (ex.doubleAt[i]) s += '<span class="chat">' + ex.text[i] + "</span>";
      }
      return s;
    }
    var reduced = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    if (reduced) {
      bad.innerHTML = buildBad(examples[0]);
      good.textContent = examples[0].text;
    } else {
      var caret = '<span class="caret"></span>';
      var sleep = function (ms) { return new Promise(function (r) { setTimeout(r, ms); }); };

      (async function loop() {
        var idx = 0;
        while (true) {
          var ex = examples[idx];
          var b = "", g = "";
          for (var i = 0; i < ex.text.length; i++) {
            var ch = ex.text[i];
            g += ch;
            b += ch;
            if (ex.doubleAt[i]) b += '<span class="chat">' + ch + "</span>";
            bad.innerHTML = b + caret;
            good.innerHTML = g + caret;
            await sleep(ch === " " ? 130 : 115);
          }
          bad.innerHTML = b;
          good.innerHTML = g;
          await sleep(1800);
          bad.innerHTML = caret;
          good.innerHTML = caret;
          await sleep(500);
          idx = (idx + 1) % examples.length;
        }
      })();
    }
  }
})();

// Hero typewriter: acts out a double-press being deleted, then finishing.
(function () {
  var wrap = document.querySelector(".type-word");
  var live = document.querySelector(".type-live");
  if (!wrap || !live) return;
  if (window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    return; // leave the static ghost word visible
  }

  wrap.classList.add("js-typing");
  var caret = '<span class="type-caret"></span>';
  var base = "";
  var extra = "";
  function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;"); }
  function render() {
    live.innerHTML =
      esc(base) + (extra ? '<span class="chat">' + esc(extra) + "</span>" : "") + caret;
  }
  var sleep = function (ms) { return new Promise(function (r) { setTimeout(r, ms); }); };
  render();

  (async function loop() {
    while (true) {
      for (var i = 0; i < 4; i++) { base += "typi"[i]; render(); await sleep(i === 3 ? 40 : 120); }
      extra = "i"; render();                     // the double-press bounces in instantly
      await sleep(430);                          // it sits there for a beat
      extra = ""; render(); await sleep(150);    // ChatterFix deletes the extra
      var rest = "ng.";
      for (var j = 0; j < rest.length; j++) { base += rest[j]; render(); await sleep(125); }
      await sleep(2600);                         // hold the finished word
      while (base.length) { base = base.slice(0, -1); render(); await sleep(55); }
      await sleep(650);
    }
  })();
})();
