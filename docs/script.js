(function () {
  var BASE = "https://github.com/AMarcinkiewicz/chatterfix/releases/latest/download/";
  var MAC = { url: BASE + "ChatterFix-macOS.dmg", label: "Download for macOS", other: "Windows" };
  var WIN = { url: BASE + "ChatterFix-Windows.exe", label: "Download for Windows", other: "macOS" };

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
    var label = document.getElementById("primary-label");
    var secondary = document.getElementById("secondary-download");
    if (primary) primary.href = here.url;
    if (label) label.textContent = here.label;
    if (secondary) {
      secondary.href = there.url;
      secondary.textContent = "Download for " + here.other;
    }
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

  // Typing demo: same phrase typed on a chattering keyboard vs with ChatterFix.
  var bad = document.getElementById("demo-bad");
  var good = document.getElementById("demo-good");
  if (bad && good) {
    var phrase = "hello world";
    var doubleAt = { 3: true, 8: true }; // extra bounce on the second l and the r
    var reduced = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    if (reduced) {
      bad.textContent = "helllo worrld";
      good.textContent = "hello world";
    } else {
      var caret = '<span class="caret"></span>';
      var sleep = function (ms) { return new Promise(function (r) { setTimeout(r, ms); }); };

      (async function loop() {
        while (true) {
          var b = "", g = "";
          for (var i = 0; i < phrase.length; i++) {
            var ch = phrase[i];
            g += ch;
            b += ch;
            if (doubleAt[i]) b += ch;
            bad.innerHTML = b + caret;
            good.innerHTML = g + caret;
            await sleep(ch === " " ? 130 : 115);
          }
          bad.innerHTML = b;
          good.innerHTML = g;
          await sleep(1600);
          bad.innerHTML = caret;
          good.innerHTML = caret;
          await sleep(650);
        }
      })();
    }
  }
})();
