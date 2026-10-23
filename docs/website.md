# machealthapps.com

Static site for Disk Cleaner: `index.html` (product page with the interactive disk map), `privacy.html`, and
Cloudflare Pages headers in `_headers`. No build step and no dependencies.

Preview: `python3 -m http.server 8000 --directory website` and open http://localhost:8000.

Deploy (Cloudflare Pages, once per change):

```sh
npx wrangler pages deploy website --project-name machealthapps
```

Each release: upload the DMG to the R2 bucket served at `downloads.machealthapps.com`, then update the release block
in `index.html` (version, file name, SHA-256 printed by `make dmg-signed`).
