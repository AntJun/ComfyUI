# ComfyUI 安全审计报告

**审计日期**: 2025-11-15
**审计范围**: ComfyUI 代码库
**严重程度等级**: 🔴 严重 | 🟠 高危 | 🟡 中危 | 🟢 低危

---

## 执行摘要

本次安全审计对 ComfyUI 代码库进行了全面的漏洞评估。共发现 **8 个安全问题**,包括 1 个严重漏洞、2 个高危漏洞、3 个中危漏洞和 2 个低危问题。

**关键发现**:
- 🔴 **严重**: 不安全的模型文件反序列化可导致任意代码执行
- 🟠 **高危**: 缺少身份验证和授权机制
- 🟠 **高危**: 自定义节点执行任意代码
- 🟡 **中危**: CORS 配置过于宽松
- 🟡 **中危**: 缺少 CSRF 保护
- 🟡 **中危**: 缺少请求速率限制
- 🟢 **低危**: 默认监听地址不安全
- 🟢 **低危**: 缺少安全响应头

---

## 详细漏洞分析

### 🔴 V-001: 不安全的Pickle反序列化 (严重)

**位置**: `comfy/checkpoint_pickle.py:1-13`, `comfy/utils.py:86-89`

**描述**:
ComfyUI 使用不安全的 `pickle.load()` 来加载模型文件。当 PyTorch 版本低于 2.4 或未设置 `safe_load` 参数时,系统会使用自定义的 `checkpoint_pickle.Unpickler`,但该实现仅过滤了 `pytorch_lightning` 模块,没有实现真正的安全反序列化。

**漏洞代码**:
```python
# comfy/checkpoint_pickle.py
class Unpickler(pickle.Unpickler):
    def find_class(self, module, name):
        #TODO: safe unpickle  # ⚠️ 未实现安全检查
        if module.startswith("pytorch_lightning"):
            return Empty
        return super().find_class(module, name)

# comfy/utils.py:88-89
logging.warning("WARNING: loading {} unsafely...")
pl_sd = torch.load(ckpt, map_location=device, pickle_module=comfy.checkpoint_pickle)
```

**影响**:
攻击者可以构造恶意的 pickle 文件(伪装成模型文件),上传后在服务器端执行任意 Python 代码,完全接管系统。

**攻击场景**:
1. 攻击者创建包含恶意 payload 的 .ckpt/.pt/.pth 文件
2. 将文件放置在 models 目录或通过工作流加载
3. ComfyUI 加载模型时触发反序列化
4. 执行 shell 命令、窃取数据、植入后门等

**CVSS评分**: 9.8 (严重)

**修复建议**:
```python
# 建议修复方案
class SafeUnpickler(pickle.Unpickler):
    ALLOWED_MODULES = {
        'torch', 'numpy', 'collections', 'typing',
        # 仅允许安全的模块
    }

    def find_class(self, module, name):
        # 白名单验证
        if not any(module.startswith(allowed) for allowed in self.ALLOWED_MODULES):
            raise pickle.UnpicklingError(f"Forbidden module: {module}")
        return super().find_class(module, name)

# 或强制使用 weights_only=True
pl_sd = torch.load(ckpt, map_location=device, weights_only=True)
```

**参考**:
- [CWE-502: Deserialization of Untrusted Data](https://cwe.mitre.org/data/definitions/502.html)
- [PyTorch Security Advisory](https://pytorch.org/docs/stable/torch.html#torch.load)

---

### 🟠 V-002: 缺少身份验证和授权机制 (高危)

**位置**: `server.py:213-820`, `app/user_manager.py:58-66`

**描述**:
大部分 API 端点缺少身份验证和授权检查。虽然实现了 `UserManager` 和多用户模式,但:
1. 默认情况下 `--multi-user` 未启用,所有用户共享 "default" 账户
2. 用户身份仅通过 HTTP 头 `comfy-user` 传递,无任何验证
3. 敏感操作(上传文件、执行任务、查看历史)无需认证

**漏洞代码**:
```python
# app/user_manager.py:58-66
def get_request_user_id(self, request):
    user = "default"
    if args.multi_user and "comfy-user" in request.headers:
        user = request.headers["comfy-user"]  # ⚠️ 直接信任客户端提供的值

    if user not in self.users:
        raise KeyError("Unknown user: " + user)
    return user
```

**影响**:
- 未授权访问: 任何人都可以访问所有 API 端点
- 用户冒充: 攻击者可以通过修改 HTTP 头伪装成其他用户
- 数据泄露: 可以查看其他用户的历史记录、工作流、输出文件

**攻击场景**:
```bash
# 无需认证即可执行任务
curl -X POST http://target:8188/api/prompt -d '{"prompt": {...}}'

# 伪装成其他用户
curl -H "comfy-user: admin" http://target:8188/api/history
```

**CVSS评分**: 8.6 (高危)

**修复建议**:
1. 实现基于 Token 的身份验证(JWT/API Key)
2. 添加会话管理机制
3. 对所有敏感操作添加权限检查
4. 默认启用身份验证

```python
# 建议添加认证装饰器
def require_auth(handler):
    async def wrapper(request):
        token = request.headers.get('Authorization')
        if not verify_token(token):
            return web.Response(status=401, text="Unauthorized")
        return await handler(request)
    return wrapper

@routes.post("/prompt")
@require_auth  # 添加认证
async def post_prompt(request):
    ...
```

---

### 🟠 V-003: 自定义节点任意代码执行 (高危)

**位置**: `nodes.py:2111-2189`

**描述**:
ComfyUI 允许从 `custom_nodes/` 目录加载任意 Python 代码。虽然这是设计功能,但存在严重安全风险:
1. 使用 `importlib` 动态执行自定义节点代码
2. 没有沙箱或权限限制
3. 支持 `prestartup_script.py` 在启动前执行

**漏洞代码**:
```python
# nodes.py:2123-2131
module_spec = importlib.util.spec_from_file_location(sys_module_name, module_path)
module = importlib.util.module_from_spec(module_spec)
sys.modules[sys_module_name] = module
module_spec.loader.exec_module(module)  # ⚠️ 执行任意代码
```

**影响**:
- 供应链攻击: 恶意的自定义节点可以窃取数据、植入后门
- 权限提升: 自定义节点以服务器权限运行
- 持久化: 可以修改系统文件、创建定时任务

**攻击场景**:
1. 诱导用户安装恶意自定义节点
2. 通过 Git 克隆、手动复制等方式安装
3. `__init__.py` 或 `prestartup_script.py` 执行恶意代码
4. 窃取模型文件、API 密钥、用户数据

**CVSS评分**: 8.1 (高危)

**修复建议**:
1. 实现自定义节点签名验证机制
2. 提供官方节点仓库和审核流程
3. 添加沙箱环境限制自定义节点权限
4. 在加载前警告用户潜在风险

```python
# 建议添加签名验证
def verify_node_signature(module_path):
    """验证自定义节点的数字签名"""
    sig_file = os.path.join(module_path, "node.sig")
    if not os.path.exists(sig_file):
        logging.warning(f"未签名的节点: {module_path}")
        return False
    # 验证签名逻辑
    return True
```

---

### 🟡 V-004: CORS配置过于宽松 (中危)

**位置**: `server.py:88-101`, `comfy/cli_args.py:42`

**描述**:
当使用 `--enable-cors-header` 参数时,默认允许所有来源 (`*`),这会导致跨域安全问题。

**漏洞代码**:
```python
# server.py:97
response.headers['Access-Control-Allow-Origin'] = allowed_origin  # 可能是 '*'
response.headers['Access-Control-Allow-Credentials'] = 'true'  # ⚠️ 危险组合
```

**影响**:
- CORS 混淆攻击
- 恶意网站可以读取用户的敏感数据
- 配合 XSS 攻击可以窃取 Cookie/Token

**修复建议**:
```python
# 使用白名单而非通配符
ALLOWED_ORIGINS = ['https://trusted-domain.com']

if origin in ALLOWED_ORIGINS:
    response.headers['Access-Control-Allow-Origin'] = origin
else:
    response.headers['Access-Control-Allow-Origin'] = 'null'
```

---

### 🟡 V-005: 缺少CSRF保护 (中危)

**位置**: `server.py` 所有 POST 端点

**描述**:
所有状态修改操作(POST/DELETE/PUT)都缺少 CSRF Token 验证,允许跨站请求伪造攻击。

**影响**:
- 攻击者可以诱导受害者执行非预期操作
- 上传恶意文件、修改配置、执行任务等

**攻击场景**:
```html
<!-- 恶意网页 -->
<form action="http://victim-comfyui:8188/api/prompt" method="POST">
  <input name="prompt" value='{"malicious": "payload"}'>
</form>
<script>document.forms[0].submit();</script>
```

**修复建议**:
实现 CSRF Token 机制,所有修改操作都需要验证 Token。

---

### 🟡 V-006: 缺少请求速率限制 (中危)

**位置**: 所有 API 端点

**描述**:
没有实现速率限制(Rate Limiting),攻击者可以发送大量请求导致拒绝服务。

**影响**:
- DoS/DDoS 攻击
- 资源耗尽(CPU/内存/磁盘)
- 暴力破解(如果未来添加密码认证)

**修复建议**:
```python
# 使用 aiohttp-ratelimiter 或自定义中间件
from aiohttp_ratelimiter import RateLimiter

rate_limiter = RateLimiter(max_rate=100, time_period=60)
app.middlewares.append(rate_limiter.middleware)
```

---

### 🟢 V-007: 默认监听地址不安全 (低危)

**位置**: `comfy/cli_args.py:38`

**描述**:
虽然默认监听 `127.0.0.1`,但文档鼓励用户使用 `--listen 0.0.0.0` 暴露到公网,缺少安全警告。

**修复建议**:
- 在文档中明确安全风险
- 建议使用反向代理(Nginx/Caddy)
- 强制使用 HTTPS 和身份验证

---

### 🟢 V-008: 缺少安全响应头 (低危)

**位置**: `server.py`

**描述**:
缺少以下安全响应头:
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `Content-Security-Policy`
- `Strict-Transport-Security` (使用 HTTPS 时)

**修复建议**:
```python
@web.middleware
async def security_headers_middleware(request, handler):
    response = await handler(request)
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-Frame-Options'] = 'DENY'
    response.headers['X-XSS-Protection'] = '1; mode=block'
    return response
```

---

## 正面发现 (安全最佳实践)

ComfyUI 在以下方面实现了良好的安全措施:

1. ✅ **路径遍历防护** (`server.py:407-420, 451-465`):
   ```python
   if filename[0] == '/' or '..' in filename:
       return web.Response(status=400)

   if os.path.commonpath((upload_dir, filepath)) != upload_dir:
       return web.Response(status=400)
   ```

2. ✅ **文件上传路径验证** (`server.py:355-359`):
   使用 `os.path.normpath` 和 `os.path.commonpath` 防止目录遍历

3. ✅ **命令注入防护**:
   未发现 `os.system()`、`eval()`、`exec()` 的危险使用

4. ✅ **HTTPS支持** (`comfy/cli_args.py:40-41`):
   支持 TLS/SSL 配置

---

## 漏洞统计

| 严重程度 | 数量 | 占比 |
|---------|------|------|
| 🔴 严重  | 1    | 12.5% |
| 🟠 高危  | 2    | 25.0% |
| 🟡 中危  | 3    | 37.5% |
| 🟢 低危  | 2    | 25.0% |
| **总计** | **8** | **100%** |

---

## 修复优先级

### 立即修复 (P0 - 1-7天)
1. **V-001**: 实现安全的模型文件加载机制
2. **V-002**: 添加身份验证和授权

### 短期修复 (P1 - 1-4周)
3. **V-003**: 实现自定义节点签名验证
4. **V-004**: 修复 CORS 配置
5. **V-005**: 添加 CSRF 保护

### 中期修复 (P2 - 1-3个月)
6. **V-006**: 实现速率限制
7. **V-007**: 改进默认配置文档
8. **V-008**: 添加安全响应头

---

## 合规性建议

### OWASP Top 10 映射
- **A03:2021 – Injection**: V-001 (反序列化注入)
- **A01:2021 – Broken Access Control**: V-002 (缺少认证)
- **A05:2021 – Security Misconfiguration**: V-004, V-007, V-008
- **A07:2021 – Identification and Authentication Failures**: V-002

### 推荐安全标准
- 遵循 OWASP ASVS (Application Security Verification Standard) Level 2
- 实施 NIST Cybersecurity Framework
- 考虑 SOC 2 Type II 合规性(如果提供商业服务)

---

## 总结

ComfyUI 是一个功能强大的工具,但在安全性方面还有提升空间。**最关键的问题是不安全的反序列化**,可能导致远程代码执行。建议开发团队:

1. **立即**修复 V-001 和 V-002
2. 建立安全开发生命周期(SDLC)
3. 进行定期的安全审计和渗透测试
4. 为用户提供安全配置指南
5. 建立漏洞披露计划(Responsible Disclosure)

---

**审计人员**: Claude (AI Security Auditor)
**报告版本**: 1.0
**下次审计建议**: 修复完成后 3 个月
