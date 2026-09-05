/*
 * VANTA — catalog interactions: category filter, live search, sort, "in stock
 * only", "New" badges, the wishlist, and the product-image lightbox.
 *
 * Wishlist storage: when the frontend is wired to wishlistservice
 * (<body data-wishlist="server">) the list lives server-side, keyed by the
 * shopper's session, and is mirrored into localStorage so the header count
 * paints instantly on the next page. Without the service it is localStorage
 * only. Progressive enhancement: with JS off, all products still render.
 */
(function () {
  "use strict";

  var CAT_LABELS = {
    "accessories": "Accessories", "apparel": "Apparel", "footwear": "Footwear",
    "home-kitchen": "Home & Kitchen", "beauty": "Beauty", "tech": "Tech"
  };
  var WISH_KEY = "vanta_wishlist";
  var baseUrl = document.body.getAttribute("data-base-url") || "";
  var serverWishlist = document.body.getAttribute("data-wishlist") === "server";
  var notify = function (msg, kind) { if (window.vantaToast) window.vantaToast(msg, kind); };

  // --- pretty category chips (home + product page) ---
  document.querySelectorAll(".vpc-cat[data-cat]").forEach(function (el) {
    var slug = el.getAttribute("data-cat");
    el.textContent = CAT_LABELS[slug] || slug;
  });

  // --- wishlist store ---
  function loadWish() {
    try { return new Set(JSON.parse(localStorage.getItem(WISH_KEY) || "[]")); }
    catch (e) { return new Set(); }
  }
  function saveWish(set) {
    try { localStorage.setItem(WISH_KEY, JSON.stringify(Array.from(set))); } catch (e) {}
  }
  var wish = loadWish();
  var wishButtons = [];

  function updateWishHeader() {
    var c = document.getElementById("wish-count");
    if (!c) return;
    if (wish.size > 0) { c.textContent = wish.size; c.hidden = false; }
    else { c.hidden = true; }
  }

  function paintAll() {
    wishButtons.forEach(function (btn) {
      var on = wish.has(btn.getAttribute("data-id"));
      btn.classList.toggle("is-saved", on);
      btn.setAttribute("aria-pressed", on ? "true" : "false");
    });
    updateWishHeader();
    if (typeof applyFilter === "function" && activeFilter === "__wishlist") applyFilter();
  }

  // Pull the authoritative list from the server once per page load.
  function syncFromServer() {
    if (!serverWishlist || !window.fetch) return;
    fetch(baseUrl + "/wishlist", { credentials: "same-origin", headers: { "Accept": "application/json" } })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (data) {
        if (!data || !Array.isArray(data.items)) return;
        wish = new Set(data.items.map(function (it) { return it.product_id; }));
        saveWish(wish);
        paintAll();
      })
      .catch(function () { /* keep the local mirror */ });
  }

  function toggleWish(id, name) {
    var wasSaved = wish.has(id);
    // optimistic update
    if (wasSaved) wish.delete(id); else wish.add(id);
    saveWish(wish); paintAll();
    notify(wasSaved ? "Removed from your saved items" : "Saved " + (name || "item") + " ♥", wasSaved ? "" : "ok");

    if (!serverWishlist || !window.fetch) return;
    fetch(baseUrl + "/wishlist/" + encodeURIComponent(id), {
      method: wasSaved ? "DELETE" : "POST",
      credentials: "same-origin",
      headers: { "Accept": "application/json" }
    })
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (data) {
        if (data && Array.isArray(data.items)) {
          wish = new Set(data.items.map(function (it) { return it.product_id; }));
          saveWish(wish); paintAll();
        }
      })
      .catch(function () {
        // roll back the optimistic change
        if (wasSaved) wish.add(id); else wish.delete(id);
        saveWish(wish); paintAll();
        notify("Couldn't update your wishlist — please try again", "err");
      });
  }

  document.querySelectorAll(".vpc-wish").forEach(function (btn) {
    wishButtons.push(btn);
    btn.addEventListener("click", function (e) {
      e.preventDefault(); e.stopPropagation();
      toggleWish(btn.getAttribute("data-id"), btn.getAttribute("data-name"));
    });
  });
  paintAll();
  syncFromServer();

  // --- product-image lightbox (product page) ---
  var pimg = document.querySelector(".product-image-container img");
  if (pimg) {
    pimg.classList.add("zoomable");
    pimg.addEventListener("click", function () {
      var ov = document.createElement("div");
      ov.className = "vanta-lightbox";
      ov.setAttribute("role", "dialog");
      ov.setAttribute("aria-label", pimg.alt || "Product image");
      var big = document.createElement("img");
      big.src = pimg.src; big.alt = pimg.alt;
      ov.appendChild(big);
      document.body.appendChild(ov);
      requestAnimationFrame(function () { ov.classList.add("open"); });
      function close() { ov.classList.remove("open"); setTimeout(function () { ov.remove(); }, 250); }
      ov.addEventListener("click", close);
      document.addEventListener("keydown", function esc(e) {
        if (e.key === "Escape") { close(); document.removeEventListener("keydown", esc); }
      });
    });
  }

  // --- home grid: filter / search / sort / in-stock ---
  var grid = document.getElementById("product-grid");
  if (!grid) return;

  var cards = Array.prototype.slice.call(grid.querySelectorAll(".vanta-product-card"));

  // "New" badge on freshly-added products (VNT* ids)
  cards.forEach(function (card) {
    if ((card.getAttribute("data-id") || "").indexOf("VNT") === 0) {
      var wrap = card.querySelector(".vpc-media-wrap");
      if (wrap && !wrap.querySelector(".vpc-badge-new")) {
        var b = document.createElement("span");
        b.className = "vpc-badge-new"; b.textContent = "New";
        wrap.appendChild(b);
      }
    }
  });

  var pills = Array.prototype.slice.call(document.querySelectorAll(".cat-pill"));
  var sortSel = document.getElementById("sort");
  var searchEl = document.getElementById("search");
  var inStockEl = document.getElementById("instock");
  var countEl = document.getElementById("result-count");
  var emptyEl = document.getElementById("grid-empty");
  var originalOrder = cards.slice();
  var activeFilter = "all";
  var term = "";
  var inStockOnly = false;

  function applyFilter() {
    var shown = 0;
    cards.forEach(function (card) {
      var nameOk = !term || (card.getAttribute("data-name") || "").toLowerCase().indexOf(term) !== -1;
      var stockOk = !inStockOnly || card.getAttribute("data-stock") !== "out";
      var catOk;
      if (activeFilter === "__wishlist") catOk = wish.has(card.getAttribute("data-id"));
      else catOk = activeFilter === "all" || card.getAttribute("data-category") === activeFilter;
      var match = catOk && nameOk && stockOk;
      card.hidden = !match;
      if (match) shown++;
    });
    if (countEl) countEl.textContent = shown;
    if (emptyEl) {
      emptyEl.hidden = shown !== 0;
      emptyEl.textContent = activeFilter === "__wishlist"
        ? "No saved items yet — tap the ♥ on any product."
        : "No products match your search.";
    }
  }

  function price(card) { return parseFloat(card.getAttribute("data-price")) || 0; }
  function nameOf(card) { return card.getAttribute("data-name") || ""; }

  function applySort() {
    var mode = sortSel ? sortSel.value : "featured";
    var arr = originalOrder.slice();
    if (mode === "price-asc") arr.sort(function (a, b) { return price(a) - price(b); });
    else if (mode === "price-desc") arr.sort(function (a, b) { return price(b) - price(a); });
    else if (mode === "name") arr.sort(function (a, b) { return nameOf(a).localeCompare(nameOf(b)); });
    arr.forEach(function (card) { grid.appendChild(card); });
  }

  function activate(pill) {
    pills.forEach(function (p) { p.classList.remove("active"); p.setAttribute("aria-selected", "false"); });
    pill.classList.add("active"); pill.setAttribute("aria-selected", "true");
    activeFilter = pill.getAttribute("data-filter");
    applyFilter();
  }

  pills.forEach(function (pill) {
    pill.addEventListener("click", function () { activate(pill); });
  });
  if (sortSel) sortSel.addEventListener("change", function () { applySort(); applyFilter(); });
  if (searchEl) searchEl.addEventListener("input", function () { term = searchEl.value.trim().toLowerCase(); applyFilter(); });
  if (inStockEl) inStockEl.addEventListener("change", function () { inStockOnly = inStockEl.checked; applyFilter(); });

  // Saved view: opens on /#wishlist (initial load, on hash change, and when the
  // header ♥ is clicked while already on the home page).
  function openWishlist() {
    var wp = document.querySelector('.cat-pill[data-filter="__wishlist"]');
    if (!wp) return;
    activate(wp);
    var sec = document.getElementById("products");
    if (sec) sec.scrollIntoView({ behavior: "smooth", block: "start" });
  }
  window.addEventListener("hashchange", function () {
    if (location.hash === "#wishlist") openWishlist();
  });
  var wishHeader = document.getElementById("wish-header");
  if (wishHeader) wishHeader.addEventListener("click", function () { setTimeout(openWishlist, 30); });
  if (location.hash === "#wishlist") openWishlist();

  applyFilter();
})();
