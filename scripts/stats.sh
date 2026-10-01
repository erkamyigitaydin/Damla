#!/bin/zsh
# Damla in numbers: downloads and daily active installs from damla.erkamaydin.com (server/feed, counted in
# D1), plus the GitHub downloads from before the move and the repository's traffic.
set -euo pipefail
export GH_NO_UPDATE_NOTIFIER=1
REPO="erkamyigitaydin/Damla"
FEED_DIR="${0:A:h}/../server/feed"

# Runs a query on the counters and prints its rows with the given Python format per row.
query() {
  (cd "$FEED_DIR" && npx --yes wrangler d1 execute damla-stats --remote --json --command "$1" 2>/dev/null) | python3 -c '
import json, sys
fmt, empty = sys.argv[1], sys.argv[2]
rows = json.load(sys.stdin)[0]["results"]
for row in rows:
    print(fmt.format(**row))
if not rows:
    print(empty)
' "$2" "$3"
}

echo "Aktif kurulumlar (günlük, son 14 gün; Sparkle güncelleme kontrolleri):"
query "SELECT day, SUM(installs) AS installs, GROUP_CONCAT(version || ':' || installs, ' ') AS versions
       FROM daily WHERE day >= date('now', '-14 day') GROUP BY day ORDER BY day DESC" \
      "  {day}  {installs} kurulum  ({versions})" "  henüz veri yok (0.8.2 ve sonrası sayılır)"

echo "İndirmeler, damla.erkamaydin.com (son 30 gün; site, Homebrew ve güncellemeler):"
query "SELECT file, SUM(count) AS total FROM downloads WHERE day >= date('now', '-30 day') GROUP BY file ORDER BY file DESC" \
      "  {file}  {total}" "  henüz indirme yok"

echo "İndirmeler, GitHub Releases (taşınmadan önce):"
gh api "repos/$REPO/releases" --paginate --jq '[.[].assets[].download_count] | add // 0 | "  toplam \(.)"' 2>/dev/null \
  || echo "  okunamadı (repo gizliyse bu satır beklenir)"

echo "Repo (son 14 gün):"
gh api "repos/$REPO/traffic/views" --jq '"  görüntülenme \(.count), tekil \(.uniques)"' 2>/dev/null || echo "  okunamadı"
