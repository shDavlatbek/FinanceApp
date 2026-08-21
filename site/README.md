# tally-site

The public face Google's OAuth consent screen links to: a home page, a privacy
policy and terms of service. Three static HTML files, one stylesheet, and the
Manrope font the app uses.

No build step, no JavaScript, no cookies, and nothing loaded from a third
party — the font is served from this domain rather than from a font service,
because a privacy page that phones someone else to render itself is not one.

## Deploy

Upload the contents of this folder to the web root. That is the whole process
on nginx, Caddy, Netlify, Vercel, Cloudflare Pages or GitHub Pages.

```
index.html      home page
privacy.html    privacy policy
terms.html      terms of service
style.css
fonts/          Manrope (SIL Open Font License, see fonts/OFL.txt)
```

Preview it locally with `python3 -m http.server` and open
<http://localhost:8000>.

## Where each URL goes in Google Cloud Console

**APIs & Services → OAuth consent screen → Branding**, assuming the site is at
`https://wapp.uz`:

| Field | Value |
|---|---|
| Application home page | `https://wapp.uz/` |
| Application privacy policy link | `https://wapp.uz/privacy.html` |
| Application terms of service link | `https://wapp.uz/terms.html` |
| Authorized domains → **+ Add domain** | `wapp.uz` |

Notes that trip people up:

- **All three must be HTTPS**, and on the domain listed under Authorized
  domains (or a subdomain of it). Google rejects them otherwise.
- Add the **authorized domain first**; the three link fields are validated
  against it.
- If Google asks you to verify ownership, do it in
  [Search Console](https://search.google.com/search-console) with the same
  account that owns the Cloud project.
- If your host serves extensionless URLs, `https://wapp.uz/privacy` works too —
  use whichever form actually resolves, and check it in a private window before
  pasting it into the console.

## Before you publish

- **The two email addresses are placeholders**: `privacy@wapp.uz` in
  `privacy.html` and `hello@wapp.uz` in `terms.html`. Point them at a mailbox
  you actually read — Google's reviewers and your users both use them.
- **The effective date** on both pages is 21 August 2026. Change it when you
  change the text.
- The pages describe Tally as it is built today: one `drive.file` scope, no
  analytics, no server operated by the authors. If that stops being true, these
  pages have to change with it.
