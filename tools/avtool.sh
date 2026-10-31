#!/usr/bin/env bash
# avtool.sh — AV 归类 + 刮削核对二合一 (organize_av.sh + check_rescrape.sh 合并)
#   avtool.sh organize SRC DST [--copy] [--dry-run] [--metatube URL] [--workers N]
#     SRC=目录(递归)或单个视频文件 → DST/{女优}/|_共演/|_未识别/,文件名不变
#     默认移动; --copy 复制; --dry-run 预演;目标存在跳过;日志 DST/organize_av.log
#   avtool.sh check [--api-key KEY] [--host URL] [--library 名] [--user-id UID]
#                    [--out 文件] [--fix] [--limit N] [--filter 子串]
#     核对媒体库刮削ID与文件名;加 --fix 对不一致/无ID条目按文件名搜索并应用精确命中
#   avtool.sh identify [--api-key KEY] [--host URL] [--library 名] [--user-id UID]
#                      [--limit N] [--filter 子串]
#     对码不对的条目按文件名搜元数据,只自动应用番号精确命中的,等价批量"识别"
set -u

up() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }
sanitize() { printf '%s' "$1" | sed 's#[/\\:*?"<>|]#_#g; s/[. ]*$//'; }

# 文件名 → 番号候选(每行一个,优先级从高到低)
candidates() {
  local base="${1%.*}" u
  u=$(up "$base")
  echo "$u"
  if [[ "$base" =~ ^[0-9]+([A-Za-z]+-[0-9]+[A-Za-z]*)$ ]]; then echo "$(up "${BASH_REMATCH[1]}")"; fi
  local ns="${base%%_*}"
  [ "$(up "$ns")" != "$u" ] && echo "$(up "$ns")"
  if [[ "$u" =~ ^([A-Z]+-[0-9]+)[A-Za-z]+$ ]]; then echo "${BASH_REMATCH[1]}"; fi
  local de
  de=$(printf '%s' "$u" | sed -E 's/-(UC|U|C)$//')
  [ "$de" != "$u" ] && echo "$de"
}

usage() {
  echo "用法:" >&2
  echo "  $0 organize SRC DST [--copy] [--dry-run] [--metatube URL] [--workers N]" >&2
  echo "  $0 check [--api-key KEY] [--host URL] [--library 名] [--user-id UID]" >&2
  echo "                 [--out 文件] [--fix] [--limit N] [--filter 子串]" >&2
  echo "  $0 identify [--api-key KEY] [--host URL] [--library 名] [--user-id UID]" >&2
  echo "                    [--limit N] [--filter 子串]" >&2
}

# _identify_one <itemid> <文件名> : 按文件名候选搜元数据,只应用番号精确命中的
# 依赖调用者的 HOST/APIKEY (bash 动态作用域); 返回 0=已应用 1=跳过 2=失败
_identify_one() {
  local id=$1 fn=$2 code req res pick st
  while IFS= read -r code; do
    req=$(jq -n --arg name "$code" --arg item "$id" \
      '{SearchInfo:{Name:$name},ItemId:$item,SearchProviderName:"MetaTube"}')
    res=$(curl -s -m 60 -X POST "$HOST/Items/RemoteSearch/Movie?api_key=$APIKEY" \
      -H "Content-Type: application/json" -d "$req")
    pick=$(printf '%s' "$res" | jq -c --arg code "$code" \
      'map(select((.ProviderIds.MetaTube // "" | ascii_upcase) == ("JAVBUS:"+$code))) | .[0] // empty')
    [ -n "$pick" ] || continue
    st=$(curl -s -m 60 -o /dev/null -w "%{http_code}" -X POST \
      "$HOST/Items/RemoteSearch/Apply/$id?api_key=$APIKEY&ReplaceAllImages=true" \
      -H "Content-Type: application/json" -d "$pick")
    if [ "$st" = 204 ] || [ "$st" = 200 ]; then
      echo "  已识别: $fn -> $(printf '%s' "$pick" | jq -r '.ProviderIds.MetaTube')"
      return 0
    fi
    echo "  应用失败 $fn (HTTP $st)"; return 2
  done < <(candidates "$fn")
  echo "  无精确命中,跳过: $fn"; return 1
}

# ---------------------------------------------------------------- organize
# 单个番号 → 写 $TMPD/map/<CODE> 内容为: 人数|首位演员 (查无则空文件)
fetch_one() {
  local code=$1 lazy out n first title
  for lazy in True False; do
    out=$(curl -s -m 25 "$META/v1/movies/JavBus/$code?lazy=$lazy" 2>/dev/null) || continue
    [ "$(printf '%s' "$out" | jq -r '.data // empty | (.actors // [] | length), (.title // "")' 2>/dev/null | head -1)" != "" ] || continue
    n=$(printf '%s' "$out" | jq -r '.data.actors // [] | length')
    first=$(printf '%s' "$out" | jq -r '.data.actors[0] // empty')
    title=$(printf '%s' "$out" | jq -r '.data.title // empty')
    if [ "$n" -gt 0 ] || [ -n "$title" ]; then
      printf '%s|%s' "$n" "$first" > "$TMPD/map/$code"
      return 0
    fi
  done
  : > "$TMPD/map/$code"   # 标记已查无
}

cmd_organize() {
  [ $# -ge 2 ] || { echo "用法: $0 organize SRC DST [--copy] [--dry-run] [--metatube URL] [--workers N]" >&2; return 2; }
  local SRC=$1 DST=$2; shift 2
  DST=${DST%/}; [ -z "$DST" ] && DST=/
  local COPY=0 DRY=0 META="http://localhost:8085" WORKERS=8
  while [ $# -gt 0 ]; do
    case "$1" in
      --copy) COPY=1 ;;
      --dry-run) DRY=1 ;;
      --metatube) META=${2:?缺URL}; shift ;;
      --workers) WORKERS=${2:?缺数字}; shift ;;
      *) echo "未知参数: $1" >&2; return 2 ;;
    esac
    shift
  done
  local VIDS=()
  if [ -d "$SRC" ]; then
    mapfile -t VIDS < <(find "$SRC" -type f \( -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.avi' -o -iname '*.wmv' -o -iname '*.m2ts' -o -iname '*.ts' \) | sort)
  elif [ -f "$SRC" ]; then
    case "${SRC,,}" in
      *.mp4|*.mkv|*.avi|*.wmv|*.m2ts|*.ts) VIDS=("$SRC") ;;
      *) echo "来源不是视频文件: $SRC" >&2; return 2 ;;
    esac
  else
    echo "来源不存在: $SRC" >&2; return 2
  fi
  command -v curl >/dev/null || { echo "缺 curl" >&2; return 2; }
  command -v jq >/dev/null || { echo "缺 jq" >&2; return 2; }
  command -v rsync >/dev/null || { echo "缺 rsync" >&2; return 2; }
  META=${META%/}
  TMPD=$(mktemp -d) || return 3
  trap 'rm -rf "$TMPD"' EXIT
  export -f fetch_one
  export META TMPD

  mkdir -p "$TMPD/map"
  echo "扫描到视频 ${#VIDS[@]} 个"
  [ "${#VIDS[@]}" -eq 0 ] && return 0

  local CODES=()
  mapfile -t CODES < <(for v in "${VIDS[@]}"; do candidates "$(basename "$v")"; done | awk '!seen[$0]++')
  printf '%s\n' "${CODES[@]}" | xargs -P "$WORKERS" -I{} bash -c 'fetch_one "$@"' _ {}
  local ok
  ok=$(grep -l . "$TMPD/map/"* 2>/dev/null | wc -l)
  echo "有演员番号 $ok/${#CODES[@]}"

  local done_n=0 skipped=0 i=0 n=${#VIDS[@]} src fn sub hit content cnt first dst gb OPS
  for src in "${VIDS[@]}"; do
    fn=$(basename "$src")
    sub="_未识别"; hit=""
    while IFS= read -r c; do
      if [ -s "$TMPD/map/$c" ]; then hit=$c; break; fi
    done < <(candidates "$fn")
    if [ -n "$hit" ]; then
      content=$(cat "$TMPD/map/$hit")
      cnt=${content%%|*}; first=${content#*|}
      if [ "$cnt" = "1" ]; then sub=$(sanitize "$first"); [ -z "$sub" ] && sub="_未识别"
      elif [ "$cnt" -gt 1 ] 2>/dev/null; then sub="_共演"; fi
    fi
    dst="$DST/$sub/$fn"
    [ "$src" -ef "$dst" ] 2>/dev/null && continue
    i=$((i+1))
    gb=$(awk "BEGIN{printf \"%.1f\", $(stat -c%s "$src")/1e9}")
    echo "[$i/$n] $fn (${gb}GB) -> ./$sub/$fn"
    [ "$DRY" = 1 ] && continue
    mkdir -p "$DST/$sub"
    if [ -e "$dst" ]; then echo "  跳过(目标已存在)"; skipped=$((skipped+1)); continue; fi
    if [ "$COPY" = 1 ]; then OPS=""; else OPS="--remove-source-files"; fi
    # shellcheck disable=SC2086
    rsync -a --ignore-existing $OPS --info=progress2 --human-readable "$src" "$dst" \
      || { echo "传输失败: $src" >&2; continue; }
    printf '%s\t%s\n' "$src" "$dst" >> "$DST/organize_av.log"
    done_n=$((done_n+1))
  done
  [ "$DRY" = 1 ] && { echo "dry-run: 未写盘"; return 0; }
  echo "完成 移动/复制 $done_n 个, 跳过 $skipped 个, 日志 $DST/organize_av.log"
}

# ---------------------------------------------------------------- check
cmd_check() {
  local APIKEY="${JELLYFIN_API_KEY:-}"
  local HOST="http://localhost:8096" LIB="AV" UID_ARG="" OUT="scrape_mismatch.txt"
  local FIX=0 LIMIT=0 FILTER=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --api-key) APIKEY=${2:?缺KEY}; shift ;;
      --host) HOST=${2:?缺URL}; shift ;;
      --library) LIB=${2:?缺库名}; shift ;;
      --user-id) UID_ARG=${2:?缺UID}; shift ;;
      --out) OUT=${2:?缺路径}; shift ;;
      --fix) FIX=1 ;;
      --limit) LIMIT=${2:?缺数字}; shift ;;
      --filter) FILTER=${2:?缺子串}; shift ;;
      *) echo "未知参数: $1" >&2; return 2 ;;
    esac
    shift
  done
  [ -n "$APIKEY" ] || { echo "缺 API Key: --api-key 或 JELLYFIN_API_KEY" >&2; return 2; }
  command -v curl >/dev/null || { echo "缺 curl" >&2; return 2; }
  command -v jq >/dev/null || { echo "缺 jq" >&2; return 2; }
  HOST=${HOST%/}

  local UIDS PARENT="" USERID="" u
  UIDS=$(curl -s -m 30 "$HOST/Users?api_key=$APIKEY" | jq -r '.[].Id')
  [ -n "$UID_ARG" ] && UIDS="$UID_ARG"
  for u in $UIDS; do
    PARENT=$(curl -s -m 30 "$HOST/Users/$u/Views?api_key=$APIKEY" \
      | jq -r --arg lib "$LIB" '.Items[] | select(.Name==$lib) | .Id' | head -1)
    if [ -n "$PARENT" ]; then USERID="$u"; break; fi
  done
  [ -n "$PARENT" ] || { echo "找不到媒体库: $LIB" >&2; return 2; }

  TMPD=$(mktemp -d) || return 3
  trap 'rm -rf "$TMPD"' EXIT
  curl -s -m 120 "$HOST/Users/$USERID/Items?api_key=$APIKEY&ParentId=$PARENT&Recursive=true&IncludeItemTypes=Movie&Fields=Path,ProviderIds,Name&limit=5000" \
    | jq -r '.Items[] | [.Id, (.Path//""), (.ProviderIds.MetaTube//""), (.Name//"")] | @tsv' > "$TMPD/items.tsv"
  local total
  total=$(wc -l < "$TMPD/items.tsv")
  echo "库 $LIB: Movie $total 个"

  local ok=0 miss=0 noid=0 id path mt fname fn sc hit c code
  : > "$TMPD/miss.txt"; : > "$TMPD/noid.txt"
  while IFS=$'\t' read -r id path mt fname; do
    fn=$(basename "$path")
    case "${fn,,}" in *.mp4|*.mkv) ;; *) continue ;; esac
    [ -n "$FILTER" ] && [[ "$fn" != *"$FILTER"* ]] && continue
    sc=""; [ -n "$mt" ] && sc=$(up "${mt##*:}")
    if [ -z "$sc" ]; then
      noid=$((noid+1)); printf '%s\t%s\t%s\t%s\n' "$fn" "$(candidates "$fn" | head -1)" "$id" "$fname" >> "$TMPD/noid.txt"
      continue
    fi
    hit=0
    while IFS= read -r c; do [ "$c" = "$sc" ] && { hit=1; break; }; done < <(candidates "$fn")
    if [ "$hit" = 1 ]; then ok=$((ok+1)); else
      miss=$((miss+1)); printf '%s\t%s\t%s\t%s\t%s\n' "$fn" "$(candidates "$fn" | head -1)" "$sc" "$id" "$fname" >> "$TMPD/miss.txt"
    fi
  done < "$TMPD/items.tsv"
  echo "一致 $ok / 不一致 $miss / 无ID $noid"
  {
    echo "一致$ok 不一致$miss 无ID$noid"
    echo; echo "===== 不一致 $miss ====="
    awk -F'\t' '{print $1" | 文件="$2" | 刮削="$3" | 显示="$5" | id="$4}' "$TMPD/miss.txt"
    echo; echo "===== 无ID $noid ====="
    awk -F'\t' '{print $1" | 文件="$2" | 刮削=无ID | 显示="$4" | id="$3}' "$TMPD/noid.txt"
  } > "$OUT"
  echo "报告已写 $OUT"

  [ "$FIX" = 0 ] && { echo "检查模式: 未触发修复(加 --fix 按文件名搜索并应用精确命中)"; return 0; }
  { cat "$TMPD/miss.txt"; awk -F'\t' '{print $1"\t-\t无ID\t"$3"\t"$4}' "$TMPD/noid.txt"; } > "$TMPD/targets.txt"
  [ "$LIMIT" -gt 0 ] && head -"$LIMIT" "$TMPD/targets.txt" > "$TMPD/t.l" && mv "$TMPD/t.l" "$TMPD/targets.txt"
  local done_n=0 skip_n=0 fail=0 rc
  while IFS=$'\t' read -r fn _fc _sc id _fname; do
    _identify_one "$id" "$fn"; rc=$?
    case $rc in 0) done_n=$((done_n+1));; 1) skip_n=$((skip_n+1));; *) fail=$((fail+1));; esac
    sleep 0.5
  done < "$TMPD/targets.txt"
  echo "识别 $done_n 个, 跳过 $skip_n 个, 失败 $fail 个"
  [ "$fail" = 0 ]
}

# ---------------------------------------------------------------- identify
# 对码不对的条目按文件名搜元数据,只自动应用番号精确命中的(等价批量"识别")
cmd_identify() {
  local APIKEY="${JELLYFIN_API_KEY:-}"
  local HOST="http://localhost:8096" LIB="AV" UID_ARG=""
  local LIMIT=0 FILTER=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --api-key) APIKEY=${2:?缺KEY}; shift ;;
      --host) HOST=${2:?缺URL}; shift ;;
      --library) LIB=${2:?缺库名}; shift ;;
      --user-id) UID_ARG=${2:?缺UID}; shift ;;
      --limit) LIMIT=${2:?缺数字}; shift ;;
      --filter) FILTER=${2:?缺子串}; shift ;;
      *) echo "未知参数: $1" >&2; return 2 ;;
    esac
    shift
  done
  [ -n "$APIKEY" ] || { echo "缺 API Key: --api-key 或 JELLYFIN_API_KEY" >&2; return 2; }
  command -v curl >/dev/null || { echo "缺 curl" >&2; return 2; }
  command -v jq >/dev/null || { echo "缺 jq" >&2; return 2; }
  HOST=${HOST%/}

  local UIDS PARENT="" USERID="" u
  UIDS=$(curl -s -m 30 "$HOST/Users?api_key=$APIKEY" | jq -r '.[].Id')
  [ -n "$UID_ARG" ] && UIDS="$UID_ARG"
  for u in $UIDS; do
    PARENT=$(curl -s -m 30 "$HOST/Users/$u/Views?api_key=$APIKEY" \
      | jq -r --arg lib "$LIB" '.Items[] | select(.Name==$lib) | .Id' | head -1)
    if [ -n "$PARENT" ]; then USERID="$u"; break; fi
  done
  [ -n "$PARENT" ] || { echo "找不到媒体库: $LIB" >&2; return 2; }

  TMPD=$(mktemp -d) || return 3
  trap 'rm -rf "$TMPD"' EXIT
  curl -s -m 120 "$HOST/Users/$USERID/Items?api_key=$APIKEY&ParentId=$PARENT&Recursive=true&IncludeItemTypes=Movie&Fields=Path,ProviderIds&limit=5000" \
    | jq -r '.Items[] | [.Id, (.Path//""), (.ProviderIds.MetaTube//"")] | @tsv' > "$TMPD/items.tsv"

  local id path mt fn sc hit c rc applied=0 skipped=0 failed=0
  while IFS=$'\t' read -r id path mt; do
    fn=$(basename "$path")
    case "${fn,,}" in *.mp4|*.mkv) ;; *) continue ;; esac
    [ -n "$FILTER" ] && [[ "$fn" != *"$FILTER"* ]] && continue
    [ "$LIMIT" -gt 0 ] && [ $((applied+skipped+failed)) -ge "$LIMIT" ] && break
    sc=""; [ -n "$mt" ] && sc=$(up "${mt##*:}")
    hit=0
    while IFS= read -r c; do [ "$c" = "$sc" ] && { hit=1; break; }; done < <(candidates "$fn")
    [ "$hit" = 1 ] && continue   # 已一致,跳过
    _identify_one "$id" "$fn"; rc=$?
    case $rc in 0) applied=$((applied+1));; 1) skipped=$((skipped+1));; *) failed=$((failed+1));; esac
    sleep 0.5
  done < "$TMPD/items.tsv"
  echo "识别 $applied 个, 跳过 $skipped 个, 失败 $failed 个"
  [ "$failed" = 0 ]
}

# ---------------------------------------------------------------- dispatch
[ $# -ge 1 ] || { usage; exit 2; }
CMD=$1; shift
case "$CMD" in
  organize) cmd_organize "$@" ;;
  check) cmd_check "$@" ;;
  identify) cmd_identify "$@" ;;
  *) usage; exit 2 ;;
esac
