Ghana Buys — flat static site + marketplace (no folders, drag-and-drop friendly)
=====================================================================

Every file sits at the top level — no subfolders — so uploading via
GitHub's mobile "Add file" button (or any drag-and-drop uploader) works
in one pass with nothing getting lost.

Pages:
  index.html           -> https://ghanabuys.com/            (marketplace home)
  marketplace.html      -> https://ghanabuys.com/marketplace  (browse/search listings)
  listing.html          -> https://ghanabuys.com/listing      (single listing, ?id=...)
  post.html             -> https://ghanabuys.com/post         (post/edit a listing, login required)
  account.html          -> https://ghanabuys.com/account      (log in / sign up / my listings)
  phones.html           -> https://ghanabuys.com/phones
  stores.html           -> https://ghanabuys.com/stores
  powerbanks.html       -> https://ghanabuys.com/powerbanks
  clothes.html          -> https://ghanabuys.com/clothes
  databundles.html      -> https://ghanabuys.com/databundles
  privacy.html          -> https://ghanabuys.com/privacy
  methodology.html      -> https://ghanabuys.com/methodology

Shared files:
  style.css             (all styling, linked as /style.css)
  marketplace.js        (Supabase client + shared helpers, linked as /marketplace.js
                          — used by every page for the "Log in / My Account" nav link,
                          and by the marketplace pages for listings)
  logo-icon.png         (nav logo mark, linked as /logo-icon.png)
  favicon.png           (browser tab icon, linked as /favicon.png)
  sitemap.xml
  robots.txt

Not a page — run this once, don't deploy it:
  supabase-setup.sql    (creates the `listings` table, security rules, and the
                          image storage bucket in your Supabase project)

=====================================================================
ONE-TIME MARKETPLACE SETUP (do this before the "Sell" button works)
=====================================================================

The marketplace reuses the same Supabase project already wired up for
the newsletter (URL + anon key are in marketplace.js). You just need to
add the marketplace's own table, security rules, and storage bucket:

  1. Open your Supabase project → SQL Editor → New query.
  2. Paste in the entire contents of supabase-setup.sql and click Run.
     This creates the `listings` table, locks it down so people can only
     edit their own listings, and sets up a public image bucket.
  3. Go to Authentication → Settings and check "Confirm email":
       - ON  (default): new users must click a link in their email
         before they can log in and post.
       - OFF: signup → posting works immediately, no email step.
     Either is fine — OFF is friendlier if you want zero-friction signup.

That's it — Log in, Sign up, Post an Item, and My Listings will all work
once that SQL has run.

=====================================================================

Deploying:
  1. Select ALL these files (README.txt and supabase-setup.sql are not
     needed on the live site, but are harmless to include) and upload
     them to your GitHub repo root, or drag them into Netlify/Vercel's
     deploy UI. No folders to create.
  2. If ghanabuys.com isn't your real domain, find/replace it in:
     canonical tags, og:url tags, the JSON-LD "item" URLs in each
     guide page, and sitemap.xml.
  3. Run the Supabase setup above.
  4. Submit sitemap.xml in Google Search Console once live.

Note on URLs: Netlify and Vercel both serve clean URLs (e.g. /phones
instead of /phones.html) automatically for flat .html files — no extra
config file needed for that. listing.html reads the item via a query
string (/listing?id=...), which works the same way on both hosts.
