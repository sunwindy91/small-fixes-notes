# 001 · 桌面快捷方式图标变成"白纸 + 蓝色箭头"

- 平台：Windows 11（22H2+ 均可复现同类现象）
- 关键词：图标空白、图标缓存、完整性级别、Low Mandatory Level、icacls
- 状态：已解决，附体检 / 修复脚本

## 现象

桌面上**一部分**应用快捷方式显示为"白纸 + 蓝色箭头"（通用未知图标），同一批里另一些应用显示正常。

- 双击快捷方式，程序**能正常启动**
- 清图标缓存、重建 `iconcache_*.db`、重启资源管理器，**全部无效**
- 受影响的 exe 本身图标资源完好

## 容易误判的方向

按"最常见→最不常见"排，前三个我都试过：

| 假设 | 验证方式 | 本案结果 |
| --- | --- | --- |
| 图标缓存损坏 | 删 `%LOCALAPPDATA%\Microsoft\Windows\Explorer\iconcache*` 后重启 explorer | 无效（缓存确实是脏的，但不是原因） |
| 快捷方式文件损坏 | `WScript.Shell` 重写 `.lnk` | 无效（重写后字节数不变，说明内容本身没问题） |
| exe 缺图标资源 | `[System.Drawing.Icon]::ExtractAssociatedIcon(exe)` | 图标正常，排除 |
| 自定义 `.ico` 损坏 | 解析 ICO 头部与各条目偏移 | 本案**另有两个**快捷方式属于这一类，但不是主流症状 |

## 关键实验（10 分钟定位）

这是整件事的转折点：**不要在原位置继续猜，换一个位置对照。**

1. 把同一个"显示空白"的 `.lnk` 复制到另一个普通目录（例如 `D:\Temp`）
   - 复制后图标**正常** → 问题与**位置/上下文**相关，与 `.lnk` 内容无关
2. 把同一个快捷方式的完整性级别单独改成 Medium

   ```powershell
   icacls "<某个.lnk 的完整路径>" /setintegritylevel Medium
   ```

   - 图标**立刻恢复** → 根因锁定
3. 回头看目录本身：

   ```powershell
   icacls "$env:USERPROFILE\Desktop"
   ```

   - 输出里出现 `Mandatory Label\Low Mandatory Level` → 命中

## 根因

Windows 的强制完整性控制（MIC）给文件打上 **Low Mandatory Level** 标签后，资源管理器在解析快捷方式图标时会失败，回落到通用图标。

触发源：某些**沙箱化的 AI 编码代理 / 容器类工具**在隔离工作目录时，把 ACL 与完整性级别打到了**父目录**上。如果工作目录放在桌面下面，桌面本身就会被标成 Low，之后桌面上的文件全部继承该标签 —— 于是"看起来只是个图标问题"，实际是一次权限标记的副作用。

## 修复

```powershell
# 把目录及其子项恢复为默认的 Medium 完整性级别（子项会自动继承）
icacls "$env:USERPROFILE\Desktop" /setintegritylevel "(OI)(CI)Medium"

# 重启资源管理器，让图标重新提取
Stop-Process -Name explorer -Force
Start-Process explorer.exe
```

- 不需要管理员权限
- 只改文件元数据，不动文件内容
- 仓库内脚本：`scripts/Fix-DesktopIconIntegrity.ps1`

## 验证

1. `icacls "$env:USERPROFILE\Desktop"` 显示 `Mandatory Label\Medium Mandatory Level`
2. 桌面图标逐个项目确认恢复正常
3. **新建**一个快捷方式放到桌面，图标应立即正常 —— 这一条验证的是"新的继承关系已生效"，比看现有图标更可靠

## 边界（什么情况下这套不适用）

- 目标 exe 已被卸载 / 移动 → 图标本来就该是通用图标
- **只有一个**快捷方式空白，其余正常 → 优先怀疑该 `.lnk` 或其指定的 `.ico`
- 自制 `.ico` 结构损坏：ICO 头部声明的图像字节数大于文件实际长度（`scripts/ico_tool.py check` 可校验）
- 全系统图标都异常 → 仍应先按常规重建图标缓存

## 附带修掉的第二个坑

另有两个快捷方式指向同一个自制 `.ico`，该文件头部声明单张图像约 1 MB，而文件实际只有 20 KB —— Shell 直接取不到图标。

用 Pillow 重新生成多尺寸 ICO（16 / 24 / 32 / 48 / 64 / 128 / 256）后恢复正常：

```powershell
python .\scripts\ico_tool.py rebuild .\source.png -o .\app.ico
```

## 复发预防

- **沙箱 / 容器类工具的工作目录不要放在桌面（或其子目录）**，否则隔离标记会反复打到父目录
- 出问题时先跑 `Check-IconHealth.ps1`，确认是 Low 再动手，避免又去清缓存
- 系统里留一个修复脚本，一键执行

## 排查顺序（速查）

```text
桌面图标空白
├─ 只有一个应用空白 ─────────────→ 查该 .lnk 的 TargetPath / IconLocation
├─ 大面积空白
│  ├─ 清图标缓存后恢复 ──────────→ 图标缓存损坏（结束）
│  └─ 清缓存无效
│     ├─ 同 .lnk 换目录后正常 ───→ 位置相关：查目录完整性级别 ← 本案
│     └─ 换目录后仍空白 ─────────→ 查图标源（exe 资源 / .ico 结构）
```
