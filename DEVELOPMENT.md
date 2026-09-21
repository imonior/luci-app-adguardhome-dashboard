[🇨🇳 中文开发说明](DEVELOPMENT.zh-CN.md) · [🇺🇸 English README](README.md) · [🇨🇳 中文 README](README.zh-CN.md)

# Development

> This document is for developers: the local test package, translation build, and release procedure. End users should read [README.md](README.md) (English) or [README.zh-CN.md](README.zh-CN.md) (Chinese).

---

## 1. `changes_package/` local test package

`changes_package/` is a deployment bundle for **manually uploading to the router for local testing only**. It is **never pushed to the GitHub repo** (blocked by `.gitignore`). It must stay **byte-for-byte identical** to the files under `files/` — the official release path is the in-panel "Check panel update → Upgrade panel" flow; `changes_package/` is only for local verification when network access is inconvenient.

After any change to `files/`, you must `cp` it into the matching `changes_package/` file, confirm with `diff -q`, then deploy to the router via `changes_package/deploy_atomic.sh`. Otherwise the router runs the old version and your test does not reflect your change.

`changes_package/` contains: `adguardhome.lua`, `dashboard.js`, `*.lmo`, `*.po`, `deploy_atomic.sh`, each corresponding one-to-one to the main files in `files/`.

---

## 2. Editing translations

Translation sources are `files/luci/i18n/adguardhome.po` (English) and `files/luci/i18n/adguardhome.zh-cn.po` (Chinese). After editing a `.po` you must recompile it into the LuCI binary format `.lmo`:

```sh
python3 tools/po2lmo.py files/luci/i18n/adguardhome.po files/luci/i18n/adguardhome.lmo
python3 tools/po2lmo.py files/luci/i18n/adguardhome.zh-cn.po files/luci/i18n/adguardhome.zh-cn.lmo
```

> `po2lmo.py` is dev-only and is not deployed to the router.

> **LuCI loads the `.lmo`, never the `.po`** — a corrected `.po` without a recompiled `.lmo` changes nothing on the router. The release gate enforces this: `scripts/release.sh` compiles each `.po` on the fly and fails if the committed `.lmo` is not byte-identical. It also fails on untranslated English entries (`msgstr` still Chinese), on en/zh-cn msgid drift, and on gaps in the view's fallback `_EN` dictionary.

---

## 3. Releasing a new version

1. Edit source files under `files/`.
2. Recompile `.po` → `.lmo` (see above).
3. **Bump the version in all four places.** The pre-push check enforces this — missing any one of them fails the release:
   - `manifest.json` → `"version"` (the runtime single source of truth: `adguardhome.lua` reads the deployed `/usr/share/adguardhome-dashboard/manifest.json` to learn the installed version)
   - `files/view/dashboard.js` → `DASHBOARD_VIEW_VERSION` (the baseline the anti-stale-view self-heal compares against)
   - `README.md` / `README.zh-CN.md` → the `**vX.Y.Z**` heading near the top of each file
   - `README.md` / `README.zh-CN.md` → a `- **vX.Y.Z**` changelog entry (English first, Chinese companion)

4. **Regenerate the content-fingerprint manifest** (required after ANY change to files under `files/`; otherwise install/panel-upgrade will abort with a sha256 mismatch):
   ```sh
   sha256sum files/luci/acl.json \
             files/luci/controller/adguardhome.lua \
             files/luci/i18n/adguardhome.lmo \
             files/luci/i18n/adguardhome.zh-cn.lmo \
             files/luci/i18n/adguardhome.po \
             files/luci/i18n/adguardhome.zh-cn.po \
             files/luci/menu.d/luci-app-adguardhome-dashboard.json \
             files/view/dashboard.js \
             manifest.json > checksums.sha256
   sha256sum -c checksums.sha256      # must be 9/9 OK before you go on
   ```

5. Sync the local test bundle: `cp` every changed file into `changes_package/` and confirm with `diff -q` (see §1).
6. **Run the pre-push check** — it must pass before you push:

   ```sh
   sh scripts/release.sh --check
   ```

   It enforces version consistency (all four places above), bilingual changelog entries, code syntax (`sh -n` / `node --check` / `luac -p`), the `checksums.sha256` fingerprint and the `changes_package/` sync. CI runs the same script as `--check --strict`, so anything it catches locally would abort the release too.

7. `git add files/ checksums.sha256 manifest.json README.md README.zh-CN.md && git commit -m "release: vX.Y.Z — …" && git push origin main`

   After pushing to main, every router can click "Check panel update" to see the new version and upgrade online.

8. Tag and push to publish the offline installer as a release asset:

   ```sh
   git tag vX.Y.Z && git push origin main --tags
   ```

   `.github/workflows/release.yml` then checks out the tag, runs `sh scripts/release.sh --check --strict`, builds the tarball with `scripts/make_package.sh` and attaches it to the GitHub Release.

   > The tarball is a **lean offline installer** — deployable files, installer, `manifest.json`, `checksums.sha256`, `OFFLINE_PACKAGE` and `INSTALL.md` only. Documentation (README/LICENSE/DEVELOPMENT) is deliberately **not** bundled: the complete project source is the auto-generated *Source code* archive attached to every release.

   > **The tag version must match `manifest.json`.** The panel reads the deployed `manifest.json` to learn the installed version, so a mismatch makes "Check panel update" compare against the wrong number.

---

## 4. Offline install package

`scripts/make_package.sh` builds a self-contained tarball that installs with **zero network access**:

```sh
sh scripts/make_package.sh      # -> dist/luci-app-adguardhome-dashboard-vX.Y.Z.tar.gz
```

Layout — exactly the installer-relevant subset of the repo (documentation is intentionally **not** bundled), so `install.sh`'s existing "install using local files" branch is reused with no separate offline installer to maintain:

```
luci-app-adguardhome-dashboard-vX.Y.Z/
├── files/…                 # the deployable files
├── scripts/install.sh      # SCRIPT_DIR=<pkg>/scripts
├── scripts/uninstall.sh
├── manifest.json           # PROJECT_ROOT=<pkg>
├── checksums.sha256        # verified against files/ before packing
├── OFFLINE_PACKAGE         # marker: makes install.sh skip ALL networking
├── INSTALL.md
└── AdGuardHome_linux_<arch>.tar.gz   # OPTIONAL, user-supplied (never shipped)
```

Because `SCRIPT_DIR` resolves to `<pkg>/scripts`, `PROJECT_ROOT` becomes `<pkg>` and `LOCAL_FILES` becomes `<pkg>/files` — exactly what the existing local-files branch expects.

Key behaviours when `OFFLINE_PACKAGE` is present (or `-l` is passed):

- No egress-IP probe, no connection test, no online version lookup, and no re-download when verification fails — a mismatch against the bundled `checksums.sha256` aborts instead.
- The AdGuard Home **core** is neither shipped nor downloaded. `install.sh` scans the package folder and its parent for `AdGuardHome_linux_<arch>.tar.gz`; when one matches the machine's architecture it is unpacked into `/opt/AdGuardHome` and registered via `./AdGuardHome -s install` — still fully offline. A missing or mismatched tarball degrades to panel-only and prints exactly which architecture to fetch. Skipping the online path explicitly matters: `curl … | sh` would otherwise "succeed" on an empty input, since the pipeline exit status comes from `sh`.
- The architecture map mirrors AdGuardHome's official `install.sh` (`uname -m` → `amd64` / `arm64` / `armv7` / `armv5` / `mipsle_softfloat` …). The MIPS byte-order test uses `hexdump`, which OpenWrt ships (`od` does not exist there).
- After unpacking, the installer runs `<bin> --version` and rolls back on failure, so a "right file name, wrong contents" tarball can never register a broken service. Overwrites are keyed on the **directory** (`/opt/AdGuardHome`), not the binary, so a leftover stale directory is cleared too.
- Existing installs are detected before anything is touched — for both the AGH core and this panel, in online and offline runs alike. Declining the panel prompt exits cleanly without changes.
- If `files/` is missing, the installer aborts with a clear message instead of falling back to a download.
