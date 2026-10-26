# Source after defining REPO and TMP. All synced data is fake and stays under .work/.
seed_data() {
  export LAZYMAC_DATA=$TMP/data LAZYMAC_STORAGE_CONF=$TMP/storage.conf LAZYMAC_HOST=Example-Mac
  mkdir -p "$LAZYMAC_DATA" "$TMP/storage"
  cp -R "$REPO/example/." "$LAZYMAC_DATA/"
  printf 'backend local\nlocal %s\nfiles off\ndata %s\n' "$TMP/storage" "$LAZYMAC_DATA" > "$LAZYMAC_STORAGE_CONF"
  fake_defaults
  bun "$REPO/bin/catalog.ts" render >/dev/null
}

# bin/settings.sh reads macOS settings through LAZYMAC_DEFAULTS: answer from a fixed table, never this Mac's.
fake_defaults() {
  export LAZYMAC_DEFAULTS=$TMP/defaults
  print -r -- '#!/bin/zsh
typeset -A kind=(com.apple.dock/autohide boolean com.apple.dock/tilesize float com.apple.finder/ShowPathbar boolean)
typeset -A value=(com.apple.dock/autohide 1 com.apple.dock/tilesize 48 com.apple.finder/ShowPathbar 0)
k=$2/$3
[[ -n ${kind[$k]:-} ]] || { print -u2 "The domain/default pair of ($2, $3) does not exist"; exit 1; }
case $1 in
  read-type) print -r -- "Type is ${kind[$k]}" ;;
  read) print -r -- "${value[$k]}" ;;
  *) exit 1 ;;
esac' > "$LAZYMAC_DEFAULTS"
  chmod +x "$LAZYMAC_DEFAULTS"
}

seed_inventory() {
  local dir=$1
  mkdir -p "$dir"
  printf 'ExampleNotes\tmanual\t1\t-\nExampleSketch\tmanual\t1\t-\nExampleReader\tmanual\t1\t-\nExampleTimer\tmanual\t1\t-\nExampleStore\tmas\t1\t-\n' > "$dir/apps.tsv"
  printf 'brew "gh"\nbrew "colima"\nbrew "rust-analyzer"\n' > "$dir/Brewfile"
  printf 'gh\ncolima\nrust-analyzer\n' > "$dir/brew-leaves.tsv"
  printf '## npm\nexample-cli@1.0\nnpm@10.0\n' > "$dir/cli-global.txt"
  printf 'user\tlocal.lazymac-daily\n' > "$dir/launchd.tsv"
  printf 'ExampleSans\n' > "$dir/fonts.txt"
  printf '123 ExampleStore\n' > "$dir/mas.txt"
}
