Ghana Buys — flat static site (no folders, drag-and-drop friendly)
=====================================================================

Every file sits at the top level — no subfolders — so uploading via
GitHub's mobile "Add file" button (or any drag-and-drop uploader) works
in one pass with nothing getting lost.

Files:
  index.html          -> https://ghanabuys.com/
  phones.html         -> https://ghanabuys.com/phones
  stores.html         -> https://ghanabuys.com/stores
  powerbanks.html     -> https://ghanabuys.com/powerbanks
  clothes.html        -> https://ghanabuys.com/clothes
  databundles.html    -> https://ghanabuys.com/databundles
  privacy.html        -> https://ghanabuys.com/privacy
  methodology.html    -> https://ghanabuys.com/methodology
  style.css           (shared stylesheet, linked as /style.css)
  sitemap.xml
  robots.txt
  _redirects          (Netlify: maps /phones -> phones.html with no visible .html)
  vercel.json         (Vercel: same, via "cleanUrls": true)

Both config files are harmless to have side by side — each host only
reads the one it understands, so you don't need to pick.

How each guide gets a clean URL (e.g. /phones instead of /phones.html):
  - Netlify already does this automatically for any .html file, and
    _redirects makes it explicit as a backup.
  - Vercel needs vercel.json's "cleanUrls": true, which is included.

Deploying:
  1. Select ALL these files (README.txt is optional to include) and
     upload them to your GitHub repo root, or drag them straight into
     Netlify/Vercel's deploy UI. No folders to create.
  2. If ghanabuys.com isn't your real domain, find/replace it in:
     canonical tags, og:url tags, the JSON-LD "item" URLs in each
     guide page, and sitemap.xml.
  3. Submit sitemap.xml in Google Search Console once live.
