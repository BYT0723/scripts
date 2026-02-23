#!/bin/bash

random() {
	local dir=$1
	local len=${2:-10}

	[ -z "$dir" ] && echo "Usage: $(basename $0) <dir> [len]" && exit 1
	[ ! -d "$dir" ] && echo "$dir is not a directory" && exit 1

	[[ "$dir" != /* ]] && dir=$(realpath "$dir")

	cd $dir
	mpv \
		--really-quiet \
		--playlist=<(
			find "$dir" -type f \
				\( -iname "*.mp4" -o -iname "*.avi" -o -iname "*.mkv" -o -iname "*.mov" \) \
				-print0 |
				shuf -z -n "$len" |
				tr '\0' '\n'
		)
}

recency_random() {
	local dir=$1
	local len=${2:-10}
	local recent_day=${3:-90}

	[ -z "$dir" ] && echo "Usage: $(basename $0) <dir> [len]" && exit 1
	[ ! -d "$dir" ] && echo "$dir is not a directory" && exit 1

	[[ "$dir" != /* ]] && dir=$(realpath "$dir")

	cd $dir

	# 衰减时间常数（秒）
	# 7天 = 偏向最近内容
	tau=$((86400 * recent_day))

	playlist=$(
		find "$dir" -type f \
			\( -iname "*.mp4" -o -iname "*.avi" -o -iname "*.mkv" -o -iname "*.mov" \) \
			-printf "%T@|%p\n" |
			awk -F'|' -v N="$len" -v tau="$tau" '
				BEGIN {
					srand()
				}

				{
					t[NR]=$1
					f[NR]=$2
				}

				END {
					now=systime()

					# 计算指数权重
					total=0
					for(i=1;i<=NR;i++){
						w[i]=exp((t[i]-now)/(tau*0.5))
						total+=w[i]
					}

					# 不重复抽样
					for(k=0;k<N && total>0;k++){
						r=rand()*total
						acc=0

						for(i=1;i<=NR;i++){
							acc+=w[i]
							if(acc>=r){
								print f[i]
								total-=w[i]
								w[i]=0
								break
							}
						}
					}
				}'
	)

	mpv --really-quiet --playlist=<(echo "$playlist")
}

case "$1" in
"recent")
	shift
	recency_random $@
	;;
*)
	random $@
	;;
esac
