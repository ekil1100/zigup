# zigup（工作名）开发 TODO

## 0. 项目目标

- 用 Zig 编写一个跨平台的 Zig 安装 CLI（类似 rustup），支持：
  - 安装/切换 Zig 多版本（官方发布渠道）
  - 管理默认版本、项目本地版本
  - 安装/更新/卸载 zls（Zig Language Server）
  - 安装源镜像/代理、离线包支持
  - 可嵌入到 CI，提供非交互模式
- 平台支持：Linux、macOS、Windows（x86_64、aarch64）

## 1. 项目初始化

- [ ] 选定项目名（占位：zigup）
- [ ] 初始化仓库结构
  - [ ] zigup/
    - [ ] build.zig
    - [ ] src/
      - [ ] main.zig
      - [ ] cli/
      - [ ] core/
      - [ ] net/
      - [ ] fs/
      - [ ] platform/
      - [ ] zls/
    - [ ] docs/
    - [ ] tests/
    - [ ] scripts/
- [ ] 选择 Zig 最低编译版本（建议与最新 stable 对齐）
- [ ] 代码风格、lint、格式化约定（zig fmt）
- [ ] 许可证与贡献指南（LICENSE、CONTRIBUTING.md）

## 2. 需求与规格定义

- [ ] 子命令设计
  - [ ] zigup init（首次初始化）
  - [ ] zigup install <version|latest> [--channel stable|dev] [--arch ...] [--dir ...]
  - [ ] zigup uninstall <version>
  - [ ] zigup list [--installed|--remote]
  - [ ] zigup default <version>
  - [ ] zigup which [zig|zls]
  - [ ] zigup use <version>（仅当前 shell/session 或项目目录）
  - [ ] zigup pin（在项目目录写入 .zig-version）
  - [ ] zigup self update
  - [ ] zigup zls install [--from <repo|url>] [--zig <version>]
  - [ ] zigup zls update
  - [ ] zigup zls uninstall
  - [ ] zigup env（输出 PATH/ENV 配置）
- [ ] 行为约定
  - [ ] 安装目录结构：~/.zigup/ or %USERPROFILE%\.zigup\
    - [ ] dist/<version>/<platform-arch>/
    - [ ] bin/（shims 或 symlink）
    - [ ] zls/<version>/
    - [ ] cache/（下载缓存、校验文件）
  - [ ] 版本解析：显式版本、latest、dev、别名（stable、nightly）
  - [ ] 优先级：项目 .zig-version > 环境变量 ZIGUP_DEFAULT > 全局默认
  - [ ] shim 机制：在 PATH 前置 zigup/bin，内部分发到目标版本二进制
  - [ ] 校验：SHA256 或签名校验
  - [ ] 代理/镜像：环境变量支持（HTTP(S)\_PROXY、自定义 mirror URL）
  - [ ] 非交互模式：--yes、--no-prompt、退出码规范
  - [ ] 日志与诊断：--verbose、--quiet、日志文件

## 3. 远端源与版本发现

- [ ] 官方 Zig 下载源研究与确定 API/索引方式
  - [ ] 解析 https://ziglang.org/download/ 或官方 JSON 索引（若有）
  - [ ] 支持渠道：stable、dev、nightly
- [ ] 远端版本列表缓存策略与过期时间
- [ ] 多平台资产映射（文件名、压缩格式、校验文件）
- [ ] 镜像/自定义源配置
  - [ ] zigup config set mirror <url>
  - [ ] zigup config unset mirror
  - [ ] 配置文件：~/.zigup/config.toml

## 4. 下载与校验

- [ ] HTTP 客户端实现（Zig 标准库）
- [ ] 断点续传/重试策略
- [ ] 下载进度条（TTY 友好）
- [ ] 校验和验证（SHA256、可选签名验证）
- [ ] 压缩包处理（tar.xz、zip 等）
- [ ] 下载缓存目录与命中策略

## 5. 安装与版本管理

- [ ] 将解压产物放入 dist/<version>/<plat-arch>/
- [ ] 生成 shim 或创建符号链接/硬链接
  - [ ] Linux/macOS：symlink
  - [ ] Windows：.cmd/.bat 启动器或 shim 可执行文件
- [ ] default 版本管理
  - [ ] 写入 ~/.zigup/current 指针或配置
  - [ ] 提供 zigup default <version>
- [ ] use 与 pin
  - [ ] 在当前 shell 输出 eval 脚本（POSIX shell、PowerShell）调整 PATH
  - [ ] 项目根创建 .zig-version，进入目录时自动生效的策略说明（shell 集成）
- [ ] 卸载时清理目录与索引，并保证不破坏当前默认版本

## 6. zls 支持

- [ ] 发现与选择 zls 安装方式
  - [ ] 优先：下载预构建二进制（若有官方发布）
  - [ ] 备选：用指定版本的 zig 从源码构建
- [ ] 从源码构建流程
  - [ ] 源码仓库：https://github.com/zigtools/zls
  - [ ] 选择 zig 版本（默认使用当前默认 zig）
  - [ ] 依赖获取、构建参数（release-fast/release-safe）
  - [ ] 可重用构建缓存，输出 zls/<version>/bin/zls
- [ ] zls 版本解析
  - [ ] 支持 tag、commit、latest release
- [ ] 命令实现
  - [ ] zigup zls install [--version <tag|commit|latest>] [--zig <version>]
  - [ ] zigup zls update
  - [ ] zigup zls uninstall
  - [ ] zigup which zls
- [ ] 与编辑器集成说明（VSCode、Neovim）：如何将 zls 路径指向 zigup 管理的 zls

## 7. CLI/交互与 UX

- [ ] 命令行解析库选择（原生 std.argv 解析或使用小型库）
- [ ] 友好的错误信息与建议
- [ ] 彩色输出、列对齐、表格/列表展示
- [ ] 国际化（至少中英文开关）
- [ ] TTY 检测与非 TTY 安静输出（适配 CI）

## 8. 平台细节与可移植性

- [ ] 路径与权限
  - [ ] Windows 路径与权限（需要管理员？尽量用户级别安装）
  - [ ] macOS Gatekeeper 与可执行位
  - [ ] Linux 不同发行版的依赖
- [ ] 代理与证书（公司环境）
- [ ] 文件锁与并发安装保护
- [ ] 时区与时间戳（缓存过期）
- [ ] 大文件与磁盘空间检测

## 9. 性能与健壮性

- [ ] 网络失败重试/退避
- [ ] 并行下载（多资产场景）
- [ ] 校验管线与 I/O 限制（流式处理、零拷贝尽量）
- [ ] 日志分级与诊断命令（zigup doctor）

## 10. 测试与 CI/CD

- [ ] 单元测试（版本解析、URL 生成、校验、解压）
- [ ] 端到端测试（安装、切换、卸载、zls 构建）
- [ ] 矩阵 CI（Linux/macOS/Windows；x86_64/aarch64 若可）
- [ ] 预编译发布 zigup 本体（多平台）
- [ ] 发布脚本与 Homebrew/Scoop 包配方
- [ ] 二进制可重定位性与签名

## 11. 文档与示例

- [ ] 快速开始
- [ ] 常见问题（代理、权限、证书）
- [ ] 镜像与离线安装说明
- [ ] 与现有 zig 安装并存策略
- [ ] 编辑器配置 zls 指南
- [ ] 贡献与开发指南（如何本地调试）

## 12. 安全与合规

- [ ] 下载源白名单；HTTPS 强制
- [ ] 校验和签名验证开关
- [ ] 权限最小化（不写系统目录）
- [ ] 遥测策略（默认关闭，若需要则透明说明）

## 13. 路线图（MVP -> v1.0）

- [ ] MVP
  - [ ] Linux x86_64 核心能力
    - [ ] 初始化仓库骨架（build.zig、src/main.zig、核心子目录）
    - [ ] CLI 支持 install/uninstall/list/default/which zig
      - [ ] `zigup install` 默认安装 latest 版本，如果要安装 stable 版本需要使用 `zigup install stable`
    - [ ] 解析官方下载索引并在本地缓存 Linux x86_64 版本
      - [ ] 版本可以从 https://ziglang.org/download/index.json 获取
    - [ ] 下载 + SHA256 校验 + tar.xz 解压 + 缓存命中
    - [ ] 管理 dist 结构与 symlink，支持默认版本切换与安全卸载
    - [ ] 提供 zls install/uninstall（预构建包，限制 latest）
  - [ ] 暂缓范围
    - [ ] 跨平台/架构、use/pin、自更新、镜像代理
    - [ ] CLI 进阶体验、CI/发布流程、文档与安全策略拓展
- [ ] Beta
  - [ ] 三大平台支持
  - [ ] 项目 pin、use、默认版本管理完善
  - [ ] 镜像与非交互模式
- [ ] v1.0
  - [ ] 完整 zls 管理
  - [ ] 端到端测试、打包与分发
  - [ ] 文档与示例完善

## 14. 技术实现要点备忘

- [ ] 版本解析器：支持 0.x.y、x.y.z、dev、latest、nightly、别名映射
- [ ] 平台三元组：os-arch-libc（glibc/musl 区分）
- [ ] 解压实现：tar.xz（考虑引入 xz 解压，或调用系统工具备选）
- [ ] 校验：内置 SHA256，签名如官方提供则接入
- [ ] symlink/shim 设计：Windows 使用小可执行或 .cmd 包装器
- [ ] Shell 集成脚本生成：bash/zsh/fish/pwsh

## 15. 可能的扩展

- [ ] 集成 zigup build 缓存共享
- [ ] 集成 zig 标准包管理（未来官方方案）
- [ ] 管理其他 zig 生态工具（e.g., gyro、bun-like 工具等）
