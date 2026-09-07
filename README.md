# koreader-nightly-vellum

[Vellum](https://github.com/vellum-dev/vellum) repository for
[KOReader nightly builds](https://build.koreader.rocks/download/nightly/) on
reMarkable tablets, served from <https://mirror.funami.tech/koreader-nightly/>.

Every day a GitHub Actions job looks for a new nightly, packages it for
`aarch64` (Paper Pro family) and `armv7` (reMarkable 1 and 2), signs it, and
updates the repository. The newest ten nightlies per architecture are kept.

## Installation

On the tablet:

```sh
curl -fsSL https://mirror.funami.tech/koreader-nightly/koreader-nightly.rsa.pub \
    -o /home/root/.vellum/etc/apk/keys/koreader-nightly.rsa.pub
echo https://mirror.funami.tech/koreader-nightly >> /home/root/.vellum/etc/apk/repositories
vellum update
vellum add koreader
```

The package keeps the name `koreader`. Its version is derived from the nightly
directory name, so `v2026.07.2-50-g7b0938bd8_2026-09-06` becomes
`2026.07.2_git20260906_p50`: it sorts above the Vellum release it is based on
and below the next release. While this repository is enabled, `vellum upgrade`
follows the nightlies.

To return to the release package, remove the repository line from
`/home/root/.vellum/etc/apk/repositories`, then:

```sh
vellum update
vellum del koreader
vellum add koreader
```

## How it works

`packages/koreader/VELBUILD` is the Vellum `koreader` package with the source
URLs pointed at the nightly server. The nightly it tracks is stored in the
`_nightly` variable; `pkgver` and `sha512sums` are derived from it.

`.github/workflows/nightly.yml` runs at 04:17 UTC daily and on manual dispatch:

1. **check**: reads the nightly listing, takes the newest directory that has
   both reMarkable zips, and compares it with `_nightly`. On a change it
   rewrites the VELBUILD, refreshes the checksums, and hands the file to the
   next jobs as an artifact.
2. **build**: builds each architecture with
   [vbuild](https://github.com/Eeems/vbuild), signs the package with the
   repository key, and verifies the signature.
3. **publish**: joins the tailnet, pulls the current packages from the mirror
   over SSH, adds the new ones, prunes to ten per architecture, regenerates and
   signs `APKINDEX.tar.gz`, syncs the result back, and commits the updated
   VELBUILD to `main`.

Dispatch inputs: `force` publishes even if nothing changed, and `nightly` pins
a directory name such as `v2026.07.2-50-g7b0938bd8_2026-09-06`.

### Secrets

| Secret | Value |
|---|---|
| `SIGNING_KEY` | RSA private key for `keys/koreader-nightly.rsa.pub` |
| `TS_OAUTH_CLIENT_ID`, `TS_AUDIENCE` | Tailscale trust credential with the `auth_keys` scope and `tag:ci` |
| `SSH_HOST`, `SSH_USER`, `SSH_KEY` | Mirror host login over the tailnet |
| `REMOTE_DIR` | Repository directory in the mirror webroot |

## Working locally

Requires `vbuild` and Docker or Podman. Put the private key at
`keys/koreader-nightly.rsa` (ignored by git) to sign with the repository key;
otherwise a throwaway key is generated.

```sh
./scripts/check-nightly.sh                                   # newest nightly vs. VELBUILD
./scripts/bump-velbuild.sh v2026.07.2-50-g7b0938bd8_2026-09-06
./scripts/build-package.sh aarch64                           # writes dist/aarch64/
./scripts/update-repo.sh user@host /opt/mirrorwww/koreader-nightly
```

## License

The packaging is MIT. KOReader is AGPL-3.0; its license text ships in the
package at `/home/root/.vellum/licenses/koreader/COPYING`.
