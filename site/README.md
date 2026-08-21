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

## Passing Google's brand verification

Publishing an OAuth consent screen — even with a non-sensitive scope like
`drive.file` — puts it through **brand verification**. The rules are in Google's
own docs, and every item below is one of them:

- [App homepage requirements](https://support.google.com/cloud/answer/13807376)
- [App identity and branding](https://support.google.com/cloud/answer/13804963)

### What Google requires of the home page

Verbatim from the first doc, the home page must:

1. Accurately represent and identify your app or brand
2. Fully describe your app's functionality to users
3. Explain with transparency the purpose for which your app requests user data
4. Be hosted on a **verified domain you own**
5. Not live on a platform whose subdomain ownership cannot be verified
   (Google Sites, Facebook, Instagram, Twitter)
6. **Include a link to your privacy policy — and that link must match the link
   configured on the consent screen**
7. Be visible without requiring a login

and the URLs must be **static, without redirects**.

Items 1–3 and 7 are what `index.html` is built around: it opens with the app
name, states in one sentence what Tally is, lists what it does, and has a
**Why Tally asks for access to Google Drive** section that names the scope and
walks through what it does with it. Keep all of that if you edit the page.

### The redirect trap (this one has already failed a review)

Your host serves clean URLs and **307-redirects the `.html` ones**:

```
https://tally.wapp.uz/privacy        200, 0 redirects   ← canonical
https://tally.wapp.uz/privacy.html   307 → /privacy     ← redirects
```

So `/privacy` and `/terms` are the only forms that satisfy "static without
redirects", and requirement 6 means the **link in the page and the value in the
console must be the same one**. Every link in this site now points at `/`,
`/privacy` and `/terms` for exactly that reason — do not change them back to
`.html`, and do not put the `.html` forms in the console.

(The trade-off: `python3 -m http.server` does not do clean URLs, so those links
404 in a naive local preview. Preview with something that rewrites, or just
open the `.html` files directly.)

### What Google requires of the name and logo

From the second doc: the app name and logo on the consent screen must match
your verification submission, must be accurate and up to date, must **uniquely
identify your brand**, and must not impersonate another brand.

- **Logo.** The consent screen carried a green seedling while the app and this
  site use a lime **T**. `tally-logo-120.png` is that mark at the 120×120 PNG
  the console wants — upload it under **Branding → Change logo**. The site
  header now renders that same file, so the two are byte-identical.
- **Name.** Worth a thought if the next submission fails the same way:
  "Tally" is a common English word and also the name of a large existing
  accounting-software brand (Tally Solutions / TallyPrime). Google requires the
  name to *uniquely identify your brand*. If reviewers keep objecting to the
  name, making it distinctive — a compound, or a word that is not already an
  accounting product — removes the ambiguity in a way no amount of page copy
  can.

### Which URL goes in which field

| Field | Value |
|---|---|
| Application home page | `https://tally.wapp.uz/` |
| Application privacy policy link | `https://tally.wapp.uz/privacy` |
| Application terms of service link | `https://tally.wapp.uz/terms` |
| Authorized domains | `wapp.uz` |

All three must be HTTPS, publicly reachable without a login, and — per
requirement 6 — the privacy link must be **character-for-character** what the
home page links to.

### Fix the 502 on the authorized domain

`https://wapp.uz/` returns **502 Bad Gateway**. That is the domain you verified
ownership of, so a reviewer who trims the URL to check the site is really yours
lands on a broken server. Serve something there — the same site, or a redirect
to `https://tally.wapp.uz/`.

### Before you resubmit

1. **Deploy, then purge the Cloudflare cache.** Responses come back
   `cf-cache-status: HIT`; a reviewer served a stale copy fails you for a page
   you already fixed.
2. Confirm what the edge actually serves, and that nothing redirects:
   ```bash
   curl -s https://tally.wapp.uz/ | grep -o '<h1>[^<]*</h1>'     # <h1>Tally</h1>
   curl -s -o /dev/null -w '%{http_code} %{num_redirects}\n' https://tally.wapp.uz/privacy   # 200 0
   ```
3. Open all three URLs in a private window and read them as a stranger would.
4. Only then **resubmit** — Google does not re-run the check on its own, and
   resubmitting before the deploy is live burns a round trip.

## Before you publish

- **The two email addresses are placeholders**: `privacy@wapp.uz` in
  `privacy.html` and `hello@wapp.uz` in `terms.html`. Point them at a mailbox
  you actually read — Google's reviewers and your users both use them.
- **The effective date** on both policy pages is 21 August 2026. Change it when
  you change the text.
- **Consider linking the source.** Reviewers like being able to see the app.
  If the repository is public, add a link in the "Getting Tally" section:
  `<p><a href="https://github.com/you/tally">Source code on GitHub</a></p>`.
- The pages describe Tally as it is built today: one `drive.file` scope, no
  analytics, no server operated by the authors. If that stops being true, these
  pages have to change with it.
