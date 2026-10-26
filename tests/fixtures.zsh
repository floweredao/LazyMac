# Source after defining REPO and TMP. All synced data is fake and stays under .work/.
seed_data() {
  export LAZYMAC_DATA=$TMP/data LAZYMAC_STORAGE_CONF=$TMP/storage.conf LAZYMAC_HOST=Example-Mac
  mkdir -p "$LAZYMAC_DATA" "$TMP/storage"
  cp -R "$REPO/example/." "$LAZYMAC_DATA/"
  printf 'backend local\nlocal %s\nfiles off\ndata %s\n' "$TMP/storage" "$LAZYMAC_DATA" > "$LAZYMAC_STORAGE_CONF"
  bun "$REPO/bin/catalog.ts" render >/dev/null
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
