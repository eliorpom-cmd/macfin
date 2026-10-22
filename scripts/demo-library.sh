#!/bin/bash
# Rebuilds, from scratch, the demo Jellyfin server used for the README screenshots.
#
# A second, throwaway Jellyfin instance runs from .demo/ on its own port (8097 by default), so a
# Jellyfin server you already run on this Mac (8096) is never touched. The library holds short
# excerpts of free movies (Blender open movies under Creative Commons, public domain classics),
# with local posters, backdrops and .nfo files that give each movie its full runtime.
#
# Usage: scripts/demo-library.sh [all|media|start|setup|status|stop|trash-clips]
#   all          media + start + setup (default)
#   media        download the excerpts and images, write the .nfo files
#   start        start the demo server (writes network.xml before the first launch)
#   setup        run the startup wizard, create the demo user, library, progress and trickplay
#   status       print the server address and library size
#   stop         stop the demo server
#   trash-clips  move the video excerpts to the Trash (run `media` again to get them back)
#
# Requirements: Jellyfin.app (https://jellyfin.org/downloads/macos), ffmpeg, curl, jq.
# Sign in to the demo server with user "demo", password "demo".

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEMO=${MACFIN_DEMO_DIR:-$ROOT/.demo}
PORT=${MACFIN_DEMO_PORT:-8097}
JELLYFIN_APP=${JELLYFIN_APP:-/Applications/Jellyfin.app}
SERVER="http://127.0.0.1:$PORT"
DEMO_USER=demo
DEMO_PASSWORD=demo
CLIP_SECONDS=${MACFIN_CLIP_SECONDS:-120}
UA="MacfinDemoLibrary/1.0 (open-source demo script; curl/ffmpeg)"
MOVIES="$DEMO/media/Movies"
AUTH_BASE='MediaBrowser Client="Macfin demo-library", Device="script", DeviceId="macfin-demo-library", Version="1.0"'

# Never run against the default Jellyfin port or the default Jellyfin data folders.
if [[ "$PORT" == 8096 ]]; then echo "Refusing to use port 8096: pick another MACFIN_DEMO_PORT." >&2; exit 1; fi
case "$DEMO" in
  "$HOME/Library/Application Support/jellyfin"*|"$HOME/Library/Caches/jellyfin"*) echo "Refusing to use $DEMO." >&2; exit 1 ;;
esac

log() { printf '\033[1m%s\033[0m\n' "$*"; }

# ---------------------------------------------------------------------------------------------
# Movies: key | title | year | source | excerpt start (s) | backdrop frame (s into the excerpt)
#         | crop (ffmpeg w:h:x:y, empty = none) | poster URL (empty = cut from the backdrop frame)
#         | runtime (min) | genres | director | plot
# Sources: "ia:<archive.org item>/<file>" or a direct URL. Posters are Wikimedia Commons thumbnails
# (originals are rate limited). Licenses are listed in README.md › Credits.
# ---------------------------------------------------------------------------------------------
read -r -d '' CATALOG <<'EOF' || true
bbb|Big Buck Bunny|2008|ia:BigBuckBunnyFULLHD60FPS/Big Buck Bunny - FULL HD 60FPS.mp4|75|12||https://upload.wikimedia.org/wikipedia/commons/thumb/c/c5/Big_buck_bunny_poster_big.jpg/960px-Big_buck_bunny_poster_big.jpg|10|Animation,Comedy|Sacha Goedegebure|A giant, gentle rabbit wakes up to a perfect spring morning, until three bullying rodents pick the wrong target. The Blender Foundation's second open movie.
sintel|Sintel|2010|ia:Sintel/sintel-2048-stereo.mp4|190|28||https://upload.wikimedia.org/wikipedia/commons/thumb/8/8f/Sintel_poster.jpg/960px-Sintel_poster.jpg|15|Animation,Fantasy|Colin Levy|A lone young woman crosses a frozen world to find the baby dragon she raised, taken from her by a full-grown one.
tos|Tears of Steel|2012|ia:Tears-of-Steel/tears_of_steel_1080p.mkv|250|40||https://upload.wikimedia.org/wikipedia/commons/thumb/7/70/Tos-poster.png/960px-Tos-poster.png|12|Science Fiction,Action|Ian Hubert|In a future Amsterdam, a group of scientists and soldiers try to save the world from destructive robots by replaying a breakup.
ed|Elephants Dream|2006|https://download.blender.org/ED/elephantsdream-1024-h264-st-aac.mov|150|30||https://upload.wikimedia.org/wikipedia/commons/thumb/0/0c/ElephantsDreamPoster.jpg/960px-ElephantsDreamPoster.jpg|11|Animation,Science Fiction|Bassam Kurdali|Two men explore a vast, mechanical world that only one of them seems to understand. The first open movie made with Blender.
cosmos|Cosmos Laundromat|2015|ia:CosmosLaundromatFirstCycle/Cosmos Laundromat - First Cycle (1080p).mp4|200|50||https://upload.wikimedia.org/wikipedia/commons/thumb/c/c5/CosmosLaundromatPoster.jpg/960px-CosmosLaundromatPoster.jpg|12|Animation,Comedy|Mathieu Auvray|On a desolate island, a suicidal sheep named Franck meets a quirky salesman who offers him the gift of a lifetime.
spring|Spring|2019|ia:spring_blenderopenmovie/Spring - Blender Open Movie - YouTube.mkv|120|20||https://upload.wikimedia.org/wikipedia/commons/thumb/0/05/Spring2019PillarPosterBlender.jpg/960px-Spring2019PillarPosterBlender.jpg|8|Animation,Fantasy|Andy Goralczyk|A shepherd girl and her dog face ancient spirits to bring back the cycle of seasons.
nosferatu|Nosferatu|1922|ia:Nosferatu1922/Nosferatu.mp4|2400|84|||92|Horror|F. W. Murnau|An estate agent travels to the Carpathian mountains to sell a house to Count Orlok, who follows him home with a ship full of plague rats.
notld|Night of the Living Dead|1968|ia:Night.Of.The.Living.Dead_1080p/NightOfTheLivingDead_1080p.mkv|1500|40||https://upload.wikimedia.org/wikipedia/commons/thumb/a/a7/Night_Of_The_Living_Dead_%281968%29_-_Poster.jpg/960px-Night_Of_The_Living_Dead_%281968%29_-_Poster.jpg|96|Horror|George A. Romero|Seven strangers barricade themselves in a Pennsylvania farmhouse as the dead return to life outside.
moon|A Trip to the Moon|1902|ia:ATripToTheMoonGeorgeMelies/A Trip to the Moon-George Méliès.mp4|240|30|928:720:176:0|https://upload.wikimedia.org/wikipedia/commons/8/83/Voyage_dans_la_Lune_affiche.jpg|13|Science Fiction,Adventure|Georges Méliès|Six astronomers fire themselves at the Moon in a giant shell, land in its eye and meet its inhabitants.
general|The General|1926|ia:TheGeneral1926/The_General_1926_720p.mp4|2000|30||https://upload.wikimedia.org/wikipedia/commons/c/cd/The_general_movie_poster.jpg|79|Comedy,Action|Buster Keaton|When Union spies steal his locomotive, a Southern railroad engineer chases them north, alone, to get it back.
EOF

# Movies given a playback position (fraction of the runtime), newest first, for "Continue Watching".
RESUME="cosmos:0.42 sintel:0.63 notld:0.27"
# Movies marked as watched.
WATCHED="bbb moon"

folder_of() { echo "$MOVIES/$2 ($3)"; }

# Resolves an archive.org file to its storage node URL. archive.org/download redirects there,
# but some network filters block the redirect, so the node URL is asked for directly.
resolve_source() {
  local source=$1
  if [[ "$source" == ia:* ]]; then
    local item=${source#ia:}; item=${item%%/*}
    local file=${source#ia:"$item"/}
    local meta; meta=$(curl -fsS -m 30 -A "$UA" "https://archive.org/metadata/$item")
    local encoded; encoded=$(jq -rn --arg f "$file" '$f|@uri')
    echo "https://$(jq -r .d1 <<<"$meta")$(jq -r .dir <<<"$meta")/$encoded"
  else
    echo "$source"
  fi
}

cmd_media() {
  mkdir -p "$MOVIES"
  while IFS='|' read -r key title year source start frame crop poster runtime genres director plot; do
    [[ -z "$key" ]] && continue
    local dir; dir=$(folder_of "$key" "$title" "$year")
    local base="$dir/$title ($year)"
    mkdir -p "$dir"

    if [[ ! -s "$base.mp4" ]]; then
      log "$title: excerpt from ${start}s, ${CLIP_SECONDS}s"
      local url; url=$(resolve_source "$source")
      local filters="scale='min(1920,iw)':-2:flags=lanczos,format=yuv420p"
      [[ -n "$crop" ]] && filters="crop=$crop,$filters"
      # Input seeking reads only the excerpt over HTTP. The excerpt is re-encoded to H.264 without
      # audio because some sources are Theora, VP9 or AV1, which AVPlayer can't play.
      ffmpeg -nostdin -hide_banner -loglevel error -y -user_agent "$UA" \
        -ss "$start" -t "$CLIP_SECONDS" -i "$url" -map 0:v:0 -an \
        -vf "$filters" \
        -c:v h264_videotoolbox -b:v 5M -tag:v avc1 -movflags +faststart "$base.partial.mp4"
      if [[ $(stat -f%z "$base.partial.mp4" 2>/dev/null || echo 0) -lt 1000000 ]]; then
        mv -f "$base.partial.mp4" "$DEMO/.failed-$key.mp4" 2>/dev/null || true
        echo "$title: the excerpt couldn't be downloaded. Run the script again later." >&2; exit 1
      fi
      mv "$base.partial.mp4" "$base.mp4"
      sleep 2   # be gentle with Wikimedia's rate limits
    fi

    # Jellyfin always takes a video's runtime from the file, so the excerpt is padded to the movie's
    # real runtime with its last frame, kept once every 10 seconds: a few extra megabytes at most.
    local seconds; seconds=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$base.mp4" | cut -d. -f1)
    if (( seconds < runtime * 60 - 30 )); then
      log "$title: padding the excerpt to ${runtime} min"
      ffmpeg -nostdin -hide_banner -loglevel error -y -i "$base.mp4" \
        -vf "tpad=stop_mode=clone:stop_duration=$((runtime * 60 - seconds)),select='lt(t\,$seconds)+gte(t-prev_selected_t\,10)'" \
        -fps_mode passthrough -c:v libx264 -crf 18 -preset fast -tag:v avc1 -movflags +faststart "$base.partial.mp4"
      mv "$base.partial.mp4" "$base.mp4"
    fi

    if [[ ! -s "$dir/fanart.jpg" ]]; then
      ffmpeg -nostdin -hide_banner -loglevel error -y -ss "$frame" -i "$base.mp4" -frames:v 1 -q:v 2 "$dir/fanart.jpg"
    fi

    if [[ ! -s "$dir/poster.jpg" ]]; then
      if [[ -n "$poster" ]]; then
        local ext=${poster##*.}
        curl -fsSL -m 120 -A "$UA" -o "$dir/poster-source.$ext" "$poster"
        sips -s format jpeg -s formatOptions 90 -Z 1500 "$dir/poster-source.$ext" --out "$dir/poster.jpg" >/dev/null
        mv "$dir/poster-source.$ext" "$DEMO/.poster-source-$key.$ext"
        sleep 2
      else
        # No free poster: a 2:3 crop of the backdrop frame.
        ffmpeg -nostdin -hide_banner -loglevel error -y -i "$dir/fanart.jpg" -vf "crop=ih*2/3:ih" -q:v 2 "$dir/poster.jpg"
      fi
    fi

    {
      echo '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      echo '<movie>'
      echo "  <title>$title</title>"
      echo "  <year>$year</year>"
      echo "  <plot>$plot</plot>"
      echo "  <runtime>$runtime</runtime>"
      IFS=',' read -ra list <<<"$genres"
      for genre in "${list[@]}"; do echo "  <genre>$genre</genre>"; done
      echo "  <director>$director</director>"
      echo '  <lockdata>true</lockdata>'
      echo '</movie>'
    } > "$base.nfo"
  done <<<"$CATALOG"
  log "Media ready in $MOVIES ($(du -sh "$MOVIES" | cut -f1))"
}

cmd_start() {
  if curl -fsS -m 2 "$SERVER/System/Info/Public" >/dev/null 2>&1; then log "Demo server already running on $SERVER"; return; fi
  if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then echo "Port $PORT is taken by another process." >&2; exit 1; fi
  mkdir -p "$DEMO/data" "$DEMO/config" "$DEMO/cache" "$DEMO/log"
  # Written before the first launch so the instance never tries the default port.
  if [[ ! -f "$DEMO/config/network.xml" ]]; then
    cat > "$DEMO/config/network.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<NetworkConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <InternalHttpPort>$PORT</InternalHttpPort>
  <PublicHttpPort>$PORT</PublicHttpPort>
  <EnableHttps>false</EnableHttps>
  <AutoDiscovery>false</AutoDiscovery>
  <EnableUPnP>false</EnableUPnP>
  <EnableIPv6>false</EnableIPv6>
  <EnableRemoteAccess>false</EnableRemoteAccess>
  <LocalNetworkAddresses>
    <string>127.0.0.1</string>
  </LocalNetworkAddresses>
</NetworkConfiguration>
XML
  fi
  log "Starting the demo server on $SERVER"
  nohup "$JELLYFIN_APP/Contents/MacOS/jellyfin" \
    --datadir "$DEMO/data" --configdir "$DEMO/config" --cachedir "$DEMO/cache" --logdir "$DEMO/log" \
    --webdir "$JELLYFIN_APP/Contents/Resources/jellyfin-web" --ffmpeg "$JELLYFIN_APP/Contents/MacOS/ffmpeg" \
    > "$DEMO/log/server.out.log" 2>&1 &
  echo $! > "$DEMO/jellyfin.pid"
  for _ in $(seq 1 90); do
    if curl -fsS -m 2 "$SERVER/System/Info/Public" >/dev/null 2>&1; then log "Demo server is up (pid $(cat "$DEMO/jellyfin.pid"))"; return; fi
    sleep 2
  done
  echo "The demo server didn't start. See $DEMO/log." >&2; exit 1
}

# api METHOD PATH [JSON body]: retries while the server answers 503 (still starting up).
api() {
  local attempt
  for attempt in $(seq 1 60); do
    if api_once "$@"; then return 0; fi
    [[ "$LAST_STATUS" == 503 ]] || return 1
    sleep 2
  done
  return 1
}

api_once() {
  local auth=$AUTH_BASE
  [[ -n "${TOKEN:-}" ]] && auth="$auth, Token=\"$TOKEN\""
  local body; body=$(mktemp "${TMPDIR:-/tmp}/macfin-demo.XXXXXX")
  local args=(-sS -m 60 -o "$body" -w '%{http_code}' -X "$1" -H "Authorization: $auth")
  [[ $# -ge 3 ]] && args+=(-H "Content-Type: application/json" -d "$3")
  LAST_STATUS=$(curl "${args[@]}" "$SERVER$2" || echo 000)
  cat "$body"; mv -f "$body" "$DEMO/.last-response"
  if [[ "$LAST_STATUS" -ge 200 && "$LAST_STATUS" -lt 300 ]]; then return 0; fi
  [[ "$LAST_STATUS" == 503 ]] || echo "$1 $2 returned $LAST_STATUS" >&2
  return 1
}

movie_id() { api GET "/Items?userId=$USER_ID&IncludeItemTypes=Movie&Recursive=true&Fields=Path" | jq -r --arg t "$1 ($2)" '.Items[] | select(.Path | contains("/" + $t + "/")) | .Id' | head -1; }

wait_for_idle_tasks() {
  for _ in $(seq 1 300); do
    local running; running=$(api GET "/ScheduledTasks" | jq '[.[] | select(.State != "Idle")] | length')
    [[ "$running" == 0 ]] && return
    sleep 3
  done
}

cmd_setup() {
  TOKEN=""
  if [[ $(api GET "/System/Info/Public" | jq -r .StartupWizardCompleted) != true ]]; then
    log "Running the startup wizard"
    api POST "/Startup/Configuration" '{"UICulture":"en-US","MetadataCountryCode":"US","PreferredMetadataLanguage":"en"}' >/dev/null
    api GET "/Startup/User" >/dev/null
    api POST "/Startup/User" "{\"Name\":\"$DEMO_USER\",\"Password\":\"$DEMO_PASSWORD\"}" >/dev/null
    api POST "/Startup/RemoteAccess" '{"EnableRemoteAccess":false,"EnableAutomaticPortMapping":false}' >/dev/null
    api POST "/Startup/Complete" >/dev/null
  fi
  local auth; auth=$(api POST "/Users/AuthenticateByName" "{\"Username\":\"$DEMO_USER\",\"Pw\":\"$DEMO_PASSWORD\"}")
  TOKEN=$(jq -r .AccessToken <<<"$auth"); USER_ID=$(jq -r .User.Id <<<"$auth")

  log "Server settings"
  local config; config=$(api GET "/System/Configuration")
  config=$(jq '.ServerName = "Macfin Demo" | .MinResumePct = 1 | .MinResumeDurationSeconds = 10 | .EnableFolderView = false' <<<"$config")
  api POST "/System/Configuration" "$config" >/dev/null

  if [[ $(api GET "/Library/VirtualFolders" | jq 'map(select(.Name == "Movies")) | length') == 0 ]]; then
    log "Creating the Movies library (local metadata only, trickplay on)"
    local options; options=$(jq -n --arg path "$MOVIES" '{LibraryOptions: {
      PathInfos: [{Path: $path}],
      EnableRealtimeMonitor: false, EnableInternetProviders: false, SaveLocalMetadata: false,
      EnableChapterImageExtraction: false, ExtractChapterImagesDuringLibraryScan: false,
      EnableTrickplayImageExtraction: true, ExtractTrickplayImagesDuringLibraryScan: true, SaveTrickplayWithMedia: false,
      LocalMetadataReaderOrder: ["Nfo"], MetadataSavers: [],
      TypeOptions: [{Type: "Movie", MetadataFetchers: [], MetadataFetcherOrder: [], ImageFetchers: [], ImageFetcherOrder: []}]}}')
    api POST "/Library/VirtualFolders?name=Movies&collectionType=movies&refreshLibrary=true" "$options" >/dev/null
  else
    api POST "/Library/Refresh" >/dev/null
  fi

  log "Waiting for the library scan and trickplay images (a few minutes)"
  sleep 5
  wait_for_idle_tasks
  # The scan task can look idle before it has even started: wait until every movie is in the library.
  local expected; expected=$(grep -c '|' <<<"$CATALOG")
  for _ in $(seq 1 200); do
    local found; found=$(api GET "/Items?userId=$USER_ID&IncludeItemTypes=Movie&Recursive=true&Limit=0" | jq -r .TotalRecordCount)
    [[ "$found" -ge "$expected" ]] && break
    sleep 3
  done
  wait_for_idle_tasks
  local trickplay; trickplay=$(api GET "/ScheduledTasks" | jq -r '.[] | select(.Key == "RefreshTrickplayImages") | .Id')
  if [[ -n "$trickplay" ]]; then api POST "/ScheduledTasks/Running/$trickplay" >/dev/null; sleep 5; wait_for_idle_tasks; fi

  log "Runtimes (padded excerpts), progress and watched state"
  while IFS='|' read -r key title year source start frame crop poster runtime genres director plot; do
    [[ -z "$key" ]] && continue
    local id; id=$(movie_id "$title" "$year")
    [[ -z "$id" ]] && { echo "  $title: not in the library" >&2; continue; }
    printf '  %-28s %s min (expected %s)\n' "$title" "$(( $(api GET "/Items/$id?userId=$USER_ID" | jq -r .RunTimeTicks) / 600000000 ))" "$runtime"
    # Start from a clean slate, so a rerun drops any progress left by watching the demo.
    api POST "/UserItems/$id/UserData?userId=$USER_ID" '{"PlaybackPositionTicks":0,"Played":false}' >/dev/null
  done <<<"$CATALOG"

  local minutes_ago=0
  for entry in $RESUME; do
    local key=${entry%%:*} fraction=${entry#*:}
    local line; line=$(grep "^$key|" <<<"$CATALOG")
    IFS='|' read -r _ title year _ _ _ _ _ runtime _ _ _ <<<"$line"
    local id; id=$(movie_id "$title" "$year")
    local position; position=$(awk -v r="$runtime" -v f="$fraction" 'BEGIN { printf "%d", r * 60 * f * 10000000 }')
    local played; played=$(date -u -v-"${minutes_ago}"M +%Y-%m-%dT%H:%M:%S.000Z)
    api POST "/UserItems/$id/UserData?userId=$USER_ID" "{\"PlaybackPositionTicks\":$position,\"LastPlayedDate\":\"$played\",\"Played\":false}" >/dev/null
    minutes_ago=$((minutes_ago + 90))
  done
  for key in $WATCHED; do
    local line; line=$(grep "^$key|" <<<"$CATALOG")
    IFS='|' read -r _ title year _ <<<"$line"
    api POST "/UserPlayedItems/$(movie_id "$title" "$year")?userId=$USER_ID" >/dev/null
  done
  cmd_status
}

cmd_status() {
  if ! curl -fsS -m 2 "$SERVER/System/Info/Public" >/dev/null 2>&1; then log "Demo server is not running"; return; fi
  log "Demo server: $SERVER  (user \"$DEMO_USER\", password \"$DEMO_PASSWORD\")"
  if [[ -n "${TOKEN:-}" ]]; then
    api GET "/Items?userId=$USER_ID&IncludeItemTypes=Movie&Recursive=true&Fields=Trickplay" \
      | jq -r '"  \(.TotalRecordCount) movies, \([.Items[] | select(.Trickplay != null and .Trickplay != {})] | length) with trickplay"'
  fi
}

cmd_stop() {
  if [[ -f "$DEMO/jellyfin.pid" ]] && kill -0 "$(cat "$DEMO/jellyfin.pid")" 2>/dev/null; then
    kill "$(cat "$DEMO/jellyfin.pid")"
    log "Demo server stopped"
  else
    log "Demo server is not running"
  fi
  [[ -f "$DEMO/jellyfin.pid" ]] && mv "$DEMO/jellyfin.pid" "$DEMO/jellyfin.pid.old"
  return 0
}

cmd_trash_clips() {
  local clips=()
  while IFS= read -r -d '' f; do clips+=("$f"); done < <(find "$MOVIES" -name '*.mp4' -print0 2>/dev/null)
  if [[ ${#clips[@]} -eq 0 ]]; then log "No excerpts to move"; return; fi
  trash "${clips[@]}"
  log "Moved ${#clips[@]} excerpts to the Trash"
}

case "${1:-all}" in
  all) cmd_media; cmd_start; cmd_setup ;;
  media) cmd_media ;;
  start) cmd_start ;;
  setup) cmd_start; cmd_setup ;;
  status) TOKEN=""; cmd_status ;;
  stop) cmd_stop ;;
  trash-clips) cmd_trash_clips ;;
  *) sed -n '2,20p' "$0"; exit 1 ;;
esac
