/* Ghana Buys — shared marketplace helpers, loaded by every page.
   TODO: replace these two placeholders with your actual Supabase project
   values (Project Settings → API → Project URL / anon public key). */
const SUPABASE_URL = 'https://wstjabsjsxwbkbiouyug.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndzdGphYnNqc3h3YmtiaW91eXVnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcwMDA1NzksImV4cCI6MjEwMjU3NjU3OX0.EMJztYqk969nlAxW6bygMKB0FfHG6rRdBhvOjJ-qEWk';

const sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

/* Paystack — public/test key only, safe to expose client-side.
   Get this from Paystack dashboard -> Settings -> API Keys (pk_test_... or pk_live_...) */
const PAYSTACK_PUBLIC_KEY = 'pk_test_0966980bbd23d49dc4e263d5640edd2c98c6396d';

// Generic caller for our Paystack-backed edge functions (feature-listing,
// store-subscription, etc). Each holds the Paystack SECRET key server-side
// and does the real verification — never trust a client-side "success" signal alone.
async function callPaidFeatureFn(fnName, action, payload) {
  const { data: { session } } = await sb.auth.getSession();
  if (!session) throw new Error('Not logged in');
  const res = await fetch(SUPABASE_URL + '/functions/v1/' + fnName, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + session.access_token
    },
    body: JSON.stringify(Object.assign({ action: action }, payload))
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || 'Request failed');
  return data;
}

// Opens the Paystack popup, then verifies with the server before resolving.
// Requires https://js.paystack.co/v1/inline.js loaded on the page.
function startPaidFeatureCheckout(fnName, payload, onSuccess, onError) {
  callPaidFeatureFn(fnName, 'initialize', payload)
    .then(function (init) {
      const handler = PaystackPop.setup({
        key: PAYSTACK_PUBLIC_KEY,
        email: init.email,
        amount: init.amount,
        currency: 'GHS',
        ref: init.reference,
        callback: function () {
          callPaidFeatureFn(fnName, 'verify', { reference: init.reference })
            .then(function (result) { onSuccess(result); })
            .catch(function (err) { onError(err); });
        },
        onClose: function () {}
      });
      handler.openIframe();
    })
    .catch(function (err) { onError(err); });
}

function startFeatureListingCheckout(listingId, onSuccess, onError) {
  startPaidFeatureCheckout('feature-listing', { listing_id: listingId }, onSuccess, onError);
}

function startStoreSubscriptionCheckout(onSuccess, onError) {
  startPaidFeatureCheckout('store-subscription', {}, onSuccess, onError);
}

// Buyer-pays-seller checkout, routed via Paystack subaccount split so the
// money settles directly with the seller — Ghana Buys never holds it.
async function callPayListingFn(action, payload) {
  const { data: { session } } = await sb.auth.getSession();
  if (!session) throw new Error('Not logged in');
  const res = await fetch(SUPABASE_URL + '/functions/v1/pay-listing', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + session.access_token
    },
    body: JSON.stringify(Object.assign({ action: action }, payload))
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || 'Request failed');
  return data;
}

function startListingPaymentCheckout(listingId, onSuccess, onError) {
  callPayListingFn('initialize', { listing_id: listingId })
    .then(function (init) {
      const handler = PaystackPop.setup({
        key: PAYSTACK_PUBLIC_KEY,
        email: init.email,
        amount: init.amount,
        currency: 'GHS',
        ref: init.reference,
        subaccount: init.subaccount,
        callback: function () {
          callPayListingFn('verify', { reference: init.reference })
            .then(function (result) { onSuccess(result); })
            .catch(function (err) { onError(err); });
        },
        onClose: function () {}
      });
      handler.openIframe();
    })
    .catch(function (err) { onError(err); });
}

const CATEGORIES = [
  'Phones & Electronics',
  'Fashion',
  'Home & Living',
  'Vehicles',
  'Property',
  'Services',
  'Data & Connectivity',
  'Other'
];

function escapeHtml(str) {
  return String(str == null ? '' : str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

function formatPrice(price) {
  if (price === null || price === undefined || price === '') return 'Price on request';
  const n = Number(price);
  if (Number.isNaN(n)) return 'Price on request';
  return '₵' + n.toLocaleString('en-GH');
}

function formatDate(dateStr) {
  if (!dateStr) return '';
  const d = new Date(dateStr);
  const diffMs = Date.now() - d.getTime();
  const diffDays = Math.floor(diffMs / 86400000);
  if (diffDays <= 0) return 'today';
  if (diffDays === 1) return 'yesterday';
  if (diffDays < 7) return diffDays + ' days ago';
  if (diffDays < 30) return Math.floor(diffDays / 7) + (Math.floor(diffDays / 7) === 1 ? ' week ago' : ' weeks ago');
  return d.toLocaleDateString('en-GH', { day: 'numeric', month: 'short', year: 'numeric' });
}

// Normalizes Ghanaian numbers (e.g. "024 123 4567" or "+233 24 123 4567") to
// wa.me's expected format and builds a click-to-chat link with a prefilled message.
function whatsappLink(phone, message) {
  let digits = String(phone || '').replace(/\D/g, '');
  if (digits.startsWith('0')) digits = '233' + digits.slice(1);
  else if (!digits.startsWith('233')) digits = '233' + digits;
  return 'https://wa.me/' + digits + '?text=' + encodeURIComponent(message || '');
}

// Self-contained inline SVG — does NOT rely on the <symbol> sprite that only
// index.html and the guide pages define, so it renders correctly on every
// page (including marketplace/listing/post/account, which don't have it).
function placeholderIconSVG() {
  return '<svg class="icon" viewBox="0 0 24 24" width="36" height="36" fill="none" ' +
    'stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' +
    '<rect x="3.5" y="7" width="17" height="13" rx="2"></rect>' +
    '<path d="M8 7V5.5A2.5 2.5 0 0 1 10.5 3h3A2.5 2.5 0 0 1 16 5.5V7"></path>' +
    '</svg>';
}

function listingCardHTML(l) {
  const img = l.image_url
    ? '<img src="' + escapeHtml(l.image_url) + '" alt="' + escapeHtml(l.title) + '">'
    : placeholderIconSVG();
  const soldBadge = l.status === 'sold' ? '<span class="listing-sold-badge">Sold</span>' : '';
  const isFeatured = l.featured && l.featured_until && new Date(l.featured_until) > new Date();
  const featuredBadge = isFeatured ? '<span class="listing-featured-badge">★ Featured</span>' : '';

  return (
    '<a class="listing-card" href="/listing?id=' + l.id + '">' +
      '<div class="listing-thumb-wrap">' +
        '<div class="listing-thumb">' + img + '</div>' +
        soldBadge + featuredBadge +
        '<button type="button" class="save-btn" data-id="' + l.id + '" aria-label="Add to cart">' +
          '<svg viewBox="0 0 24 24" width="18" height="18"><circle cx="9" cy="20" r="1.4"/><circle cx="18" cy="20" r="1.4"/><path d="M2.5 3h2.4l1.1 3M5.9 6l1.9 8.6a1.6 1.6 0 0 0 1.6 1.3h7.6a1.6 1.6 0 0 0 1.6-1.3L20.5 6H5.9z"/></svg>' +
        '</button>' +
      '</div>' +
      '<div class="listing-body">' +
        '<span class="listing-price">' + formatPrice(l.price) + '</span>' +
        '<h3>' + escapeHtml(l.title) + '</h3>' +
        '<div class="listing-meta">' +
          '<span>' + escapeHtml(l.category) + '</span>' +
          (l.location ? '<span>📍 ' + escapeHtml(l.location) + '</span>' : '') +
        '</div>' +
      '</div>' +
    '</a>'
  );
}

// Marks every .save-btn currently in the DOM whose listing is already saved
// by the signed-in viewer. Safe to call repeatedly (e.g. after each render);
// no-ops quietly if the viewer isn't logged in.
async function refreshSavedButtons() {
  const buttons = document.querySelectorAll('.save-btn');
  if (!buttons.length) return;
  const { data: { session } } = await sb.auth.getSession();
  if (!session) return;

  const { data, error } = await sb.from('saved_listings').select('listing_id').eq('user_id', session.user.id);
  if (error || !data) return;
  const savedIds = new Set(data.map(function (r) { return r.listing_id; }));
  buttons.forEach(function (btn) {
    btn.classList.toggle('saved', savedIds.has(btn.dataset.id));
  });
}

async function toggleSaveListing(id, btn) {
  const { data: { session } } = await sb.auth.getSession();
  if (!session) {
    window.location.href = '/account?next=' + encodeURIComponent(location.pathname + location.search);
    return;
  }

  const alreadySaved = btn.classList.contains('saved');
  btn.disabled = true;
  if (alreadySaved) {
    await sb.from('saved_listings').delete().eq('user_id', session.user.id).eq('listing_id', id);
    btn.classList.remove('saved');
  } else {
    await sb.from('saved_listings').insert({ user_id: session.user.id, listing_id: id });
    btn.classList.add('saved');
  }
  btn.disabled = false;
}

// Delegated so it works for cards rendered anywhere, at any time.
document.addEventListener('click', function (e) {
  const btn = e.target.closest('.save-btn');
  if (!btn) return;
  e.preventDefault();
  e.stopPropagation();
  toggleSaveListing(btn.dataset.id, btn);
});

// Keeps the "Log in" / "My Account" nav link in sync with auth state on every page.
(async function initNavAccountLink() {
  const link = document.getElementById('navAccountLink');
  if (!link) return;

  function applySession(session) {
    if (session && session.user) {
      link.textContent = 'My Account';
    } else {
      link.textContent = 'Log in';
    }
  }

  try {
    const { data: { session } } = await sb.auth.getSession();
    applySession(session);
  } catch (err) {
    // leave default "Log in" if the session check fails
  }

  sb.auth.onAuthStateChange(function (_event, session) {
    applySession(session);
  });
})();
