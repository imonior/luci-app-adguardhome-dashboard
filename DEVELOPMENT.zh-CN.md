[🇺🇸 English Development](DEVELOPMENT.md) · [🇺🇸 英文 README](README.md) · [🇨🇳 中文 README](README.zh-CN.md)

# 开发说明

> 本文档面向开发者，包含本地测试包说明、翻译编译与发版流程。普通用户请阅读 [README.md](README.md)（英文）或 [README.zh-CN.md](README.zh-CN.md)（中文）。

---

## 1. `changes_package/` 本地测试包

`changes_package/` 是开发机上用于**手动上传到路由器做本地测试**的部署包，**不会推送到 GitHub 仓库**（已在 `.gitignore` 屏蔽）。它必须保持与 `files/` 下文件**逐字节一致**——正式发布走面板内「检查面板更新 → 升级面板」在线完成，`changes_package/` 仅用于不方便联网时的本地验证。

任何修改 `files/` 之后，必须同步 `cp` 到 `changes_package/` 对应文件，再用 `diff -q` 确认一致，然后配合 `changes_package/deploy_atomic.sh` 上传路由器部署。否则路由器拿到的是旧版本，测非所改。

`changes_package/` 内包含：`adguardhome.lua`、`dashboard.js`、`*.lmo`、`*.po`、`deploy_atomic.sh`，与 `files/` 主文件一一对应。

---

## 2. 修改翻译

翻译源文件为 `files/luci/i18n/adguardhome.po`（英文）与 `files/luci/i18n/adguardhome.zh-cn.po`（中文）。修改 `.po` 后必须重新编译为 LuCI 二进制格式 `.lmo`：

```sh
python3 tools/po2lmo.py files/luci/i18n/adguardhome.po files/luci/i18n/adguardhome.lmo
python3 tools/po2lmo.py files/luci/i18n/adguardhome.zh-cn.po files/luci/i18n/adguardhome.zh-cn.lmo
```

> `po2lmo.py` 仅用于开发，不部署到路由器。

---

## 3. 发布新版本

1. 修改 `files/` 下的源文件。
2. 重新编译 `.po` → `.lmo`（见上）。
3. **四处同步 bump 版本号**。推送前检查会强制校验，漏掉任何一处都会导致发版失败：
   - `manifest.json` → `"version"`（运行时单一数据源：`adguardhome.lua` 读取已部署的 `/usr/share/adguardhome-dashboard/manifest.json` 获知已安装版本）
   - `files/view/dashboard.js` → `DASHBOARD_VIEW_VERSION`（「防旧视图」自修复的比对基准）
   - `README.md` / `README.zh-CN.md` → 各自顶部 `**vX.Y.Z**` 标记
   - `README.md` / `README.zh-CN.md` → `- **vX.Y.Z**` 变更记录条目（英文在前、中文对照）

4. **重新生成内容指纹清单**（任何对 `files/` 下文件的改动都必须执行，否则 install/面板升级会判定 sha256 不匹配而中止）：
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
   sha256sum -c checksums.sha256      # 必须 9/9 OK 才能继续
   ```

5. 同步本地测试包：把每个改动过的文件 `cp` 进 `changes_package/`，并用 `diff -q` 确认（见第 1 节）。
6. **跑推送前检查** —— 必须全绿才能推送：

   ```sh
   sh scripts/release.sh --check
   ```

   它会强制校验版本一致性（上述四处）、双语变更记录条目、代码语法（`sh -n` / `node --check` / `luac -p`）、`checksums.sha256` 指纹与 `changes_package/` 同步。CI 以 `--check --strict` 跑同一脚本，因此本地能拦下的问题在 CI 同样会中止发版。

7. `git add files/ checksums.sha256 manifest.json README.md README.zh-CN.md && git commit -m "release: vX.Y.Z — …" && git push origin main`

   推到 main 后，所有路由器上点「检查面板更新」即可看到新版本并在线升级。

8. 打 tag 并推送，同时发布离线安装包资产：

   ```sh
   git tag vX.Y.Z && git push origin main --tags
   ```

   `.github/workflows/release.yml` 会检出该 tag、先跑 `sh scripts/release.sh --check --strict`、再用 `scripts/make_package.sh` 生成压缩包，并作为资产附到 GitHub Release。

   > 该压缩包是**精简的离线安装包**——只含可部署文件、安装脚本、`manifest.json`、`checksums.sha256`、`OFFLINE_PACKAGE` 与 `INSTALL.md`。文档（README / LICENSE / DEVELOPMENT）**刻意不随包**：完整项目源码就是每个 Release 自动附带的 *Source code* 归档。

   > **tag 版本号必须与 `manifest.json` 一致。** 面板读取已部署的 `manifest.json` 来获知「已安装版本」，两者不一致会导致「检查面板更新」拿错数字比对。

---

## 4. 离线安装包

`scripts/make_package.sh` 生成**完全不需联网**即可安装的自包含压缩包：

```sh
sh scripts/make_package.sh      # -> dist/luci-app-adguardhome-dashboard-vX.Y.Z.tar.gz
```

包结构——只包含仓库里与安装相关的子集（**刻意不随带任何文档**），从而直接复用 `install.sh` 已有的「使用本地文件安装」分支，不需要另外维护一套离线安装器：

```
luci-app-adguardhome-dashboard-vX.Y.Z/
├── files/…                 # 可部署文件
├── scripts/install.sh      # SCRIPT_DIR=<pkg>/scripts
├── scripts/uninstall.sh
├── manifest.json           # PROJECT_ROOT=<pkg>
├── checksums.sha256        # 打包前会先与 files/ 校验一遍
├── OFFLINE_PACKAGE         # 标记：让 install.sh 跳过所有联网动作
├── INSTALL.md
└── AdGuardHome_linux_<arch>.tar.gz   # 可选，由用户自行放入（本包从不携带）
```

因为 `SCRIPT_DIR` 解析为 `<pkg>/scripts`，于是 `PROJECT_ROOT=<pkg>`、`LOCAL_FILES=<pkg>/files` —— 正好命中已有的本地文件分支。

存在 `OFFLINE_PACKAGE`（或传入 `-l`）时的关键行为：

- 不做出口 IP 探测、不做连接测试、不查在线版本；校验失败时也不重新联网下载，而是与包内 `checksums.sha256` 比对不一致即中止。
- **既不随包携带、也不联网下载** AdGuard Home 核心。`install.sh` 会扫描发布包目录及其上一级，查找 `AdGuardHome_linux_<arch>.tar.gz`；命中本机架构时解压到 `/opt/AdGuardHome` 并通过 `./AdGuardHome -s install` 注册服务 —— 全程仍然离线。没有匹配的包（或架构不符）时降级为只装面板，并明确提示需要获取哪个架构。这里必须显式跳过在线路径：`curl … | sh` 的退出码取自 `sh`，curl 失败喂进去的是空输入，会被误判成「安装成功」。
- 架构映射与 AdGuard Home 官方 `install.sh` 一致（`uname -m` → `amd64` / `arm64` / `armv7` / `armv5` / `mipsle_softfloat` 等）。MIPS 的端序判定用 `hexdump` —— OpenWrt 自带 `hexdump`，而没有 `od`。
- 解压后会执行 `<bin> --version` 自检，失败即回滚，因此「文件名对、内容错」的包不可能注册出一个坏服务。覆盖安装的判据是**目录**（`/opt/AdGuardHome`）而非二进制，残留目录同样会被清理。
- 动手写任何东西之前先检测已有安装 —— 核心与面板都是如此，在线与离线一致。面板选择「跳过」时干净退出，不做任何改动。
- 若 `files/` 缺失，直接报错退出，不会退化为联网下载。
