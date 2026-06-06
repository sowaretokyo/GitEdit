#!/usr/bin/env bash
# Cut a new release tag (vX.Y.Z) and push it. The Release workflow takes
# over from there and builds, signs, notarizes, and uploads the .dmg.
#
# Usage:
#   scripts/release.sh           # patch/minor/major を対話で選ぶ
#   scripts/release.sh patch     # 直接指定
#   scripts/release.sh minor
#   scripts/release.sh major
#   scripts/release.sh 1.2.3     # 任意のバージョンを明示
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# --- 1. Safety checks ---------------------------------------------------------

current_branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "${current_branch}" != "main" ]]; then
    echo "❌ main ブランチで実行してください（現在: ${current_branch}）" >&2
    exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "❌ 未コミットの変更があります。先に commit / stash してください" >&2
    git status --short
    exit 1
fi

echo "==> origin の状態を確認"
git fetch --tags origin main >/dev/null

local_head="$(git rev-parse HEAD)"
remote_head="$(git rev-parse origin/main)"
if [[ "${local_head}" != "${remote_head}" ]]; then
    echo "❌ ローカル main が origin/main と一致しません。先に pull / push してください" >&2
    echo "    local:  ${local_head:0:7}"
    echo "    remote: ${remote_head:0:7}"
    exit 1
fi

# --- 2. Resolve the last version ---------------------------------------------

last_tag="$(git tag --list 'v*' --sort=-v:refname | head -n 1 || true)"
if [[ -z "${last_tag}" ]]; then
    cur_major=0
    cur_minor=0
    cur_patch=0
    echo "==> 過去のリリースタグなし。最初のリリースを切ります"
else
    ver="${last_tag#v}"
    IFS='.' read -r cur_major cur_minor cur_patch <<< "${ver}"
    echo "==> 直近のリリース: ${last_tag}"
fi

# --- 3. Determine the bump ---------------------------------------------------

bump="${1:-}"
if [[ -z "${bump}" ]]; then
    echo
    echo "どのバージョンを上げますか？"
    echo
    echo "  [1] patch  → v${cur_major}.${cur_minor}.$((cur_patch + 1))   (バグ修正・微調整)"
    echo "  [2] minor  → v${cur_major}.$((cur_minor + 1)).0   (機能追加・後方互換あり)"
    echo "  [3] major  → v$((cur_major + 1)).0.0   (破壊的変更)"
    echo
    read -rp "選択 [1-3]: " choice
    case "${choice}" in
        1|patch|p) bump="patch" ;;
        2|minor|m) bump="minor" ;;
        3|major|M) bump="major" ;;
        *) echo "❌ 不正な選択: ${choice}" >&2; exit 1 ;;
    esac
fi

case "${bump}" in
    patch)
        new_version="${cur_major}.${cur_minor}.$((cur_patch + 1))"
        ;;
    minor)
        new_version="${cur_major}.$((cur_minor + 1)).0"
        ;;
    major)
        new_version="$((cur_major + 1)).0.0"
        ;;
    *)
        if [[ "${bump}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            new_version="${bump}"
        else
            echo "❌ 不正な引数: ${bump}（patch / minor / major / X.Y.Z のいずれか）" >&2
            exit 1
        fi
        ;;
esac

new_tag="v${new_version}"

if git rev-parse "${new_tag}" >/dev/null 2>&1; then
    echo "❌ タグ ${new_tag} は既に存在します" >&2
    exit 1
fi

# --- 4. Confirm and push -----------------------------------------------------

echo
echo "    新しいタグ:     ${new_tag}"
echo "    対象コミット:   $(git log -1 --pretty=format:'%h %s')"
echo
read -rp "    push してリリースを開始しますか？ [y/N]: " confirm
case "${confirm}" in
    y|Y|yes|YES) ;;
    *) echo "中止しました"; exit 0 ;;
esac

git tag -a "${new_tag}" -m "Release ${new_tag}"
git push origin "${new_tag}"

cat <<DONE

✅ ${new_tag} を push しました

   CI       : https://github.com/sowaretokyo/GitEdit/actions
   Releases : https://github.com/sowaretokyo/GitEdit/releases
   DL (固定): https://github.com/sowaretokyo/GitEdit/releases/latest/download/GitEdit.dmg

DONE
