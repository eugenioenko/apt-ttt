#!/usr/bin/env bash
set -euo pipefail
image=${1:?usage: apt-install.sh IMAGE REPOSITORY_DIR}
repository_dir=$(realpath "${2:?missing repository directory}")
docker run --rm --network none --env DEBIAN_FRONTEND=noninteractive \
  --mount "type=bind,source=$repository_dir,target=/repo,readonly" \
  "$image" sh -eu -c '
    printf "Types: deb\nURIs: file:/repo\nSuites: stable\nComponents: main\nSigned-By: /repo/ttt.asc\n" > /tmp/ttt.sources
    apt_ttt() {
      apt-get -o Dir::Etc::sourcelist=/tmp/ttt.sources -o Dir::Etc::sourceparts=- "$@"
    }
    apt_ttt update
    apt_ttt install -y --no-install-recommends ttt
    ttt --version | grep -F "$(cat /repo/version)"
    printf "APT package smoke test\n" > /tmp/apt-test.txt
    TTT_CONFIG_DIR=/tmp/ttt-config ttt /tmp/apt-test.txt --size 80x24 \
      --exec "wait-for APT package smoke test; screenshot /tmp/screen.txt; quit"
    grep -F "APT package smoke test" /tmp/screen.txt
    apt_ttt remove -y ttt
    test ! -e /usr/bin/ttt
  '
