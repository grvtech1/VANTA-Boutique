/*
 * VANTA — catalog interactions: category filtering, sorting, and pretty labels.
 * Progressive enhancement: with JS off, all products still render (no filtering).
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

  // Fill the category chip on every card (and product page) with a pretty label.
  document.querySelectorAll(".vpc-cat[data-cat]").forEach(function (el) {
    var slug = el.getAttribute("data-cat");
    el.textContent = CAT_LABELS[slug] || slug;
  });

  var grid = document.getElementById("product-grid");
  if (!grid) return; // not on the home page

  var cards = Array.prototype.slice.call(grid.querySelectorAll(".vanta-product-card"));
  var pills = Array.prototype.slice.call(document.querySelectorAll(".cat-pill"));
  var sortSel = document.getElementById("sort");
  var countEl = document.getElementById("result-count");
  var emptyEl = document.getElementById("grid-empty");
  var originalOrder = cards.slice();
  var activeFilter = "all";

  function applyFilter() {
    var shown = 0;
    cards.forEach(function (card) {
      var match = activeFilter === "all" || card.getAttribute("data-category") === activeFilter;
      card.hidden = !match;
      if (match) shown++;
    });
    if (countEl) countEl.textContent = shown;
    if (emptyEl) emptyEl.hidden = shown !== 0;
  }

  function applySort() {
    var mode = sortSel ? sortSel.value : "featured";
    var arr = originalOrder.slice();
    if (mode === "price-asc") {
      arr.sort(function (a, b) { return price(a) - price(b); });
    } else if (mode === "price-desc") {
      arr.sort(function (a, b) { return price(b) - price(a); });
    } else if (mode === "name") {
      arr.sort(function (a, b) { return name(a).localeCompare(name(b)); });
    }
    arr.forEach(function (card) { grid.appendChild(card); });
  }

  function price(card) { return parseFloat(card.getAttribute("data-price")) || 0; }
  function name(card) { return card.getAttribute("data-name") || ""; }

  pills.forEach(function (pill) {
    pill.addEventListener("click", function () {
      pills.forEach(function (p) { p.classList.remove("active"); p.setAttribute("aria-selected", "false"); });
      pill.classList.add("active");
      pill.setAttribute("aria-selected", "true");
      activeFilter = pill.getAttribute("data-filter");
      applyFilter();
    });
  });

  if (sortSel) {
    sortSel.addEventListener("change", function () { applySort(); applyFilter(); });
  }

  applyFilter();
})();
