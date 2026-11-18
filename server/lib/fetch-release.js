// Runs as the Vercel build step. Copies the app (APK) and its version.json
// from the newest GitHub Release into public/ and puts its version on the
// download page, so the download page and the
// in-app update serve them from this site. The APK is not kept in git.
//
// Fails the build (and Vercel keeps the site that is live) if either file
// cannot be fetched or the APK does not match its fingerprint.

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const repo = process.env.RELEASE_REPO || 'RamSoft-by-RVPL/iimm-buddy';
const base = `https://github.com/${repo}/releases/latest/download`;
const out = path.join(__dirname, '..', 'public');

async function get(name) {
  for (let attempt = 1; ; attempt++) {
    try {
      const r = await fetch(`${base}/${name}`, { redirect: 'follow' });
      if (!r.ok) throw new Error(`${name}: HTTP ${r.status}`);
      return Buffer.from(await r.arrayBuffer());
    } catch (e) {
      if (attempt >= 3) throw e;
      await new Promise((ok) => setTimeout(ok, 2000 * attempt));
    }
  }
}

(async () => {
  const info = JSON.parse((await get('version.json')).toString('utf8'));
  const apk = await get('IIMM-Buddy.apk');
  const sha = crypto.createHash('sha256').update(apk).digest('hex');
  if (info.sha256 && info.sha256 !== sha) {
    throw new Error(`APK fingerprint ${sha} does not match version.json (${info.sha256})`);
  }
  if (info.size && info.size !== apk.length) {
    throw new Error(`APK size ${apk.length} does not match version.json (${info.size})`);
  }
  fs.writeFileSync(path.join(out, 'IIMM-Buddy.apk'), apk);
  fs.writeFileSync(path.join(out, 'version.json'), JSON.stringify(info, null, 2) + '\n');
  // The download page shows the version and size of what it serves.
  const page = path.join(out, 'index.html');
  const mb = Math.round(apk.length / 1e6);
  fs.writeFileSync(page, fs.readFileSync(page, 'utf8')
    .replace(/Version [0-9.]+ · [0-9]+ MB/g, `Version ${info.version} · ${mb} MB`));
  console.log(`Release ${info.version} (build ${info.build}), ${apk.length} bytes`);
})().catch((e) => {
  console.error(`Could not fetch the release: ${e.message}`);
  process.exit(1);
});
