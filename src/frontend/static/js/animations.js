/* =============================================================================
 * VANTA — motion & micro-interactions
 *
 * Everything here is progressive enhancement: the storefront works with this
 * file missing. Honors prefers-reduced-motion (no reveals, no parallax).
 * ============================================================================= */

(function () {
  'use strict';

  var reduceMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var raf = window.requestAnimationFrame || function (f) { return setTimeout(f, 16); };

  // ---------------------------------------------------------------------------
  // Toasts — small, non-blocking confirmations ("Saved to wishlist").
  // Exposed as window.vantaToast(message, kind) for catalog.js.
  // ---------------------------------------------------------------------------
  var toastHost = null;
  function toast(message, kind) {
    if (!toastHost) {
      toastHost = document.createElement('div');
      toastHost.className = 'vanta-toasts';
      toastHost.setAttribute('aria-live', 'polite');
      document.body.appendChild(toastHost);
    }
    var el = document.createElement('div');
    el.className = 'vanta-toast' + (kind ? ' vanta-toast-' + kind : '');
    el.textContent = message;
    toastHost.appendChild(el);
    raf(function () { el.classList.add('show'); });
    setTimeout(function () {
      el.classList.remove('show');
      setTimeout(function () { el.remove(); }, 300);
    }, 2400);
  }
  window.vantaToast = toast;

  // ---------------------------------------------------------------------------
  // Scroll reveal — cards and sections fade/slide in once, with a stagger.
  // ---------------------------------------------------------------------------
  var revealTargets = document.querySelectorAll('[data-reveal], .vanta-product-card, .review-card, .recommendation-card');
  if (reduceMotion || !('IntersectionObserver' in window)) {
    revealTargets.forEach(function (el) { el.classList.add('is-visible'); });
  } else {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        entry.target.classList.add('is-visible');
        io.unobserve(entry.target);
      });
    }, { threshold: 0.08, rootMargin: '0px 0px -40px 0px' });
    revealTargets.forEach(function (el, i) {
      el.classList.add('reveal');
      // stagger by position in its row; cap so late cards don't lag
      el.style.setProperty('--reveal-delay', (Math.min(i % 8, 7) * 45) + 'ms');
      io.observe(el);
    });
  }

  // ---------------------------------------------------------------------------
  // Header — compact + stronger blur once the page scrolls.
  // ---------------------------------------------------------------------------
  var header = document.querySelector('header');
  if (header) {
    var ticking = false;
    var onScroll = function () {
      if (ticking) return;
      ticking = true;
      raf(function () {
        header.classList.toggle('is-scrolled', window.pageYOffset > 24);
        ticking = false;
      });
    };
    window.addEventListener('scroll', onScroll, { passive: true });
    onScroll();
  }

  // ---------------------------------------------------------------------------
  // Hero parallax — the banner image drifts slower than the page.
  // ---------------------------------------------------------------------------
  var hero = document.querySelector('.hero-banner img');
  if (hero && !reduceMotion) {
    var heroTick = false;
    window.addEventListener('scroll', function () {
      if (heroTick) return;
      heroTick = true;
      raf(function () {
        var y = Math.min(window.pageYOffset, 600);
        hero.style.transform = 'translate3d(0,' + (y * 0.25) + 'px,0) scale(1.08)';
        heroTick = false;
      });
    }, { passive: true });
  }

  // ---------------------------------------------------------------------------
  // Images — blur-up: cards start soft and sharpen when the image has loaded.
  // ---------------------------------------------------------------------------
  document.querySelectorAll('.vpc-media img, .product-image-container img, .recommendation-card img').forEach(function (img) {
    var done = function () { img.classList.add('is-loaded'); };
    if (img.complete && img.naturalWidth > 0) done();
    else { img.addEventListener('load', done); img.addEventListener('error', done); }
  });

  // ---------------------------------------------------------------------------
  // Product page — hover zoom lens (mouse only; touch keeps the tap-to-lightbox).
  // ---------------------------------------------------------------------------
  var stage = document.querySelector('.product-image-container');
  var stageImg = stage && stage.querySelector('img');
  var finePointer = window.matchMedia && window.matchMedia('(hover: hover) and (pointer: fine)').matches;
  if (stage && stageImg && finePointer && !reduceMotion) {
    stage.classList.add('has-lens');
    stage.addEventListener('mousemove', function (e) {
      var r = stage.getBoundingClientRect();
      var x = ((e.clientX - r.left) / r.width) * 100;
      var y = ((e.clientY - r.top) / r.height) * 100;
      stageImg.style.transformOrigin = x + '% ' + y + '%';
    });
    stage.addEventListener('mouseleave', function () {
      stageImg.style.transformOrigin = '50% 50%';
    });
  }

  // ---------------------------------------------------------------------------
  // Quantity stepper — the − / + buttons drive the hidden form field.
  // ---------------------------------------------------------------------------
  document.querySelectorAll('.qty-stepper').forEach(function (box) {
    var input = box.querySelector('input[name="quantity"]');
    var out = box.querySelector('.qty-value');
    var min = parseInt(box.getAttribute('data-min') || '1', 10);
    var max = parseInt(box.getAttribute('data-max') || '10', 10);
    function set(v) {
      v = Math.max(min, Math.min(max, v));
      input.value = v; out.textContent = v;
      box.querySelector('[data-step="-1"]').disabled = v <= min;
      box.querySelector('[data-step="1"]').disabled = v >= max;
    }
    box.querySelectorAll('[data-step]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        set(parseInt(input.value, 10) + parseInt(btn.getAttribute('data-step'), 10));
      });
    });
    set(parseInt(input.value, 10) || min);
  });

  // ---------------------------------------------------------------------------
  // Add to cart — press feedback while the form submits.
  // ---------------------------------------------------------------------------
  document.querySelectorAll('form[action$="/cart"] button[type="submit"]').forEach(function (btn) {
    btn.closest('form').addEventListener('submit', function () {
      btn.classList.add('is-busy');
      btn.setAttribute('aria-busy', 'true');
    });
  });

  // ---------------------------------------------------------------------------
  // Reviews — sort, live character count, "helpful" votes (kept per browser).
  // ---------------------------------------------------------------------------
  var reviewsList = document.querySelector('.reviews-list');
  var reviewSort = document.getElementById('review-sort');
  if (reviewsList && reviewSort) {
    var items = Array.prototype.slice.call(reviewsList.children);
    var original = items.slice();
    reviewSort.addEventListener('change', function () {
      var mode = reviewSort.value;
      var arr = original.slice();
      var rating = function (li) { return parseInt(li.getAttribute('data-rating') || '0', 10); };
      var when = function (li) { return parseInt(li.getAttribute('data-when') || '0', 10); };
      if (mode === 'highest') arr.sort(function (a, b) { return rating(b) - rating(a) || when(b) - when(a); });
      else if (mode === 'lowest') arr.sort(function (a, b) { return rating(a) - rating(b) || when(b) - when(a); });
      else arr.sort(function (a, b) { return when(b) - when(a); });
      arr.forEach(function (li) { reviewsList.appendChild(li); });
    });
  }

  var comment = document.getElementById('review-comment');
  var counter = document.getElementById('review-comment-count');
  if (comment && counter) {
    var max = parseInt(comment.getAttribute('maxlength') || '1000', 10);
    var update = function () { counter.textContent = comment.value.length + ' / ' + max; };
    comment.addEventListener('input', update);
    update();
  }

  var HELPFUL_KEY = 'vanta_helpful';
  var helpful = {};
  try { helpful = JSON.parse(localStorage.getItem(HELPFUL_KEY) || '{}'); } catch (e) { helpful = {}; }
  document.querySelectorAll('.review-helpful').forEach(function (btn) {
    var id = btn.getAttribute('data-review');
    var count = btn.querySelector('.review-helpful-count');
    var base = parseInt(count.textContent, 10) || 0;
    if (helpful[id]) { btn.classList.add('is-on'); count.textContent = base + 1; }
    btn.addEventListener('click', function () {
      var on = !helpful[id];
      if (on) helpful[id] = 1; else delete helpful[id];
      try { localStorage.setItem(HELPFUL_KEY, JSON.stringify(helpful)); } catch (e) {}
      btn.classList.toggle('is-on', on);
      count.textContent = base + (on ? 1 : 0);
    });
  });

  // Star picker: keep the label text in sync with the chosen rating.
  var picker = document.querySelector('.star-picker');
  var pickerLabel = document.getElementById('star-picker-label');
  if (picker && pickerLabel) {
    var words = { 5: 'Excellent', 4: 'Good', 3: 'Average', 2: 'Poor', 1: 'Bad' };
    picker.addEventListener('change', function (e) {
      if (e.target && e.target.name === 'rating') pickerLabel.textContent = words[e.target.value] || '';
    });
  }

  // ---------------------------------------------------------------------------
  // Order page — confetti.
  // ---------------------------------------------------------------------------
  if (document.querySelector('.order-page') && !reduceMotion) {
    var host = document.createElement('div');
    host.className = 'confetti-container';
    document.body.appendChild(host);
    var colors = ['#6c5ce7', '#a29bfe', '#00cec9', '#ff6b6b', '#fdcb6e', '#00b894'];
    for (var i = 0; i < 50; i++) {
      var c = document.createElement('div');
      c.className = 'confetti';
      c.style.left = Math.random() * 100 + '%';
      c.style.backgroundColor = colors[Math.floor(Math.random() * colors.length)];
      c.style.animationDelay = Math.random() * 2 + 's';
      c.style.animationDuration = (Math.random() * 2 + 2) + 's';
      c.style.width = (Math.random() * 8 + 4) + 'px';
      c.style.height = (Math.random() * 8 + 4) + 'px';
      host.appendChild(c);
    }
    setTimeout(function () { host.remove(); }, 5000);
  }
})();
