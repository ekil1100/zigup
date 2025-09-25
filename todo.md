# zigup MVP TODO

## 项目目标

用 Zig 编写 Zig 版本管理工具（类似 rustup），MVP 专注 Linux x86_64 核心功能。

## MVP 任务清单

### 1. 项目结构初始化

- [ ] 完善基础目录结构 (src/main.zig, build.zig)
- [ ] 设计核心模块：cli/, core/, net/, fs/

### 2. 版本索引与解析

- [ ] 从 https://ziglang.org/download/index.json 获取版本信息
- [ ] 实现版本解析：支持 latest, stable, 具体版本号

### 3. 下载与校验

- [ ] HTTP 客户端下载 tar.xz 文件 (Linux x86_64)
- [ ] SHA256 校验下载文件完整性
- [ ] tar.xz 解压到指定目录
- [ ] 实现下载缓存避免重复下载

### 4. 版本管理核心

- [ ] 创建 ~/.zigup/ 目录结构:
  - dist/<version>/zig (解压的二进制)
  - bin/ (符号链接管理)
  - cache/ (下载缓存)
- [ ] 创建/管理 symlink 指向活跃版本
- [ ] 记录默认版本配置

### 5. CLI 命令实现

- [ ] `zigup install [version]` - 安装 Zig 版本 (默认 latest)
- [ ] `zigup uninstall <version>` - 卸载指定版本
- [ ] `zigup list` - 显示已安装和可用版本
- [ ] `zigup default <version>` - 设置默认版本
- [ ] `zigup which` - 显示当前使用的 zig 路径

### 6. 基础 ZLS 支持

- [ ] 通过 https://github.com/zigtools/release-worker API 获取对应的 ZLS 版本
- [ ] `zigup zls install` - 安装最新 ZLS (预构建包)
- [ ] `zigup zls uninstall` - 卸载 ZLS
- [ ] ZLS 二进制管理与 symlink

### 7. 错误处理与用户体验

- [ ] 友好的错误信息和建议
- [ ] 基础的进度显示
- [ ] 参数验证和帮助信息

## 暂缓功能 (后续版本)

- 跨平台支持 (macOS, Windows)
- 项目级版本管理 (.zig-version)
- 镜像/代理配置
- 高级 CLI 体验
- 自动更新机制
- vscode zig 插件适配
