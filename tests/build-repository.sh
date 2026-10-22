#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd "$(dirname "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'gpgconf --kill gpg-agent; rm -rf "$work_dir"' EXIT
export GNUPGHOME=$work_dir/gnupg
mkdir -m700 "$GNUPGHOME"
gpg --batch --passphrase '' --quick-generate-key 'APT test <test@example.invalid>' ed25519 sign 0
APT_SIGNING_KEY=$(gpg --batch --with-colons --list-secret-keys | awk -F: '$1 == "fpr" { print $10; exit }')
export APT_SIGNING_KEY
mkdir "$work_dir/release"
for arch in amd64 arm64; do
  printf '#!/bin/sh\necho "fixture %s"\n' "$arch" > "$work_dir/release/ttt-linux-$arch"
done
printf 'MIT fixture\n' > "$work_dir/release/LICENSE"
(cd "$work_dir/release"; sha256sum ttt-linux-* > checksums.txt)

for minor in 1 2 3 4 5 6; do
  "$project_dir/scripts/build-repository.sh" "$work_dir/release" "$work_dir/site" "v1.$minor.0"
done
test ! -e "$work_dir/site/pool/main/t/ttt/ttt_1.1.0-1_amd64.deb"
test "$(find "$work_dir/site/pool" -name '*.deb' | wc -l)" -eq 10
for arch in amd64 arm64; do
  package=$work_dir/site/pool/main/t/ttt/ttt_1.6.0-1_${arch}.deb
  test "$(dpkg-deb --field "$package" Architecture)" = "$arch"
  test "$(dpkg-deb --field "$package" Version)" = 1.6.0-1
  dpkg-deb --extract "$package" "$work_dir/extract-$arch"
  cmp "$work_dir/extract-$arch/usr/bin/ttt" "$work_dir/release/ttt-linux-$arch"
  test -x "$work_dir/extract-$arch/usr/bin/ttt"
  index=$work_dir/site/dists/stable/main/binary-$arch/Packages
  test "$(awk '/^Architecture:/ { print $2 }' "$index" | sort -u)" = "$arch"
  gzip -cd "$index.gz" | cmp - "$index"
done
gpg --verify "$work_dir/site/dists/stable/Release.gpg" "$work_dir/site/dists/stable/Release"
gpg --decrypt "$work_dir/site/dists/stable/InRelease" | cmp - "$work_dir/site/dists/stable/Release"
before=$(sha256sum "$work_dir/site/pool/main/t/ttt/ttt_1.6.0-1_amd64.deb")
"$project_dir/scripts/build-repository.sh" "$work_dir/release" "$work_dir/site" v1.6.0
test "$before" = "$(sha256sum "$work_dir/site/pool/main/t/ttt/ttt_1.6.0-1_amd64.deb")"

printf 'tampered\n' >> "$work_dir/release/ttt-linux-arm64"
if "$project_dir/scripts/build-repository.sh" "$work_dir/release" "$work_dir/rejected" v1.7.0; then
  echo 'Accepted a binary with the wrong checksum' >&2; exit 1
fi
test ! -e "$work_dir/rejected"
if "$project_dir/scripts/build-repository.sh" "$work_dir/release" "$work_dir/invalid" 'v1.7.0/../../bad'; then
  echo 'Accepted an invalid release tag' >&2; exit 1
fi
echo 'Package retention, architectures, signatures, and checksum rejection passed.'
