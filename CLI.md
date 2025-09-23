# Zigup 重构方案

## 问题分析

当前代码存在明显的过度设计问题：

### 1. 模块粒度过细

- **10 个源文件**处理仅 3 个核心功能（install/uninstall/list）
- 平均每个模块不到 100 行，造成不必要的认知负担
- 简单操作存在多层间接调用

### 2. 不必要的抽象层

- `App` 结构体仅是 HTTP client 和 paths 的薄包装器
- `Paths` 结构体使用复杂的 Cleanup 机制处理简单的路径拼接
- archive.zig（65 行）和 download.zig（48 行）作为独立模块过于琐碎

### 3. 过度复杂的错误处理

- 每个模块定义自己的错误类型，实际只是标准错误的组合
- 6 种不同的错误类型用于简单操作（InstallError、UninstallError 等）

### 4. 冗余的路径管理

- paths.zig 中复杂的 Cleanup 模式仅用于简单路径分配
- 多个辅助函数（distVersionDir、distPlatformDir 等）可以内联

## 重构方案

### 目标架构：单文件结构

将所有功能整合到 `src/zigup.zig`（约 400-500 行）：

```
src/
├── zigup.zig     # 所有核心功能
└── main.zig      # 仅包含 main 函数入口（可选）
```

### 具体重构步骤

#### 第一阶段：合并核心逻辑

1. **合并 core/ 目录下的所有模块**

   - 将 app.zig、install.zig、list.zig 合并
   - 移除 App 包装结构，直接传递 allocator 和 HTTP client
   - 消除中间错误类型

2. **简化路径管理**
   - 移除 Paths 结构体的 Cleanup 模式
   - 使用简单的路径拼接函数替代
   - 从 117 行减少到约 20 行

#### 第二阶段：内联辅助模块

1. **将 fs/archive.zig 和 net/download.zig 内联**

   - 这些只是标准库的薄包装
   - 将核心的 2-3 个函数直接移入主模块

2. **简化 remote.zig**
   - 移除复杂的平台检测逻辑
   - 使用简单结构体替代 Index/Release 层次结构
   - 从 340 行减少到约 50 行

#### 第三阶段：整合 CLI

1. **将 cli/runner.zig 合并到主模块**
   - 消除额外的间接层
   - 简化参数解析
   - 移除冗余错误处理

#### 第四阶段：最终整合

1. **创建单一 zigup.zig 文件**
   - 包含所有功能：install、uninstall、list
   - 清晰的函数组织
   - 直接使用标准库，无需包装器

### 重构后的代码结构

```zig
// zigup.zig - 完整实现
const std = @import("std");

// 常量定义
const INDEX_URL = "https://ziglang.org/download/index.json";
const PLATFORM = detectPlatform(); // 编译时检测

// 简单数据结构
const Release = struct {
    version: []const u8,
    url: []const u8,
    shasum: []const u8,
};

// 主函数入口
pub fn main() !void {
    // 命令行解析和分发
}

// 核心功能函数
fn installZig(allocator: Allocator, version: []const u8, set_default: bool) !void {
    // 1. 获取版本列表
    // 2. 下载压缩包
    // 3. 解压安装
    // 4. 设置默认版本（如需要）
}

fn uninstallZig(allocator: Allocator, version: []const u8) !void {
    // 删除版本目录
}

fn listVersions(allocator: Allocator, show_remote: bool) !void {
    // 显示已安装或远程版本
}

// 辅助函数
fn fetchReleases(allocator: Allocator) ![]Release { }
fn downloadFile(allocator: Allocator, url: []const u8, path: []const u8) !void { }
fn extractTarXz(allocator: Allocator, archive: []const u8, dest: []const u8) !void { }
fn getZigupPath() ![]const u8 { }
```

### 预期收益

#### 代码量减少

- **代码行数减少 50%**（1088 行 → 约 450 行）
- **文件数减少 90%**（10 个 → 1 个）
- **模块数减少 80%**（消除 8 个模块）

#### 可维护性提升

- 所有逻辑在一处，易于理解数据流
- 减少模块边界的认知负担
- 简化调试和测试
- 编译速度更快

#### 功能完全保留

- 所有 CLI 命令工作方式不变
- 相同的安装行为
- 相同的文件结构和路径
- 相同的用户错误消息

### 实施优先级

1. **高优先级**：合并核心模块（app、install、list）
2. **中优先级**：简化 paths 并内联小模块
3. **低优先级**：整合 CLI 并创建单文件结构

### 备选方案

如果希望保留一定的模块化，可采用两文件结构：

- `src/main.zig` - CLI 接口和参数处理（约 100 行）
- `src/zigup.zig` - 核心功能实现（约 350 行）

这样既保持了代码的简洁性，又维持了基本的关注点分离。

## 总结

当前的高度模块化结构适合大型应用，但对于 zigup 这样的简单 CLI 工具造成了不必要的复杂性。通过重构，我们可以在保持所有功能的同时，显著提高代码的可读性和可维护性。
