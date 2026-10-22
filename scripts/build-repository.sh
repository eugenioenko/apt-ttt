#!/usr/bin/env bash
set -euo pipefail

release_dir=$(realpath "${1:?usage: build-repository.sh RELEASE_DIR REPOSITORY_DIR TAG}")
repository_dir=$(realpath -m "${2:?missing repository directory}")
tag=${3:?missing release tag}
: "${APT_SIGNING_KEY:?set APT_SIGNING_KEY to the signing key fingerprint}"
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Expected a stable vX.Y.Z release" >&2; exit 1; }
version=${tag#v}-1

for arch in amd64 arm64; do
  binary=ttt-linux-$arch
  checksum=$(awk -v name="$binary" '$2 == name { print $1 }' "$release_dir/checksums.txt")
  [[ "$checksum" =~ ^[a-f0-9]{64}$ ]] || { echo "Missing or invalid checksum for $binary" >&2; exit 1; }
  (cd "$release_dir"; printf '%s  %s\n' "$checksum" "$binary" | sha256sum --check --strict)
done
test -s "$release_dir/LICENSE"
gpg --batch --list-secret-keys "$APT_SIGNING_KEY" >/dev/null

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$repository_dir/pool/main/t/ttt"
for arch in amd64 arm64; do
  package=$repository_dir/pool/main/t/ttt/ttt_${version}_${arch}.deb
  if [[ ! -f "$package" ]]; then
    root=$work_dir/$arch
    install -Dm755 "$release_dir/ttt-linux-$arch" "$root/usr/bin/ttt"
    install -Dm644 "$release_dir/LICENSE" "$root/usr/share/doc/ttt/copyright"
    mkdir -p "$root/DEBIAN"
    cat > "$root/DEBIAN/control" <<EOF
Package: ttt
Version: $version
Architecture: $arch
Maintainer: Eugene Yakhnenko <eugenioenko@gmail.com>
Section: editors
Priority: optional
Homepage: https://tttedit.dev
Recommends: git, ripgrep
Installed-Size: $(du -sk "$root/usr" | cut -f1)
Description: Terminal text editor
 A terminal text editor with syntax highlighting, Git integration,
 language server support, and Lua plugins.
EOF
    dpkg-deb --root-owner-group -Zxz --build "$root" "$package"
  fi
  mapfile -t packages < <(find "$repository_dir/pool" -name "ttt_*_${arch}.deb" | sort -V)
  for ((i = 0; i < ${#packages[@]} - 5; i++)); do
    rm "${packages[$i]}"
  done
done

cd "$repository_dir"
for arch in amd64 arm64; do
  index=dists/stable/main/binary-$arch
  mkdir -p "$index"
  apt-ftparchive --arch "$arch" packages pool > "$index/Packages"
  gzip -n -9 -c "$index/Packages" > "$index/Packages.gz"
done

# Exclude the previous signatures and Release file from the new index checksums.
rm -f dists/stable/Release dists/stable/Release.gpg dists/stable/InRelease
apt-ftparchive \
  -o APT::FTPArchive::Release::Origin=ttt \
  -o APT::FTPArchive::Release::Label=ttt \
  -o APT::FTPArchive::Release::Suite=stable \
  -o APT::FTPArchive::Release::Codename=stable \
  -o 'APT::FTPArchive::Release::Architectures=amd64 arm64' \
  -o APT::FTPArchive::Release::Components=main \
  -o 'APT::FTPArchive::Release::Description=ttt Debian and Ubuntu packages' \
  release dists/stable > "$work_dir/Release"
mv "$work_dir/Release" dists/stable/Release
gpg --batch --yes --local-user "$APT_SIGNING_KEY" --armor --detach-sign \
  --output dists/stable/Release.gpg dists/stable/Release
gpg --batch --yes --local-user "$APT_SIGNING_KEY" --clearsign \
  --output dists/stable/InRelease dists/stable/Release
gpg --batch --armor --export "$APT_SIGNING_KEY" > ttt.asc
gpg --batch --verify dists/stable/InRelease
printf '%s\n' "$tag" > version
touch .nojekyll
cat > index.html <<EOF
<!doctype html>
<html lang="en"><meta charset="utf-8"><title>ttt APT repository</title>
<h1>ttt APT repository</h1><p>Latest release: $tag (amd64 and arm64).</p>
<p><a href="https://github.com/eugenioenko/apt-ttt#installation">Installation instructions</a></p>
<p><a href="ttt.asc">Signing key</a> · <a href="dists/stable/InRelease">Signed index</a></p>
</html>
EOF
