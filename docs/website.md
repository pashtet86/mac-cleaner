# machealthapps.com

Static site for Disk Cleaner: `index.html` (product page with the interactive disk map), `privacy.html`, and
Cloudflare Pages headers in `_headers`. No build step and no dependencies.

Preview: `python3 -m http.server 8000 --directory website` and open http://localhost:8000.

Deploy (Cloudflare Pages, once per change):

```sh
npx wrangler pages deploy website --project-name machealthapps
```

Each release: `scripts/release.sh <version>` uploads the DMG, `DiskCleaner.dmg` (latest) and the update feed to the
R2 bucket served at `downloads.machealthapps.com` (see README → Releasing an update). Then update the release block in
`index.html` (version, size, SHA-256 printed by the script).
