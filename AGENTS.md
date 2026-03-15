# AGENTS.md

本文件用于约束在本仓库中执行自动化修改的 Agent（含 AI 助手）行为。

## 目标

- 保持仓库可构建、可运行、可回滚。
- 优先保证跨平台一致性（Android/iOS/Web/Desktop）。
- 在不确定产品意图时，先提问再实现。

## 工作约定

- 默认语言：中文（简体）。
- 代码与注释：优先英文，必要时可中文补充。
- 小步提交：每次改动聚焦一个明确目标。
- 禁止无关重构：只改与当前任务直接相关的代码。

## 必须执行

- 修改代码后至少运行一次：
  - `flutter analyze`
- 涉及行为变化时尽量补测试：
  - `flutter test`

## 提交规范

- 每次完成代码或文档变更后，必须自动执行一次 `git commit`。
- 每次 `git commit` 后，必须自动执行一次 `git push`（默认推送到当前分支的上游）。
- 提交信息建议使用 Conventional Commits，例如：
  - `feat: add login screen skeleton`
  - `fix: handle empty file list state`
  - `chore: update dependencies`

## 目录建议

- `lib/`
  - `app/`：应用入口、路由、主题
  - `features/`：按业务模块组织
  - `shared/`：通用组件、工具、常量

## 风险操作

以下操作需要先明确说明并获得确认：

- 批量删除文件
- 大规模目录迁移
- 修改包名/签名/发布配置
- 升级 Flutter 主版本
