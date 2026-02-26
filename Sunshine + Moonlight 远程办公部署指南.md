# **Sunshine \+ Moonlight \+ BetterDisplay 远程部署方案**

本方案旨在帮助你在 Chromebook 上通过高性能协议访问 Mac Mini，并自动锁定到 BetterDisplay 提供的 16:10 虚拟显示器，避开 8:9 物理屏幕的比例问题。

## **1\. 环境准备**

在 Mac Mini 终端中运行以下命令安装必要组件：

\# 安装 Sunshine 服务端  
brew install \--cask sunshine

\# 安装 BetterDisplay (如果尚未安装)  
brew install \--cask betterdisplay

\# 确保 BetterDisplay CLI 已安装  
\# 路径通常在: /Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay

## **2\. 自动化配置脚本 (prep-remote.sh)**

此脚本将自动激活虚拟显示器、将其设为主屏幕、查找 Sunshine 索引并重启服务。

\#\!/bin/bash

\# \--- 配置区 \---  
VIRTUAL\_NAME="Virtual"   
SUNSHINE\_CONF="$HOME/.config/sunshine/sunshine.conf"  
SUNSHINE\_BIN="/Applications/Sunshine.app/Contents/MacOS/sunshine"

echo "--- 正在初始化远程环境 \---"

\# 1\. 激活虚拟显示器  
echo "Step 1: 激活虚拟显示器 (16:10)..."  
\# 注意：如果命令找不到，请确保 BetterDisplay 设置里的 CLI 已启用  
betterdisplaycli set \-namelike="$VIRTUAL\_NAME" \-state=on \-main

\# 等待系统识别新布局  
sleep 3

\# 2\. 获取 Sunshine 识别到的显示器索引  
echo "Step 2: 获取显示器索引..."  
DISPLAY\_INFO=$($SUNSHINE\_BIN \--list-displays)

\# 提取虚拟显示器的索引号  
TARGET\_INDEX=$(echo "$DISPLAY\_INFO" | grep \-i "BetterDisplay" | head \-n 1 | awk \-F'|' '{print $1}' | tr \-d ' ')

if \[ \-z "$TARGET\_INDEX" \]; then  
    echo "错误: 未能找到虚拟显示器索引。请检查 \--list-displays 输出："  
    echo "$DISPLAY\_INFO"  
    exit 1  
fi

echo "确认虚拟显示器索引为: $TARGET\_INDEX"

\# 3\. 更新 Sunshine 配置  
echo "Step 3: 更新 Sunshine 配置文件..."  
mkdir \-p "$(dirname "$SUNSHINE\_CONF")"  
touch "$SUNSHINE\_CONF"

\# 移除旧的 output\_name 并添加新的  
sed \-i '' '/output\_name \=/d' "$SUNSHINE\_CONF"  
echo "output\_name \= $TARGET\_INDEX" \>\> "$SUNSHINE\_CONF"

\# 4\. 重启服务  
echo "Step 4: 重启 Sunshine 以应用新屏幕锁定..."  
brew services restart sunshine

echo "--- 部署成功！您可以连接了 \---"

## **3\. 常见问题 (FAQ)**

### **Q1: 远程连接时，Mac Mini 的物理屏幕会亮吗？**

**会。** Sunshine 只是在后台抓取屏幕并串流，它不会自动关闭物理显示器的输出。

* **最佳实践：** 既然是 Mac Mini，出门前请直接**物理关闭** LG 显示器的电源。BetterDisplay 的虚拟屏幕在系统层依然活跃。  
* **软件方案：** 在脚本中加入 betterdisplaycli set \-namelike="LG" \-brightness=0 将物理屏幕亮度降至最低。

### **Q2: 如何在 Chromebook 上获得最佳体验？**

1. **安装客户端：** 在 Chromebook 的 Linux 容器中安装 moonlight-qt：  
   sudo apt update && sudo apt install moonlight-qt

2. **网络：** 确保两端均运行 Tailscale。连接时，在 Moonlight 中输入 Mac Mini 的 **Tailscale IP**。  
3. **编码器：** 进入 Sunshine Web UI (https://localhost:47990) \-\> Audio/Video \-\> 确保 Encoder 选为 Apple VideoToolbox。  
4. **按键映射：** 在 Moonlight 设置中开启 Capture system keys，这样 Command 键等 Mac 快捷键才能正确传回。

### **Q3: 如何恢复本地使用模式？**

当你回到 Mac Mini 前，可以运行以下命令关闭虚拟屏并恢复物理屏为主屏：

betterdisplaycli set \-namelike="Virtual" \-state=off  
\# 如果需要，重新锁定 Sunshine 到物理屏（索引通常为 0）

## **4\. 远程启动流程建议**

1. 通过 SSH 远程登录 Mac Mini（使用 Tailscale IP）。  
2. 运行脚本：bash prep-remote.sh。  
3. 打开 Chromebook 上的 Moonlight，启动连接。