wallpaper_launch_delay=1

# wallpaper configuration file
conf="$HOME/.config/dwm/wallpaper.json"
cache_wallpaper_dir="$HOME/.cache/wallpaper"
mkdir -p "$cache_wallpaper_dir"

# Create default config if missing
[ ! -f "$conf" ] && jq -n '{
	defaults: {
		random: 0,
		random_type: "image",
		random_image_dir: "~/Pictures",
		random_video_dir: "~/Videos",
		video_keymap_conf: "~/.config/dwm/wallpaperKeyMap.conf",
		duration: 30,
		random_depth: 3
	},
	monitors: {}
}' >"$conf"

wallpaper_latest="$cache_wallpaper_dir/wallpaper_latest"
wallpaper_full_latest="${wallpaper_latest}_full"
wallpaper_pid="$cache_wallpaper_dir/wallpaper_pid"
wallpaper_full_pid="${wallpaper_pid}_full"
rotation_cache="$cache_wallpaper_dir/rotation_cache"

# Define the default configuration
declare -A config
config["random"]=0
config["random_type"]="image"
config["random_image_dir"]="~/Pictures"
config["random_video_dir"]="~/Videos"
config["random_depth"]=3
config["duration"]=30
cmd="feh --no-fehbg --bg-scale /usr/share/backgrounds/archlinux/small.png"

# Get configuration value by key, with fallback to defaults
# Usage: getConfig [-m <monitor>] <key>
getConfig() {
	local monitor=""
	[ "$1" = "-m" ] && monitor="$2" && shift 2
	local key="$1"

	if [ -f "$conf" ]; then
		# "ALL" uses defaults directly
		if [ "$monitor" != "ALL" ] && [ -n "$monitor" ]; then
			local val=$(jq -r ".monitors[\"$monitor\"].\"$key\" // empty" "$conf" 2>/dev/null)
			[ -n "$val" ] && echo "$val" && return
		fi
		# Try defaults
		local val=$(jq -r ".defaults.\"$key\" // empty" "$conf" 2>/dev/null)
		[ -n "$val" ] && echo "$val" && return
	fi

	# Hardcoded fallback
	echo "${config[$key]}"
}

# Utility functions
expand_path() {
	local path="$1"
	path=$(printf '%s\n' "$path" | envsubst)
	echo "${path/#\~/$HOME}"
}

detect_file_type() {
	local filepath="$1"
	local baseFilename=$(basename "${filepath// /_}")
	local Type="${baseFilename##*.}"

	case "$Type" in
	mp4 | mkv | avi | webm) echo "video" ;;
	jpg | jpeg | png) echo "image" ;;
	html | htm) echo "page" ;;
	*) echo "page" ;;
	esac
}

get_video_dim() {
	local file="$1"
	ffprobe -v error -select_streams v:0 \
		-show_entries stream=width,height \
		-of csv=p=0 "$file" 2>/dev/null | tr ',' ' '
}

# Returns 0 (true) if monitor and video have different orientation (landscape vs portrait)
orientation_mismatch() {
	local mw="$1" mh="$2" vw="$3" vh="$4"
	local ml=false vl=false
	[ "$mw" -gt "$mh" ] && ml=true
	[ "$vw" -gt "$vh" ] && vl=true
	[ "$ml" != "$vl" ]
}

# Returns "width height" for the selected monitor (or screen)
get_monitor_dim() {
	local select="$1" list="$2"
	if [[ "$select" == "Screen" ]]; then
		get_screen_size | sed 's/\([0-9]*\)x\([0-9]*\).*/\1 \2/'
	else
		local mon="$select"
		[[ "$mon" == "ALL" ]] && mon=$(echo "$list" | awk 'NR>1 {print $NF; exit}')
		xrandr --current | awk -v m="$mon" '
			$1==m {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+x[0-9]+/) {split($i,a,"[x+]"); print a[1], a[2]; exit}}
		'
	fi
}

# Launch mpv preview with r=cycle rotation, q=quit; returns final rotation angle
preview_rotation() {
	local file="$1"
	local tmp=$(mktemp -d)
	local wld="$tmp/watch_later"
	mkdir -p "$wld"
	cat >"$tmp/input.conf" <<'EOF'
r cycle-values video-rotate "90" "270" "0"
q quit
EOF
	mpv \
		--no-config \
		--no-osc \
		--video-rotate=90 \
		--loop \
		--mute \
		--audio-client-name=wallpaper \
		--input-conf="$tmp/input.conf" \
		--save-position-on-quit \
		--watch-later-directory="$wld" \
		--watch-later-options="video-rotate" \
		--autofit=800x600 \
		"$file" &>/dev/null
	local rotate="90"
	for f in "$wld"/*; do
		[ -f "$f" ] && rotate=$(grep "^video-rotate=" "$f" | cut -d= -f2) && break
	done
	rm -rf "$tmp"
	echo "${rotate:-90}"
}

find_wallpapers() {
	local dir="$1"
	local depth="$2"
	local pattern="$3" # regex pattern for file extensions

	# Expand path
	dir=$(expand_path "$dir")

	if [ ! -d "$dir" ]; then
		error "Directory does not exist: $dir"
		return 1
	fi

	# Use mapfile to read all matching files into array
	local files=()
	if ! mapfile -t files < <(find "$dir" -maxdepth "$depth" -type f -regextype posix-extended -regex "$pattern" 2>/dev/null); then
		error "Failed to search for wallpapers in $dir"
		return 1
	fi

	if [ ${#files[@]} -eq 0 ]; then
		error "No matching wallpapers found in $dir"
		return 1
	fi

	# Output each file on a new line
	printf '%s\n' "${files[@]}"
}

check_command() {
	local cmd="$1"
	local friendly_name="$2"

	if ! command -v "$cmd" >/dev/null 2>&1; then
		error "Command '$cmd' not found. Please install $friendly_name"
		return 1
	fi
	return 0
}

safe_kill_pidfile() {
	local pidfile="$1"
	local signal="${2:-TERM}"

	if [ -f "$pidfile" ]; then
		local pid=$(cat "$pidfile" 2>/dev/null)
		if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
			kill -"$signal" "$pid" 2>/dev/null
			sleep 0.1
			if kill -0 "$pid" 2>/dev/null; then
				kill -KILL "$pid" 2>/dev/null
			fi
		fi
		rm -f "$pidfile"
	fi
}

TERM=${TERMINAL:-"kitty --class float-term -o font_size=8 -o initial_window_width=160c -o initial_window_height=48c"}

handle_error() {
	local level="$1" # error, warning, info
	local message="$2"
	local exit_code="${3:-0}"

	case "$level" in
	"error")
		echo -e "\033[31mError: $message\033[0m" >&2
		# Use existing system-notify function if available
		if command -v system-notify >/dev/null 2>&1; then
			system-notify critical "Wallpaper Error" "$message"
		fi
		;;
	"warning")
		echo -e "\033[33mWarning: $message\033[0m" >&2
		if command -v system-notify >/dev/null 2>&1; then
			system-notify normal "Wallpaper Warning" "$message"
		fi
		;;
	"info")
		echo -e "\033[32mInfo: $message\033[0m"
		if command -v system-notify >/dev/null 2>&1; then
			system-notify low "Wallpaper Info" "$message"
		fi
		;;
	esac

	[ "$exit_code" -ne 0 ] && exit "$exit_code"
}

error() {
	handle_error "error" "$1" "${2:-0}"
}

# print help information
echo_help() {
	echo -e "Help Message"
	echo "      -r | --run             run wallpaper daemon"
	echo "      -s | --set <path>      set wallpaper (prompts monitor)"
	echo "      -n | --next            random next (prompts monitor)"
	echo "      -S | --select          interactive: monitor -> action"
	echo "      -m <mon> <next|select> apply to specific monitor"
}

clean_latest() {
	local monitor_index=$1

	# 开启 nullglob，保证通配符为空时不会报错
	shopt -s nullglob

	# Clean up full screen wallpaper
	safe_kill_pidfile "$wallpaper_full_pid"
	[ -f "$wallpaper_full_latest" ] && rm -f "$wallpaper_full_latest"

	local files=()
	if [ -n "$monitor_index" ]; then
		files=("${wallpaper_pid}_${monitor_index}")
	else
		files=("${wallpaper_pid}"_*)
	fi

	# 遍历每个匹配文件
	for f in "${files[@]}"; do
		[ ! -f "$f" ] && continue
		safe_kill_pidfile "$f"
		# Remove corresponding latest file
		local latest_file="${f/$wallpaper_pid/$wallpaper_latest}"
		[ -f "$latest_file" ] && rm -f "$latest_file"
	done
}

get_screen_size() {
	xrandr | awk -F',' '{for(i=1;i<=NF;i++) if($i ~ /current/) print $i}' | awk '{print $2 $3 $4}'
}
