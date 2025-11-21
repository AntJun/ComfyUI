# ComfyUI 安全漏洞发现总结

## 🔍 概述

在 ComfyUI 项目中发现了 **6 个主要安全漏洞**，其中包括 **2 个严重级别**的任意代码执行漏洞。

---

## ⚠️ 严重漏洞（立即关注）

### 1. 任意代码执行 - 自定义节点加载
- **位置**: `nodes.py:2131`
- **描述**: 自动执行 `custom_nodes` 目录中的任意 Python 代码
- **影响**: 完全控制服务器
- **代码**: `module_spec.loader.exec_module(module)`

### 2. 任意代码执行 - Prestartup 脚本
- **位置**: `main.py:69`
- **描述**: 启动时自动执行 `prestartup_script.py`
- **影响**: 完全控制服务器
- **代码**: `spec.loader.exec_module(module)`

---

## 🔴 高危漏洞

### 3. 信息泄露 - /system_stats 端点
- **位置**: `server.py:593`
- **描述**: 暴露 `sys.argv`（可能包含 API 密钥、密码）
- **影响**: 敏感信息泄露
- **复现**: `curl http://localhost:8188/system_stats`

### 4. 无身份验证
- **位置**: 多个端点
- **描述**: 所有 API 端点默认无需认证
- **受影响端点**: `/system_stats`, `/object_info`, `/queue`, `/history`, `/prompt`, 等

---

## 🟡 中危漏洞

### 5. 符号链接路径遍历
- **位置**: `server.py:470`
- **描述**: `/view` 端点未检查符号链接
- **影响**: 可通过符号链接读取任意文件
- **前提**: 需要先在允许目录创建符号链接

### 6. 拒绝服务 - 无限超时
- **位置**: `server.py:824`
- **描述**: HTTP 客户端配置为无超时 (`total=None`)
- **影响**: 资源耗尽风险

---

## 📝 快速验证

### 方法 1: 使用自动化脚本
```bash
cd /home/user/ComfyUI
./verify_vulnerabilities.sh
```

### 方法 2: 手动验证

#### 验证信息泄露
```bash
# 启动 ComfyUI
python main.py

# 在另一个终端
curl http://localhost:8188/system_stats | jq '.system.argv'
```

#### 验证任意代码执行
```bash
# 创建测试节点
mkdir -p custom_nodes/test_vuln
cat > custom_nodes/test_vuln/__init__.py << 'EOF'
print("[!] 代码已执行!")
NODE_CLASS_MAPPINGS = {}
EOF

# 启动 ComfyUI（会看到 "[!] 代码已执行!" 消息）
python main.py
```

#### 验证符号链接漏洞
```bash
# 创建符号链接
ln -s /etc/passwd output/test_link

# 访问
curl "http://localhost:8188/view?filename=test_link&type=output"
```

---

## 🛡️ 缓解措施

### 立即采取的行动:

1. **隔离运行环境**
   - 仅在可信环境中运行
   - 使用 Docker 容器隔离

2. **禁用自定义节点**
   ```bash
   python main.py --disable-all-custom-nodes
   ```

3. **网络隔离**
   - 仅绑定到 localhost（默认）
   - 不要暴露到公网

4. **清理敏感信息**
   - 不要在命令行传递密钥、密码
   - 使用环境变量或配置文件

5. **添加认证层**
   - 使用反向代理（Nginx, Caddy）
   - 实现基本认证或 OAuth

6. **审查自定义节点**
   - 定期检查 `custom_nodes` 目录
   - 仅使用可信来源的节点

---

## 📊 漏洞统计

| 严重程度 | 数量 | 漏洞类型 |
|---------|------|---------|
| 严重 ⚠️ | 2 | 任意代码执行 |
| 高危 🔴 | 2 | 信息泄露、无认证 |
| 中危 🟡 | 2 | 路径遍历、DoS |
| **总计** | **6** | |

---

## 📄 相关文档

- **详细报告**: `VULNERABILITY_REPORT.md` - 完整的漏洞分析和复现步骤
- **验证脚本**: `verify_vulnerabilities.sh` - 自动化验证脚本
- **安全分析**: `SECURITY_ANALYSIS.md` - 全面的安全分析文档（如存在）

---

## 🔗 关键代码位置

| 漏洞 | 文件 | 行号 |
|------|------|------|
| 自定义节点代码执行 | nodes.py | 2131 |
| Prestartup 代码执行 | main.py | 69 |
| sys.argv 泄露 | server.py | 593 |
| 符号链接漏洞 | server.py | 470 |
| 无限超时 | server.py | 824 |
| URL 下载 (SSRF) | comfy_api_nodes/util/download_helpers.py | 97 |

---

## ⚙️ 测试环境

- **项目**: ComfyUI
- **Commit**: cb96d4d
- **Python**: 3.11.14
- **测试日期**: 2025-11-20

---

## ⚡ 使用示例

```bash
# 1. 查看详细报告
cat VULNERABILITY_REPORT.md

# 2. 运行验证脚本
./verify_vulnerabilities.sh

# 3. 安全启动 ComfyUI
python main.py --disable-all-custom-nodes --listen 127.0.0.1

# 4. 使用 Docker 隔离运行（推荐）
docker run --rm -p 127.0.0.1:8188:8188 -v $(pwd):/app comfyui \
  python main.py --disable-all-custom-nodes
```

---

## ⚠️ 免责声明

这些漏洞信息仅用于安全研究和修复目的。请负责任地使用这些信息，不要用于恶意目的。

**强烈建议**:
- 立即评估风险
- 实施缓解措施
- 不要在生产环境暴露未受保护的 ComfyUI 实例
- 关注官方安全更新

---

**如有疑问或需要进一步协助，请参考详细报告或联系安全团队。**
