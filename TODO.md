# zigup MVP TODO

## 项目目标

用 Zig 编写 Zig 版本管理工具（类似 rustup），MVP 专注核心功能。

## ✅ 已完成功能 (MVP)

### 1. 项目结构初始化
- [x] 完善基础目录结构 (src/main.zig, build.zig)
- [x] 简化为单文件架构 (src/zigup.zig)

### 2. 版本索引与解析
- [x] 从 https://ziglang.org/download/index.json 获取版本信息
- [x] 实现版本解析：latest, master, stable, 具体版本号
- [x] 版本排序逻辑 (语义化版本，master 排最后)

### 3. 下载与校验
- [x] 使用 curl 下载 tar.xz 文件
- [x] SHA256 校验下载文件完整性
- [x] tar 解压到指定目录
- [x] 实现下载缓存避免重复下载
- [x] 跨平台支持（运行时检测 OS 和架构）

### 4. 版本管理核心
- [x] 创建 ~/.zigup/ 目录结构:
  - versions/<version>/zig (解压的二进制)
  - cache/ (下载缓存 + index.json)
  - current (当前版本文本文件)
- [x] 创建 symlink: ~/.local/bin/zig -> ~/.zigup/versions/<version>/zig
- [x] 记录默认版本配置

### 5. CLI 命令实现
- [x] `zigup install [version] [-d|--default]` - 安装 Zig 版本 (默认 latest)
- [x] `zigup uninstall <version>` - 卸载指定版本
- [x] `zigup list [-r|--remote]` - 显示已安装/可用版本
- [x] `zigup use <version>` - 切换默认版本
- [x] 命令别名: i, rm, ls
- [x] 完善 usage 帮助信息

### 6. 测试与文档
- [x] `findRelease()` 单元测试
- [x] Arena allocator 避免内存泄漏
- [x] README.md 完整文档
- [x] CLAUDE.md 架构说明

## 🚧 待实现功能

### ZLS 支持
- [ ] 通过 https://github.com/zigtools/release-worker API 获取对应的 ZLS 版本
- [ ] `zigup zls install` - 安装最新 ZLS (预构建包)
- [ ] `zigup zls uninstall` - 卸载 ZLS
- [ ] ZLS 二进制管理与 symlink

### 用户体验改进
- [ ] 下载进度条显示
- [ ] 友好的错误信息和建议
- [ ] 检查 ~/.local/bin 是否在 PATH 中

### 项目级版本管理
- [ ] `.zig-version` 文件支持
- [ ] `zigup which` - 显示当前使用的 zig 路径

## 💡 未来增强

- 镜像/代理配置支持
- 并行下载优化
- 自动更新机制
- Shell 补全脚本 (bash/zsh/fish)
- 交互式版本选择 (TUI)
- 验证已安装版本的完整性
