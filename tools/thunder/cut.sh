#!/usr/bin/env bash
set -euo pipefail

input_dir="$HOME/Downloads"
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="$repo_dir/client/art/sound/cnr"
scratch_dir=$(mktemp -d "$repo_dir/.thunder-cut.XXXXXXXXXX")
trap 'rm -rf -- "$scratch_dir"' EXIT

normalize() {
  local name="$1"
  local pcm="$scratch_dir/$name.wav"
  local peak gain
  peak=$(ffmpeg -hide_banner -nostats -i "$pcm" -af volumedetect -f null - 2>&1 |
    sed -n 's/.*max_volume: \(-*[0-9.]*\) dB/\1/p')
  gain=$(python3 -I -c 'import sys; print(round(1.8 - float(sys.argv[1]), 2))' "$peak")
  ffmpeg -nostats -loglevel error -y -i "$pcm" -af "volume=${gain}dB,alimiter=limit=0.84:attack=2:release=50:level=0:latency=1" \
    -c:a libvorbis -q:a 5 "$scratch_dir/$name.ogg"
  printf '%s: peak %s dBFS, gain %s dB\n' "$name" "$peak" "$gain"
}

cut() {
  local source="$1" name="$2" start="$3" end="$4" fade_in="$5" fade_out="$6"
  local fade_out_start
  fade_out_start=$(python3 -I -c 'import sys; end, start, fade = map(float, sys.argv[1:]); print(round(end - start - fade, 3))' \
    "$end" "$start" "$fade_out")
  ffmpeg -nostats -loglevel error -y -i "$input_dir/$source" \
    -af "atrim=$start:$end,asetpts=PTS-STARTPTS,pan=mono|c0=0.5*c0+0.5*c1,afade=t=in:st=0:d=$fade_in,afade=t=out:st=$fade_out_start:d=$fade_out,aresample=48000" \
    -c:a pcm_f32le "$scratch_dir/$name.wav"
  normalize "$name"
}

bajko=399656__bajko__sfx_thunder-blast.wav
mikala=347562__mikala_oidua__distant-thunder-clap_gentle.wav
trp=717845__trp__230405-thunder-dry-rolling-distant-low-rumbles-roof-em272s-toronto-7am.mp3

cut "$bajko" thunder_close_1 0 15 0.01 3
ffmpeg -nostats -loglevel error -y -i "$scratch_dir/thunder_close_1.wav" \
  -af "asetrate=44160,aresample=48000" -c:a pcm_f32le "$scratch_dir/thunder_close_2.wav"
normalize thunder_close_2
cut "$mikala" thunder_medium_1 0 18.4 0.05 2
cut "$trp" thunder_far_1 2 8 0.3 1.5
cut "$trp" thunder_far_2 44.5 57 0.3 1.5
cut "$trp" thunder_far_3 59.7 65 0.3 1.5
cut "$trp" thunder_far_4 69.5 74 0.3 1.5
cut "$trp" thunder_far_5 76.7 90 0.3 1.5
cut "$trp" thunder_far_6 125.7 135.5 0.3 1.5
cut "$trp" thunder_far_7 146.7 161 0.3 1.5

mv -f -- "$scratch_dir"/thunder_*.ogg "$output_dir/"
