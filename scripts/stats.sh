#!/bin/zsh
# Damla in numbers: GitHub downloads per release, site traffic, and (once the feed worker is live) daily
# active installs from the update checks.
set -euo pipefail
REPO="erkamyigitaydin/Damla"
echo "İndirmeler (GitHub Releases, Homebrew dahil):"
gh api "repos/$REPO/releases" --paginate --jq '.[] | "  \(.tag_name)\t" + ([.assets[] | .download_count] | add // 0 | tostring)'
gh api "repos/$REPO/releases" --paginate --jq '[.[].assets[].download_count] | add // 0 | "  toplam\t\(.)"'
echo "Repo (son 14 gün):"
gh api "repos/$REPO/traffic/views" --jq '"  görüntülenme \(.count), tekil \(.uniques)"'
FEED_DIR="${0:A:h}/../server/feed"
if grep -q REPLACE_AFTER_D1_CREATE "$FEED_DIR/wrangler.toml"; then
  echo "Aktif kurulumlar: güncelleme sayacı henüz kurulmadı (server/feed)."
  exit 0
fi
echo "Aktif kurulumlar (günlük, son 14 gün):"
(cd "$FEED_DIR" && npx --yes wrangler d1 execute damla-stats --remote --json --command \
  "SELECT day, SUM(installs) AS kurulum, SUM(checks) AS kontrol, GROUP_CONCAT(version || ':' || installs, ' ') AS surumler
   FROM daily WHERE day >= date('now', '-14 day') GROUP BY day ORDER BY day DESC" ) \
  | python3 -c 'import json,sys; rows=json.load(sys.stdin)[0]["results"]; [print(f"  {r[\"day\"]}  {r[\"kurulum\"]} kurulum  ({r[\"surumler\"]})") for r in rows] or print("  henüz veri yok")'
