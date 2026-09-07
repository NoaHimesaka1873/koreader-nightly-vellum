# koreader-nightly-vellum

A [Vellum](https://github.com/vellum-dev/vellum) (apk) repository that tracks
[KOReader nightly builds](https://build.koreader.rocks/download/nightly/) for
reMarkable tablets. A GitHub Actions cron checks the KOReader build server
daily, and when a new nightly with reMarkable builds appears it packages it for
`aarch64` (Paper Pro family) and `armv7` (rM1/rM2), signs it, and publishes it
to <https://mirror.funami.tech/koreader-nightly/>.

The package is named `koreader`, same as the Vellum one, with a version like
`2026.07.2_git20260906_p50` (base tag, nightly date, commits since the tag).
That version always sorts above the matching Vellum release and below the next
one, so with this repository enabled `vellum upgrade` follows the nightlies.

## Using the repository

On the tablet, install the signing key and add the repository:

```sh
curl -fsSL https://mirror.funami.tech/koreader-nightly/koreader-nightly.rsa.pub \
  -o /home/root/.vellum/etc/apk/keys/koreader-nightly.rsa.pub
echo https://mirror.funami.tech/koreader-nightly >> /home/root/.vellum/etc/apk/repositories
vellum update
vellum add koreader
```

To go back to the stable Vellum package, remove the line from
`/home/root/.vellum/etc/apk/repositories`, then `vellum update` and
`vellum add koreader@vellum` (or `vellum del koreader && vellum add koreader`).

Only the newest 10 nightlies per architecture are kept on the mirror.

## Layout

```
packages/koreader/VELBUILD     # tracks one nightly via _nightly= (rewritten by CI)
packages/koreader/KOReader.oxide
keys/koreader-nightly.rsa.pub  # repository public key (private key is the SIGNING_KEY secret)
scripts/check-nightly.sh       # newest nightly with both reMarkable zips vs. VELBUILD
scripts/bump-velbuild.sh       # rewrite _nightly/pkgver and refresh sha512sums with vbuild
scripts/build-package.sh       # vbuild one arch into dist/<arch>/
scripts/update-repo.sh         # merge into the mirror, prune, rebuild + sign APKINDEX
.github/workflows/nightly.yml  # cron: check -> build (matrix) -> publish
```

## Workflow

`nightly.yml` runs daily at 04:17 UTC and on `workflow_dispatch`:

1. **check** – finds the newest nightly directory whose
   `koreader-remarkable-aarch64-*.zip` and `koreader-remarkable-*.zip` both
   exist, compares it with `_nightly=` in the VELBUILD, and if it changed runs
   `bump-velbuild.sh` (checksums via `vbuild checksum`) and uploads the VELBUILD
   as an artifact.
2. **build** – builds `aarch64` and `armv7` with [vbuild](https://github.com/Eeems/vbuild),
   signs with the repository key, verifies the signatures.
3. **publish** – joins the tailnet with the Tailscale GitHub Action, pulls the
   existing apks from the mirror over SSH, adds the new ones, prunes to the
   newest 10, regenerates and signs `APKINDEX.tar.gz`, pushes everything back
   with rsync, and commits the updated VELBUILD to `main`.

Dispatch inputs: `force` rebuilds even when nothing changed; `nightly` pins a
specific directory name such as `v2026.07.2-50-g7b0938bd8_2026-09-06`.

### Secrets

| Secret | Purpose |
|---|---|
| `SIGNING_KEY` | RSA private key matching `keys/koreader-nightly.rsa.pub` |
| `TS_OAUTH_CLIENT_ID`, `TS_AUDIENCE` | Tailscale federated identity (same as arch-mact2-PKGBUILDs) |
| `SSH_HOST`, `SSH_USER`, `SSH_KEY` | mirror host login (same as arch-mact2-PKGBUILDs) |
| `REMOTE_DIR` | `/opt/mirrorwww/koreader-nightly` |

## Local use

Requires `vbuild` and docker/podman. The private key goes in
`keys/koreader-nightly.rsa` (git-ignored); without it a throwaway dev key is
generated.

```sh
./scripts/check-nightly.sh                       # what would be built
./scripts/bump-velbuild.sh v2026.07.2-50-g7b0938bd8_2026-09-06
./scripts/build-package.sh aarch64               # -> dist/aarch64/*.apk
./scripts/update-repo.sh user@mirror /opt/mirrorwww/koreader-nightly
```

## License

Packaging is MIT. KOReader itself is AGPL-3.0; its license is installed to
`/home/root/.vellum/licenses/koreader/COPYING`.
