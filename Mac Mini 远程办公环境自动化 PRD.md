# **产品需求文档 (PRD): Mac Mini 高性能远程工作站自动化方案**

**版本:** v1.0

**状态:** Draft / Ready for Claude Code

**负责人:** AI Product Manager

## **1\. 产品愿景 (Vision)**

通过一套自动化的状态切换机制，将 Mac Mini (M4 Pro) 转换为一个随时待命、高性能、且针对 Chromebook 屏幕比例优化过的虚拟工作站，消除 8:9 物理屏幕导致的远程体验畸形，确保隐私与性能的完美平衡。

## **2\. 核心痛点 (Pain Points)**

1. **比例不匹配:** LG DualUp (8:9) 物理屏幕在 16:10 的 Chromebook 上显示会有巨大的黑边。  
2. **配置繁琐:** 每次手动开关 BetterDisplay、查找 Sunshine 索引、修改配置文件并重启服务极其低效。  
3. **隐私风险:** 远程办公时，家里的物理屏幕依然亮着并显示操作内容。  
4. **环境不确定性:** 偶尔出现的显示器索引跳变会导致远程连接失败。

## **3\. 目标用户与场景 (User Persona & Scenarios)**

* **用户:** 拥有 Chromebook 的开发者/高级用户，通过 Tailscale 在外网访问 Mac Mini。  
* **场景:** \* **远程启动:** 在咖啡馆打开 Chromebook，通过一条命令让 Mac 进入“就绪态”。  
  * **本地回归:** 回到家坐到 Mac 前，一键恢复 8:9 双屏工作流。

## **4\. 功能需求 (Functional Requirements)**

### **4.1 状态机管理 (Core Logic)**

方案需支持两种核心状态：REMOTE\_MODE 和 LOCAL\_MODE。

#### **4.1.1 REMOTE\_MODE (远程模式)**

* **显示管理:** 激活 BetterDisplay 虚拟显示器 (16:10)，并设为主屏幕。  
* **隐私保护:** 尝试将物理显示器亮度降至 0 或通过虚拟断开 (Soft Disconnect) 隐藏内容。  
* **流媒体锁定:** 自动扫描 Sunshine 显示器列表，提取包含 "BetterDisplay" 关键字的索引号。  
* **配置注入:** 动态修改 sunshine.conf 中的 output\_name。  
* **服务生命周期:** 强制重启 Sunshine 以确保配置生效。

#### **4.1.2 LOCAL\_MODE (本地模式)**

* **显示管理:** 关闭虚拟显示器。  
* **环境恢复:** 恢复物理显示器为主屏幕，并恢复亮度。  
* **服务复位:** 清除 Sunshine 的 output\_name 锁定（可选，建议恢复到 0）。

### **4.2 错误处理与鲁棒性**

* **超时机制:** 屏幕切换需预留系统响应时间（3-5s）。  
* **自愈能力:** 如果脚本在切换中途失败，应具备 Rollback (回滚) 到 LOCAL\_MODE 的能力。  
* **依赖检查:** 启动前检查 betterdisplaycli、sunshine、tailscaled 是否在线。

## **5\. 技术架构方案 (Technical Architecture)**

| 组件 | 技术选型 | 职责 |
| :---- | :---- | :---- |
| **网络层** | Tailscale | 提供稳定、加密的点对点内网连接 |
| **显示层** | BetterDisplay | 创建 16:10 虚拟屏幕，处理主屏幕权重 |
| **流媒体层** | Sunshine (Server) | H.264/HEVC 硬件加速编码 (VideoToolbox) |
| **控制层** | Shell Script / Claude Code | 封装核心逻辑，提供 CLI 指令 |
| **客户端** | Moonlight-QT | 接收流媒体，处理低延迟输入与按键映射 |

## **6\. 用户交互设计 (User Interaction)**

通过终端定义简单的 Alias 或命令：

* remote-up: 执行切换至远程模式。  
* remote-down: 恢复本地模式。  
* remote-status: 检查当前屏幕索引及 Sunshine 运行状态。

## **7\. 非功能需求 (Non-functional Requirements)**

* **延迟:** 局域网/Tailscale 下端到端延迟控制在 30ms 以内。  
* **安全性:** 仅监听 Tailscale 网卡。  
* **隐私:** 物理屏幕在 REMOTE\_MODE 下必须处于不可视或极低亮度状态。

## **8\. 验收标准 (Acceptance Criteria)**

1. **成功率:** 连续 10 次执行 remote-up，Moonlight 均能准确连接到 16:10 画面且无物理屏黑边。  
2. **响应耗时:** 整个脚本从执行到 Sunshine 就绪应小于 10 秒。  
3. **资源占用:** 闲置时 Sunshine 对 M4 Pro 的 CPU 占用应低于 1%。