# ComfyUI Quick Reference Guide

## Key Files & Locations

### Entry Points
- **main.py** - Application initialization, custom node loading, server startup
- **server.py** - aiohttp web server, all API endpoints (1000+ lines)
- **execution.py** - Prompt execution pipeline, node execution, caching

### Configuration
- **comfy/cli_args.py** - Command-line arguments and startup configuration
- **folder_paths.py** - File system paths (models, custom_nodes, input, output, temp)

### API & Nodes
- **nodes.py** - Node definitions, loading, and NODE_CLASS_MAPPINGS (2400+ lines)
- **comfy_api/** - API framework (versioned: v0_0_1, v0_0_2, latest)
- **comfy_api_nodes/** - External API integrations (Stability, Topaz, Ideogram, etc.)

### Application Layer
- **app/user_manager.py** - User management, file operations, multi-user support
- **app/database/db.py** - Optional SQLite persistence
- **app/custom_node_manager.py** - Custom node translations and routing

### Execution & Validation
- **comfy_execution/graph.py** - Workflow graph management
- **comfy_execution/validation.py** - Input type validation

## Critical Security Findings

### CRITICAL Issues (Immediate Action Required)
1. **NO AUTHENTICATION** - All endpoints accessible without credentials
2. **Arbitrary Code Execution** - Custom nodes/prestartup scripts executed without approval
3. **No SSRF Protection** - URL downloads can access any URL
4. **Client ID Hijacking** - WebSocket sessions vulnerable to hijacking

### HIGH Issues
5. **No Rate Limiting** - DoS vulnerability
6. **Infinite HTTP Timeout** - Resource exhaustion risk
7. **Info Disclosure** - `/object_info`, `/system_stats`, `/internal/logs` exposed
8. **No HTTPS Enforcement** - Optional TLS, can run on HTTP

### MEDIUM Issues
9. **Symlink Traversal** - Path validation doesn't check symlinks
10. **No Input Size Limits** - Memory exhaustion possible
11. **Tokens in History** - API credentials might be stored
12. **CORS/CSRF** - Limited to loopback by default, but can be enabled

## Security Recommendations

### For Developers
- Use `--disable-all-custom-nodes` or strict whitelist in production
- Never expose on public internet without authentication wrapper
- Implement rate limiting at reverse proxy level
- Use reverse proxy (nginx/Apache) with auth in front of ComfyUI

### For Deployments
- Bind to 127.0.0.1 (default is good)
- Use firewall to restrict access
- Run as unprivileged user
- Use HTTPS/TLS with valid certificates
- Monitor resource usage (GPU/Memory/Disk)

### Defense in Depth
- Use containerization with resource limits
- Separate ComfyUI instances per user
- Air-gap critical systems
- Regular security audits
- Keep dependencies updated

## API Endpoints Overview

| Endpoint | Method | Purpose | Risk Level |
|----------|--------|---------|-----------|
| `/ws` | WS | WebSocket real-time updates | MEDIUM |
| `/prompt` | POST | Submit workflows | MEDIUM |
| `/queue` | GET/POST | Queue management | LOW |
| `/history` | GET/POST | Execution history | LOW |
| `/upload/image` | POST | Image upload | LOW |
| `/view` | GET | Image retrieval | LOW |
| `/object_info` | GET | Node definitions | MEDIUM |
| `/system_stats` | GET | System information | MEDIUM |
| `/userdata/*` | GET/POST/DELETE | File operations | LOW |
| `/extensions` | GET | Extension list | MEDIUM |
| `/internal/logs` | GET | Application logs | MEDIUM |

## File Organization

```
ComfyUI/
├── Main Scripts
│   ├── main.py                    # Entry point
│   ├── server.py                  # Web server
│   └── execution.py               # Execution engine
├── Core Logic
│   ├── nodes.py                   # Node system
│   ├── folder_paths.py            # Path management
│   └── comfy/                     # ML/generation
├── API Framework
│   ├── comfy_api/                 # API definitions
│   └── comfy_api_nodes/           # API node implementations
├── Application
│   ├── app/                       # User/model/node managers
│   └── middleware/                # HTTP middleware
└── Execution
    ├── comfy_execution/           # Graph execution
    └── Custom Node System         # Dynamic node loading
```

## Command-Line Security Flags

```bash
# Recommended for untrusted environments:
--listen 127.0.0.1                 # Bind to localhost only
--disable-all-custom-nodes         # Don't load custom nodes
--whitelist-custom-nodes trusted1 trusted2  # Only load specific nodes
--tls-keyfile key.pem              # Enable HTTPS
--tls-certfile cert.pem

# Optional but recommended:
--port 8188                        # Non-standard port (obscurity)
--max-upload-size 50               # Limit upload size to 50MB
```

## Custom Node Loading Risks

Custom nodes are loaded via:
1. `importlib.util.spec_from_file_location()` - Direct file loading
2. `module.exec_module()` - Arbitrary Python execution
3. Prestartup scripts executed before main loading
4. Web directories served via `/extensions/{name}/`

No sandboxing, verification, or user approval required.

## Network Communication

- **Internal HTTP Client**: aiohttp with no timeout (risk of hang attacks)
- **WebSocket**: Real-time updates, but no built-in authentication
- **External APIs**: Stability AI, Topaz, Ideogram, etc. (require API keys)
- **File Downloads**: From arbitrary URLs (SSRF risk)

## Database

- **Optional SQLite** (not required for basic operation)
- **ORM**: SQLAlchemy (protects against SQL injection)
- **Migrations**: Alembic
- **Location**: Configurable database URL

## Logging & Monitoring

- Accessible via `/internal/logs` without authentication
- Logs node loading times, execution progress, errors
- Terminal size information exposed
- Sensitive data might be logged

## Authentication/Authorization Status

| Component | Status | Risk |
|-----------|--------|------|
| API Endpoints | None | CRITICAL |
| Multi-User Mode | Header-based (spoofable) | HIGH |
| WebSocket | UUID-based | MEDIUM |
| CORS | Disabled by default, loopback CSRF protection | LOW |
| TLS | Optional | MEDIUM |

## Most Security-Sensitive Code Locations

1. **nodes.py:2111-2204** - Custom node loading (arbitrary code execution)
2. **main.py:60-101** - Prestartup script execution
3. **server.py:700-751** - Prompt submission endpoint
4. **server.py:341-392** - Image upload handler
5. **server.py:441-520** - Image view/retrieval handler
6. **app/user_manager.py:68-98** - File path validation
7. **comfy_api_nodes/util/download_helpers.py** - URL downloading
8. **server.py:825** - aiohttp client initialization (infinite timeout)

## Testing Security

```python
# Check if endpoints are accessible without auth:
curl http://localhost:8188/object_info       # Should fail in production
curl http://localhost:8188/system_stats      # Should fail in production

# Check for SSRF:
POST /prompt with URL to internal resource

# Check for path traversal:
GET /view?filename=../../../../etc/passwd

# Check for RCE:
Create custom node with malicious code
```

---

**Full Analysis**: See SECURITY_ANALYSIS.md for comprehensive details
**Last Updated**: 2025-11-20
**Status**: NEEDS SECURITY HARDENING
