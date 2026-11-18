# 小问题笔记 · Small Fixes Notes

> 个人解决小问题的经验仓库。  
> 记录自己机器上遇到的怪问题，每条都要求：**能复现、能验证、能一键复用**。内容会持续增加。

## 这是什么

- 不是教程合集，而是**排障记录 + 可执行脚本**
- 每条案例固定结构：现象 → 容易误判的方向 → 关键实验 → 根因 → 修复 → 验证 → 边界
- 脚本都做了去个人化处理（路径走 `$env:USERPROFILE`），可直接改参数运行

## 案例索引

| # | 问题 | 平台 | 关键词 | 状态 |
| --- | --- | --- | --- | --- |
| 001 | 桌面快捷方式图标变成"白纸 + 蓝色箭头" | Windows 11 | 图标空白 / 图标缓存 / 完整性级别 / Low Mandatory Level | 已解决 |

## 脚本

| 脚本 | 用途 | 是否修改系统 |
| --- | --- | --- |
| `scripts/Check-IconHealth.ps1` | 体检：扫描桌面快捷方式，报告目标是否存在、完整性级别、自定义图标是否可用 | 只读 |
| `scripts/Fix-DesktopIconIntegrity.ps1` | 修复：把桌面目录完整性级别恢复为 Medium，并重启资源管理器 | 改文件元数据 |
| `scripts/ico_tool.py` | 校验 / 重建 `.ico`（需要 Pillow） | 只处理你指定的文件 |

## 用法

```powershell
# 1) 先体检，不改任何东西
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Check-IconHealth.ps1

# 2) 确认是 Low 完整性标签后再修复
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Fix-DesktopIconIntegrity.ps1

# 3) 校验一个自制 ico 是否损坏
python .\scripts\ico_tool.py check .\my-icon.ico
```

## 安全与免责

- 修复脚本只改**文件元数据**（完整性级别），不移动、不删除、不修改你的文件内容
- 修复脚本会重启 `explorer.exe`，已打开的资源管理器窗口会关闭；不想重启就加 `-NoRestart`
- 脚本按"现状"提供，仅在本机（Windows 11）验证过，不同版本行为可能不同
- 动手前请自行备份；涉及系统级改动时，建议先建还原点

## 记录模板

新增案例时复制 [`docs/_template.md`](docs/_template.md)，保持结构一致。

## License

MIT
