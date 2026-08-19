/* Ghana Buys — shared marketplace helpers, loaded by every page.
   TODO: replace these two placeholders with your actual Supabase project
   values (Project Settings → API → Project URL / anon public key). */
const SUPABASE_URL = 'https://YOUR-PROJECT-REF.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR-ANON-PUBLIC-KEY';

const sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

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

  return (
    '<a class="listing-card" href="/listing?id=' + l.id + '">' +
      '<div class="listing-thumb-wrap">' +
        '<div class="listing-thumb">' + img + '</div>' +
        soldBadge +
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
