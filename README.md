# OpenList Synology SPK
OpenList 群晖DSM7套件
将 [OpenList](https://github.com/openlistteam/openlist) 打包为 Synology DSM 7 套件（SPK）。

## ✨ 功能特性

- **自动检测**：定时检查 OpenList 上游是否有新版本发布
- **自动下载**：新版本出现时自动下载该版本**所有**二进制文件
- **自动打包**：同时构建 x64 和 arm64 两种架构的 SPK 安装包
- **自动发布**：上游二进制文件 + SPK 包全部发布到本仓库 GitHub Releases
- **仓库轻量**：二进制不进 Git 仓库，只存 MD5 校验文件（几百字节）

## 🔄 自动同步流程

```
每 6 小时定时检查 (cron)
        ↓
查询 openlistteam/openlist 最新 release → v4.2.10
        ↓
检查本仓库是否已有 v4.2.10 (git tag)
        ↓ 已有 → 跳过
        ↓ 没有 → 继续
        ↓
下载该版本所有文件到临时目录 (~90 个文件，全平台)
        ↓
用 linux-amd64 / linux-arm64 打包 SPK
        ↓
MD5 校验文件提交到仓库 checksums/ 目录
        ↓
打 git tag v4.2.10
        ↓
创建 GitHub Release，上传：
  - 所有上游二进制文件 (tar.gz / zip 等)
  - SPK 安装包 (x64 + arm64)
```

### 手动触发

GitHub 仓库 → Actions → **自动检测并同步 OpenList 新版本** → Run workflow

- **version**：指定版本号（留空则自动检测最新）

## 📦 安装

1. 从 [Releases](../../releases) 页面下载对应架构的 SPK 文件
2. DSM 套件中心 → 手动安装 → 上传 SPK
3. 安装后通过 `http://<NAS-IP>:5244` 访问

## 支持的架构

| SPK 文件 | 适用型号 | CPU |
|----------|---------|-----|
| `openlist_x64_*.spk` | DS224+, DS920+, DS1522+ 等 | Intel/AMD x86_64 |
| `openlist_arm64_*.spk` | DS423+, DS623slim 等 | ARM64 |

## 目录结构

```
├── .github/workflows/
│   ├── auto-sync.yml               # 自动检测+下载+打包+发布工作流
│   └── build-spk.yml               # 手动构建工作流（旧）
├── checksums/                      # MD5 校验文件（入库，很小）
│   └── v4.2.9/
│       ├── md5.txt
│       └── md5-lite.txt
├── scripts/
│   ├── sync-binaries.sh            # 核心同步脚本
│   ├── installer                   # DSM 安装器
│   ├── functions                   # 辅助函数
│   ├── service-setup               # OpenList 服务配置
│   ├── start-stop-status           # 启停状态管理
│   └── preinst/postinst/...        # 生命周期钩子
├── build-spk.sh                    # SPK 构建脚本
├── conf/                           # DSM 权限配置
├── etc/                            # OpenList 默认配置
├── ui/                             # DSM 应用入口
├── icons/                          # SPK 级别图标
└── WIZARD_UIFILES/                 # 卸载向导
```

> **注意**：二进制文件和 SPK 包不在此仓库中，请在 [Releases](../../releases) 页面下载。

## 本地使用同步脚本

```bash
# 自动检测最新版本
./scripts/sync-binaries.sh

# 指定版本
./scripts/sync-binaries.sh 4.2.9

# 设置 GitHub Token 避免 API rate limit
export GITHUB_TOKEN=ghp_xxxxx
./scripts/sync-binaries.sh
```

脚本会将文件下载到临时目录、打包 SPK，结束后自动清理临时目录。
实际发布到 Releases 由 GitHub Actions 工作流完成。

## 登录账号

- **v4.2.7 及以上版本**：首次访问时通过初始化页面设置账号密码
- **v4.2.7 以下版本**：已预置管理员账号，用户名 `admin`，密码 `admin`
