/*
 * VANTA — catalog interactions: category filter, live search, sort,
 * "New" badges, and a localStorage-backed wishlist.
 * Progressive enhancement: with JS off, all products still render.
 */
(function () {
  "use strict";

  var CAT_LABELS = {
    "accessories": "Accessories",
    "apparel": "Apparel",
    "footwear": "Footwear",
    "home-kitchen": "Home & Kitchen",
    "beauty": "Beauty",
    "tech": "Tech"
  };
  var WISH_KEY = "vanta_wishlist";

  // --- pretty category chips (home + product page) ---
  document.querySelectorAll(".vpc-cat[data-cat]").forEach(function (el) {
    var slug = el.getAttribute("data-cat");
    el.textContent = CAT_LABELS[slug] || slug;
  });

  // --- wishlist helpers (shared) ---
  function loadWish() {
    try { return new Set(JSON.parse(localStorage.getItem(WISH_KEY) || "[]")); }
    catch (e) { return new Set(); }
  }
  function saveWish(set) {
    try { localStorage.setItem(WISH_KEY, JSON.stringify(Array.from(set))); } catch (e) {}
  }
  var wish = loadWish();

  function bindWish(btn) {
    var id = btn.getAttribute("data-id");
    var saved = wish.has(id);
    btn.classList.toggle("is-saved", saved);
    btn.setAttribute("aria-pressed", saved ? "true" : "false");
    btn.addEventListener("click", function (e) {
      e.preventDefault(); e.stopPropagation();
      if (wish.has(id)) { wish.delete(id); } else { wish.add(id); }
      saveWish(wish);
      var on = wish.has(id);
      btn.classList.toggle("is-saved", on);
      btn.setAttribute("aria-pressed", on ? "true" : "false");
    });
  }
  document.querySelectorAll(".vpc-wish").forEach(bindWish);

  var grid = document.getElementById("product-grid");
  if (!grid) return; // not on the home page

  var cards = Array.prototype.slice.call(grid.querySelectorAll(".vanta-product-card"));

  // --- "New" badge on freshly-added products (VNT* ids) ---
  cards.forEach(function (card) {
    if ((card.getAttribute("data-id") || "").indexOf("VNT") === 0) {
      var wrap = card.querySelector(".vpc-media-wrap");
      if (wrap && !wrap.querySelector(".vpc-badge-new")) {
        var b = document.createElement("span");
        b.className = "vpc-badge-new";
        b.textContent = "New";
        wrap.appendChild(b);
      }
    }
  });

  var pills = Array.prototype.slice.call(document.querySelectorAll(".cat-pill"));
  var sortSel = document.getElementById("sort");
  var searchEl = document.getElementById("search");
  var countEl = document.getElementById("result-count");
  var emptyEl = document.getElementById("grid-empty");
  var originalOrder = cards.slice();
  var activeFilter = "all";
  var term = "";

  function applyFilter() {
    var shown = 0;
    cards.forEach(function (card) {
      var catOk = activeFilter === "all" || card.getAttribute("data-category") === activeFilter;
      var nameOk = !term || (card.getAttribute("data-name") || "").toLowerCase().indexOf(term) !== -1;
      var match = catOk && nameOk;
      card.hidden = !match;
      if (match) shown++;
    });
    if (countEl) countEl.textContent = shown;
    if (emptyEl) emptyEl.hidden = shown !== 0;
  }

  function price(card) { return parseFloat(card.getAttribute("data-price")) || 0; }
  function name(card) { return card.getAttribute("data-name") || ""; }

  function applySort() {
    var mode = sortSel ? sortSel.value : "featured";
    var arr = originalOrder.slice();
    if (mode === "price-asc") arr.sort(function (a, b) { return price(a) - price(b); });
    else if (mode === "price-desc") arr.sort(function (a, b) { return price(b) - price(a); });
    else if (mode === "name") arr.sort(function (a, b) { return name(a).localeCompare(name(b)); });
    arr.forEach(function (card) { grid.appendChild(card); });
  }

  pills.forEach(function (pill) {
    pill.addEventListener("click", function () {
      pills.forEach(function (p) { p.classList.remove("active"); p.setAttribute("aria-selected", "false"); });
      pill.classList.add("active");
      pill.setAttribute("aria-selected", "true");
      activeFilter = pill.getAttribute("data-filter");
      applyFilter();
    });
  });

  if (sortSel) sortSel.addEventListener("change", function () { applySort(); applyFilter(); });

  if (searchEl) {
    searchEl.addEventListener("input", function () {
      term = searchEl.value.trim().toLowerCase();
      applyFilter();
    });
  }

  applyFilter();
})();
