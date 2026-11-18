#!/usr/bin/env bash
set -euo pipefail

input_dir="$HOME/Downloads"
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="$repo_dir/client/art/sound/cnr"
scratch_dir=$(mktemp -d "$repo_dir/.thunder-cut.XXXXXXXXXX")
trap 'rm -rf -- "$scratch_dir"' EXIT

cut() {
  local source="$1" name="$2" start="$3" end="$4" fade_in="$5" fade_out="$6" drive_db="${7:-11}"
  local pcm="$scratch_dir/trimmed.wav"
  local peak gain fade_out_start
  ffmpeg -nostats -loglevel error -y -i "$input_dir/$source" \
    -af "atrim=$start:$end,asetpts=PTS-STARTPTS,pan=mono|c0=0.5*c0+0.5*c1,aresample=48000,highpass=f=40" \
    -c:a pcm_f32le "$pcm"
  peak=$(ffmpeg -hide_banner -nostats -i "$pcm" -af volumedetect -f null - 2>&1 |
    sed -n 's/.*max_volume: \(-*[0-9.]*\) dB/\1/p')
  gain=$(python3 -I -c 'import sys; drive, peak = map(float, sys.argv[1:]); print(round(drive - peak, 2))' "$drive_db" "$peak")
  fade_out_start=$(python3 -I -c 'import sys; end, start, fade = map(float, sys.argv[1:]); print(round(end - start - fade, 3))' \
    "$end" "$start" "$fade_out")
  local dynamics="alimiter=limit=1:attack=2:release=20:level=0:latency=1:level_out=2,asoftclip=type=tanh:output=0.76"
  local fades="afade=t=in:st=0:d=$fade_in,afade=t=out:st=$fade_out_start:d=$fade_out"
  ffmpeg -nostats -loglevel error -y -i "$pcm" -af "volume=${gain}dB,$dynamics,$fades" \
    -c:a pcm_f32le "$scratch_dir/$name.wav"
  printf '%s: peak %s dBFS, gain %s dB\n' "$name" "$peak" "$gain"
}

bajko=399656__bajko__sfx_thunder-blast.wav
mikala=347562__mikala_oidua__distant-thunder-clap_gentle.wav
trp=717845__trp__230405-thunder-dry-rolling-distant-low-rumbles-roof-em272s-toronto-7am.mp3

cut "$bajko" thunder_close_1 0 15 0.01 3 19
ffmpeg -nostats -loglevel error -y -i "$scratch_dir/thunder_close_1.wav" \
  -af "asetrate=44160,aresample=48000" -c:a pcm_f32le "$scratch_dir/thunder_close_2.wav"
cut "$mikala" thunder_medium_1 0 18.4 0.05 2
cut "$trp" thunder_far_1 2 8 0.3 1.5
cut "$trp" thunder_far_2 44.5 57 0.3 1.5
cut "$trp" thunder_far_3 59.7 65 0.3 1.5
cut "$trp" thunder_far_4 69.5 74 0.3 1.5
cut "$trp" thunder_far_5 76.7 90 0.3 1.5
cut "$trp" thunder_far_6 125.7 135.5 0.3 1.5
cut "$trp" thunder_far_7 146.7 161 0.3 1.5

for pcm in "$scratch_dir"/thunder_*.wav; do
  ffmpeg -nostats -loglevel error -y -i "$pcm" -c:a libvorbis -q:a 5 -fflags +bitexact "${pcm%.wav}.ogg"
done

mv -f -- "$scratch_dir"/thunder_*.ogg "$output_dir/"
