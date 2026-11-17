#!/bin/zsh
# Copies the app and the server into the public GitHub repo folder, checks
# that nothing secret came along, then commits and pushes.
#   ./publish-code.sh "what changed"      (DRY=1 to copy and check only)
set -e
APP=${APP:-$HOME/attendance-planner}
SERVER=${SERVER:-$HOME/iimm-buddy-api}
REPO=${REPO:-$HOME/iimm-buddy}
msg=${1:-"Update code"}

common=(--exclude .DS_Store --exclude '*.iml' --exclude .idea --exclude '*.apk'
        --exclude '.env*' --exclude '*.jks' --exclude '*.keystore' --exclude key.properties
        --exclude publisher-key.txt --exclude google-services.json --exclude '*service-account*')

rsync -a --delete "${common[@]}" \
  --exclude build --exclude .dart_tool --exclude .gradle --exclude local.properties \
  --exclude .flutter-plugins --exclude .flutter-plugins-dependencies --exclude android/app/debug \
  --exclude android/app/profile --exclude android/app/release \
  "$APP/" "$REPO/app/"

rsync -a --delete "${common[@]}" \
  --exclude node_modules --exclude .vercel --exclude public/version.json \
  "$SERVER/" "$REPO/server/"

# ---- safety check: the real secret values must not appear anywhere
cd "$REPO"
secrets=()
[[ -f $SERVER/publisher-key.txt ]] && secrets+=("$(tr -d '\n' < $SERVER/publisher-key.txt)")
if [[ -f $SERVER/.env.local ]]; then
  while IFS='=' read -r k v; do
    v=${v%\"}; v=${v#\"}
    [[ ${#v} -ge 12 ]] && secrets+=("$v")
  done < <(grep -E '^[A-Z_]+=' $SERVER/.env.local)
fi
for s in "${secrets[@]}"; do
  if grep -rIlF -- "$s" app server >/dev/null 2>&1; then
    echo "STOP: a secret value was found in the repo copy. Nothing pushed."; exit 1
  fi
done
for f in publisher-key.txt .env.local google-services.json; do
  if [[ -n $(find app server -name "$f" -print -quit) ]]; then echo "STOP: $f found. Nothing pushed."; exit 1; fi
done
if grep -rIl -E -e '-----BEGIN (RSA |EC )?PRIVATE KEY-----' -e '"private_[k]ey": *"-' app server >/dev/null 2>&1; then
  echo "STOP: a private key was found. Nothing pushed."; exit 1
fi
me="${USER}@"   # built at run time so this file passes its own check
if grep -rIliF -e "$me" app server >/dev/null 2>&1; then echo "STOP: a personal email was found. Nothing pushed."; exit 1; fi

if [[ -n $DRY ]]; then echo "Checks passed (dry run, nothing committed)."; exit 0; fi
git add -A
if git diff --cached --quiet; then echo "No changes."; exit 0; fi
git commit -q -m "$msg"
git push -q origin main
echo "Pushed: $(git log -1 --format='%h %s')"
