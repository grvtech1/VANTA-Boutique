/* =============================================================================
 * VANTA — Micro-Animations & Interactions
 * ============================================================================= */

(function() {
  'use strict';

  // --- Scroll-triggered fade-in animations ---
  const observerOptions = {
    threshold: 0.1,
    rootMargin: '0px 0px -50px 0px'
  };

  const observer = new IntersectionObserver(function(entries) {
    entries.forEach(function(entry) {
      if (entry.isIntersecting) {
        entry.target.classList.add('visible');
        observer.unobserve(entry.target);
      }
    });
  }, observerOptions);

  // Observe all fade-in elements
  document.querySelectorAll('.fade-in-up').forEach(function(el) {
    observer.observe(el);
  });

  // --- Navbar scroll effect ---
  var header = document.querySelector('header');
  var lastScroll = 0;

  if (header) {
    window.addEventListener('scroll', function() {
      var currentScroll = window.pageYOffset;
      if (currentScroll > 100) {
        header.style.background = 'rgba(10, 10, 15, 0.95)';
      } else {
        header.style.background = 'rgba(10, 10, 15, 0.85)';
      }
      lastScroll = currentScroll;
    }, { passive: true });
  }

  // --- Smooth scroll for anchor links ---
  document.querySelectorAll('a[href^="#"]').forEach(function(anchor) {
    anchor.addEventListener('click', function(e) {
      e.preventDefault();
      var target = document.querySelector(this.getAttribute('href'));
      if (target) {
        target.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }
    });
  });

  // --- Product card hover effect enhancement ---
  document.querySelectorAll('.hot-product-card').forEach(function(card) {
    card.addEventListener('mouseenter', function() {
      this.style.transition = 'all 0.3s cubic-bezier(0.16, 1, 0.3, 1)';
    });
  });

  // --- Order page confetti ---
  if (document.querySelector('.order-page')) {
    createConfetti();
  }

  function createConfetti() {
    var container = document.createElement('div');
    container.className = 'confetti-container';
    document.body.appendChild(container);

    var colors = ['#6c5ce7', '#a29bfe', '#00cec9', '#ff6b6b', '#fdcb6e', '#00b894'];

    for (var i = 0; i < 50; i++) {
      var confetti = document.createElement('div');
      confetti.className = 'confetti';
      confetti.style.left = Math.random() * 100 + '%';
      confetti.style.backgroundColor = colors[Math.floor(Math.random() * colors.length)];
      confetti.style.animationDelay = Math.random() * 2 + 's';
      confetti.style.animationDuration = (Math.random() * 2 + 2) + 's';
      confetti.style.width = (Math.random() * 8 + 4) + 'px';
      confetti.style.height = (Math.random() * 8 + 4) + 'px';
      container.appendChild(confetti);
    }

    setTimeout(function() {
      container.remove();
    }, 5000);
  }

})();
