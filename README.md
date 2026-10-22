# ttt APT repository

Debian and Ubuntu packages for [ttt](https://github.com/eugenioenko/ttt), a terminal text editor. Supports amd64 and arm64.

## Installation

Install the tools used to add the repository:

```sh
sudo apt update
sudo apt install ca-certificates curl
```

Add the signing key and repository:

```sh
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://eugenioenko.github.io/apt-ttt/ttt.asc \
  | sudo tee /etc/apt/keyrings/ttt.asc > /dev/null
sudo chmod 0644 /etc/apt/keyrings/ttt.asc

sudo tee /etc/apt/sources.list.d/ttt.sources > /dev/null <<'EOF'
Types: deb
URIs: https://eugenioenko.github.io/apt-ttt
Suites: stable
Components: main
Architectures: amd64 arm64
Signed-By: /etc/apt/keyrings/ttt.asc
EOF

sudo apt update
sudo apt install ttt
```

The signing key fingerprint is `6366CC088CC2CA33DD1A94FB4459813A5CB83061`. The public key is also committed as [ttt.asc](ttt.asc).

Updates arrive through the usual `sudo apt update && sudo apt upgrade`. Git and ripgrep are recommended dependencies for source control and workspace search; APT installs them by default. Language servers remain separately installed.

If you previously installed ttt with the shell installer, check `command -v ttt`: an older copy in `~/.local/bin` or `/usr/local/bin` can take precedence over `/usr/bin/ttt`.

## Releases

[Update APT repository](https://github.com/eugenioenko/apt-ttt/actions/workflows/update-repository.yml) checks the latest stable ttt release hourly, on a `new-release` repository dispatch, and when run manually. Pushes to `main` rebuild and publish; pull requests run checks without signing credentials or publishing. GitHub can delay scheduled runs and disables schedules after 60 days without repository activity; a manual run or dispatch remains available.

The workflow downloads the Linux release binaries and verifies both against upstream `checksums.txt`, packages them with `dpkg-deb`, then generates and signs the APT indexes. The newest five versions per architecture are retained on `gh-pages`. GitHub Pages deploys the repository only after real APT install, editor startup, and removal checks pass on Debian 12/13 and Ubuntu 22.04/24.04/26.04.

No cross-repository token is required for hourly updates. To trigger an immediate update from a ttt release workflow, use a token restricted to this repository with Contents write permission:

```sh
gh api --method POST repos/eugenioenko/apt-ttt/dispatches \
  -f event_type=new-release
```

The `new-release` payload is only a wake-up signal; the workflow always resolves the latest stable release itself. To retry a failed deployment or republish the same version, run:

```sh
gh workflow run update-repository.yml --repo eugenioenko/apt-ttt
```

## Maintainer setup

GitHub Pages must use **GitHub Actions** as its publishing source. The repository needs:

- Actions secret `APT_SIGNING_PRIVATE_KEY`: the ASCII-armored private signing key, without a passphrase.
- Actions variable `APT_SIGNING_KEY`: the full fingerprint shown above.

Never commit the private key. If rotating keys, update the secret, variable, committed public key, and fingerprint; existing users must receive the replacement key before the old signature is removed.

## Local checks

Requires Bash, GnuPG, `apt-utils`, `dpkg`, and ShellCheck. Docker is needed for the real installation checks.

```sh
shellcheck scripts/*.sh tests/*.sh
tests/build-repository.sh
```

With a downloaded release in `downloads/` (the two Linux binaries, `checksums.txt`, and the tagged source's `LICENSE`), and the signing key imported into an isolated `GNUPGHOME`:

```sh
export APT_SIGNING_KEY=6366CC088CC2CA33DD1A94FB4459813A5CB83061
scripts/build-repository.sh downloads _site v1.8.0
tests/apt-install.sh debian:bookworm-slim _site
tests/apt-install.sh debian:trixie-slim _site
tests/apt-install.sh ubuntu:22.04 _site
tests/apt-install.sh ubuntu:24.04 _site
tests/apt-install.sh ubuntu:26.04 _site
```

Installation tests run without network access and trust only the generated repository key. CI currently executes amd64 packages; both architecture packages and indexes are checked by the packaging tests.
