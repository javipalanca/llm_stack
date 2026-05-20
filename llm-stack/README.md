# LLM Stack: Multi-GPU vLLM Deployment with Docker Compose + LiteLLM Router

A production-ready setup for running multiple LLMs across two GPU servers (Blackwell + A30) using vLLM, Docker Compose, and LiteLLM as a unified routing layer.

## Overview

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│  LiteLLM Router (Port 4000)                            │
│  ├─ Single unified OpenAI-compatible API               │
│  └─ Routes requests to appropriate model endpoints     │
│                                                         │
├──────────────────────┬──────────────────────            │
│                      │                                  │
│  BLACKWELL           │  A30                             │
│  (2× RTX PRO 6000)   │  (3× A30)                        │
│  ├─ llama33          │  ├─ mimo (GPU 0+1)              │
│  │  (GPU 0)          │  ├─ llava (GPU 2)               │
│  │  Port 8001        │  └─ deepseek (GPU 0+1) [opt]    │
│  └─ qwen36           │     Port 8005                    │
│     (GPU 1)          │                                  │
│     Port 8002        │  Ports: 8003, 8004              │
│                      │                                  │
└──────────────────────┴──────────────────────            │
```

## Hardware Configuration

### Server: Blackwell
- **GPU 0**: NVIDIA RTX PRO 6000 Blackwell (96 GB VRAM) → `llama33` (port 8001)
- **GPU 1**: NVIDIA RTX PRO 6000 Blackwell (96 GB VRAM) → `qwen36` (port 8002)

### Server: A30
- **GPU 0+1**: 2× NVIDIA A30 (24 GB each) → `mimo` with tensor-parallel (port 8003)
- **GPU 2**: NVIDIA A30 (24 GB) → `llava` (port 8004)
- **GPU 0+1**: 2× NVIDIA A30 → `deepseek` alternative (port 8005) *not running by default*

## Models Deployed

| Model | Server | GPU | Port | Notes |
|-------|--------|-----|------|-------|
| `llama33` | Blackwell | 0 | 8001 | Llama 3.3 70B AWQ |
| `qwen36` | Blackwell | 1 | 8002 | Qwen 3.6 35B |
| `mimo` | A30 | 0,1 | 8003 | MIMO v2.5 Pro (tensor-parallel) |
| `llava` | A30 | 2 | 8004 | LLaVA multimodal |
| `deepseek` | A30 | 0,1 | 8005 | DeepSeek R1 (alternative to MIMO) |

**Note**: `deepseek` and `mimo` share the same GPUs (A30:0,1). Only one can run simultaneously.

## Directory Structure

```
llm-stack/
├── .env.example                          # Environment template
├── .env                                  # Local config (copy from .env.example)
├── README.md                             # This file
├── compose/
│   ├── docker-compose.blackwell.yml     # Blackwell server services
│   ├── docker-compose.a30.yml           # A30 server services
│   └── docker-compose.monitoring.yml    # Prometheus + Grafana (optional)
├── config/
│   └── litellm-config.yml               # LiteLLM routing configuration
├── monitoring/
│   └── prometheus.yml                   # Prometheus scrape config
├── scripts/
│   ├── model-lib.sh                     # Utility functions library
│   ├── download-model.sh                # Download models from HuggingFace
│   ├── start-model.sh                   # Start individual model
│   ├── stop-model.sh                    # Stop individual model
│   ├── restart-model.sh                 # Restart individual model
│   ├── status.sh                        # Show status of all services
│   ├── test-model.sh                    # Test model endpoint
│   └── swap-deepseek.sh                 # Switch between MIMO and DeepSeek
└── volumes/
    └── (prometheus and grafana data)
```

## Prerequisites

### System Requirements
- Docker Engine 20.10+
- Docker Compose 1.29+
- NVIDIA Container Runtime
- NVIDIA GPU drivers (525.x or later)
- `nvidia-smi` accessible in PATH
- `curl` for health checks and testing
- `huggingface-cli` for model downloads (`pip install huggingface-hub`)
- `jq` for JSON parsing (optional, for test reports)

### Network Requirements
- Blackwell and A30 servers must be on the same LAN or have stable network connectivity
- Open ports: 8001-8005 (vLLM), 4000 (LiteLLM), 9090 (Prometheus), 3000 (Grafana)

### Storage Requirements
- `/models` directory with at least 500 GB total (models are ~100-150 GB each)
- `~/.cache/huggingface` for model cache (at least 50 GB recommended)

## Installation

### 1. Clone and Setup

```bash
cd /path/to/llm-stack

# Copy environment template
cp .env.example .env

# Make scripts executable
chmod +x scripts/*.sh
```

### 2. Configure `.env`

Edit `.env` with your specific settings:

```bash
nano .env
```

**Key variables to update:**

```bash
# Model storage path (must exist and have write permissions)
MODELS_PATH=/models

# HuggingFace credentials
HF_TOKEN=hf_your_token_here

# Server hostnames (adjust if using different names/IPs)
BLACKWELL_HOST=blackwell
A30_HOST=a30

# GPU memory utilization (0.85-0.90 recommended)
LLAMA33_GPU_MEMORY_UTILIZATION=0.90
QWEN36_GPU_MEMORY_UTILIZATION=0.90
MIMO_GPU_MEMORY_UTILIZATION=0.88
LLAVA_GPU_MEMORY_UTILIZATION=0.85
DEEPSEEK_GPU_MEMORY_UTILIZATION=0.88
```

### 3. Prepare Model Storage

Create and verify model directories:

```bash
mkdir -p /models
chmod 777 /models

# Verify write permissions
touch /models/.test && rm /models/.test
echo "✓ /models is writable"
```

### 4. Verify NVIDIA Setup

```bash
# Check GPU drivers
nvidia-smi

# Check NVIDIA Container Runtime
docker run --rm --runtime=nvidia nvidia/cuda:12.0.0-runtime-ubuntu22.04 nvidia-smi
```

## Quick Start

### Option A: Manual Steps (Recommended for first time)

#### On Blackwell Server:

```bash
# 1. Download models
cd /path/to/llm-stack
./scripts/download-model.sh llama33
./scripts/download-model.sh qwen36

# 2. Start models
./scripts/start-model.sh llama33
./scripts/start-model.sh qwen36

# 3. Verify they're running
./scripts/status.sh
```

#### On A30 Server:

```bash
cd /path/to/llm-stack

# 1. Download models
./scripts/download-model.sh mimo
./scripts/download-model.sh llava

# 2. Start models
./scripts/start-model.sh mimo
./scripts/start-model.sh llava

# 3. Verify
./scripts/status.sh
```

#### On Router Server (usually Blackwell, could be separate):

```bash
# Start LiteLLM router
docker run -d \
    --name litellm-proxy \
    -p 4000:4000 \
    -v $(pwd)/config/litellm-config.yml:/app/config.yml \
    -e LITELLM_LOG=/logs \
    ghcr.io/berriai/litellm:main \
    --config /app/config.yml \
    --host 0.0.0.0 \
    --port 4000

# Verify router is running
curl http://localhost:4000/health
```

### Option B: Start All Models at Once

```bash
# On Blackwell
./scripts/start-model.sh llama33 && ./scripts/start-model.sh qwen36

# On A30
./scripts/start-model.sh mimo && ./scripts/start-model.sh llava
```

## Usage

### Via LiteLLM Router (Recommended)

LiteLLM provides a single unified OpenAI-compatible endpoint:

```bash
# List available models
curl http://localhost:4000/v1/models

# Complete request (any model)
curl -X POST http://localhost:4000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama33",
    "prompt": "Explain quantum computing",
    "max_tokens": 200,
    "temperature": 0.7
  }'

# Chat completion request
curl -X POST http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-llm-stack-master" \
  -d '{
    "model": "qwen36",
    "messages": [{"role": "user", "content": "What is LLM?"}],
    "temperature": 0.8
  }'
```

### Direct to vLLM Endpoint (Debugging)

```bash
# Query llama33 directly
curl -X POST http://blackwell:8001/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama33",
    "prompt": "Hello world",
    "max_tokens": 50
  }'

# Query mimo directly
curl -X POST http://a30:8003/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mimo",
    "prompt": "Test",
    "max_tokens": 50
  }'
```

### Python Client Example

```python
from openai import OpenAI

# Connect to LiteLLM router
client = OpenAI(
    api_key="sk-llm-stack-master",
    base_url="http://localhost:4000/v1"
)

# Simple completion
response = client.completions.create(
    model="llama33",
    prompt="Explain neural networks",
    max_tokens=200,
    temperature=0.7
)

print(response.choices[0].text)

# Chat interface
chat_response = client.chat.completions.create(
    model="qwen36",
    messages=[
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "What is AI?"}
    ],
    temperature=0.8
)

print(chat_response.choices[0].message.content)
```

## Script Reference

### `./scripts/start-model.sh <model_name>`

Start a single model.

```bash
./scripts/start-model.sh llama33
./scripts/start-model.sh mimo

# Auto-downloads if not present, starts service, waits for health check
# Warns if starting conflicting models (deepseek while mimo running)
```

### `./scripts/stop-model.sh <model_name>`

Stop a single model.

```bash
./scripts/stop-model.sh llama33
./scripts/stop-model.sh deepseek
```

### `./scripts/restart-model.sh <model_name>`

Restart a model (stop + start).

```bash
./scripts/restart-model.sh mimo
```

### `./scripts/download-model.sh <model_name>`

Download a model from HuggingFace. Uses `HF_TOKEN` if set, auto-detects model paths.

```bash
./scripts/download-model.sh llama33
./scripts/download-model.sh deepseek
```

### `./scripts/status.sh`

Show comprehensive status of all services, GPU usage, and health.

```bash
./scripts/status.sh
```

Output:
```
========================================
LLM Stack Status Report
========================================

─── SERVICES ───

Server: blackwell
---
  vllm-llama33: ✓ RUNNING
  vllm-qwen36: ✓ RUNNING

Server: a30
---
  vllm-mimo: ✓ RUNNING
  vllm-llava: ✓ RUNNING
  vllm-deepseek: ✗ STOPPED

─── MODELS ───
llama33: ✓ RUNNING (port 8001) | ✓ DOWNLOADED
qwen36: ✓ RUNNING (port 8002) | ✓ DOWNLOADED
mimo: ✓ RUNNING (port 8003) | ✓ DOWNLOADED
llava: ✓ RUNNING (port 8004) | ✓ DOWNLOADED
deepseek: ✗ STOPPED | ✓ DOWNLOADED

─── GPU USAGE ───
GPU 0 (NVIDIA RTX PRO 6000): 95% util, 85000/98304 MB (87%)
GPU 1 (NVIDIA RTX PRO 6000): 92% util, 84000/98304 MB (85%)
GPU 2 (NVIDIA A30): 88% util, 20000/24576 MB (81%)
GPU 3 (NVIDIA A30): 90% util, 22000/24576 MB (89%)
GPU 4 (NVIDIA A30): 32% util, 6000/24576 MB (24%)

─── LITELLM ROUTER ───
✓ LiteLLM Router: RUNNING on port 4000

─── MODEL ENDPOINTS ───
✓ llama33: http://localhost:8001 (port 8001)
✓ qwen36: http://localhost:8002 (port 8002)
✓ mimo: http://localhost:8003 (port 8003)
✓ llava: http://localhost:8004 (port 8004)
✗ deepseek: STOPPED (port 8005)
```

### `./scripts/test-model.sh <model_name|--all> [prompt]`

Test a model with a simple prompt and measure latency.

```bash
# Test single model
./scripts/test-model.sh llama33
./scripts/test-model.sh qwen36 "What is quantum computing?"

# Test all models
./scripts/test-model.sh --all
```

Output:
```
[2024-05-20 14:32:15] INFO: Testing model llama33 at http://localhost:8001/v1/completions
[2024-05-20 14:32:15] INFO: Prompt: What is an LLM? Please provide a brief explanation.

Response received in 2350ms

Response:
---
An LLM (Large Language Model) is a type of artificial intelligence model trained on vast amounts of text data from the internet and other sources. These models are designed to understand and generate human language through patterns learned during training. LLMs like GPT, BERT, and others can perform various NLP tasks such as text completion, translation, summarization, and question answering. They are the foundation of modern conversational AI systems.
---

Usage:
{
  "completion_tokens": 89,
  "prompt_tokens": 17,
  "total_tokens": 106
}
```

### `./scripts/swap-deepseek.sh {--enable|--disable|--status}`

Switch between MIMO and DeepSeek (they share A30 GPUs 0,1).

```bash
# Enable DeepSeek (stops MIMO)
./scripts/swap-deepseek.sh --enable

# Disable DeepSeek (starts MIMO)
./scripts/swap-deepseek.sh --disable

# Check current status
./scripts/swap-deepseek.sh --status
```

## MIMO ↔ DeepSeek: Manual Switching

Both models share A30 GPUs 0+1 with tensor-parallel-size=2. Only one can run at a time.

### Switch to DeepSeek:

```bash
# Option 1: Use swap script (recommended)
./scripts/swap-deepseek.sh --enable

# Option 2: Manual
./scripts/stop-model.sh mimo
sleep 2
./scripts/start-model.sh deepseek
```

### Switch back to MIMO:

```bash
# Option 1: Use swap script (recommended)
./scripts/swap-deepseek.sh --disable

# Option 2: Manual
./scripts/stop-model.sh deepseek
sleep 2
./scripts/start-model.sh mimo
```

### View current state:

```bash
./scripts/swap-deepseek.sh --status
./scripts/status.sh | grep -A 10 "MODELS"
```

## cURL Examples

### Basic Completion

```bash
# Llama 3.3
curl -X POST http://localhost:4000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama33",
    "prompt": "The future of AI is",
    "max_tokens": 100,
    "temperature": 0.8,
    "top_p": 0.95
  }'
```

### Chat Completions (OpenAI format)

```bash
curl -X POST http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-llm-stack-master" \
  -d '{
    "model": "qwen36",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "Explain relativity in simple terms"}
    ],
    "temperature": 0.7,
    "max_tokens": 250
  }'
```

### Stream Response

```bash
curl -X POST http://localhost:4000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llava",
    "prompt": "List 5 benefits of renewable energy:",
    "max_tokens": 150,
    "stream": true
  }' \
  | jq -R 'select(length > 0) | fromjson'
```

### List Available Models

```bash
curl http://localhost:4000/v1/models | jq .
```

## Monitoring (Optional)

### Start Monitoring Stack

```bash
# In compose directory
docker-compose -f compose/docker-compose.monitoring.yml up -d
```

### Access Dashboards

- **Grafana**: http://localhost:3000 (login: admin / password: admin)
- **Prometheus**: http://localhost:9090

### Create Grafana Dashboard

1. Add Prometheus datasource: `http://prometheus:9090`
2. Create panels for:
   - GPU utilization per model
   - Request latency (p50, p95, p99)
   - Token throughput (tokens/sec)
   - Error rates

Example Prometheus queries:

```promql
# GPU memory usage
nvidia_gpu_memory_used_mb

# Model request latency
histogram_quantile(0.99, rate(vllm_request_duration_seconds_bucket[5m]))

# Throughput
rate(vllm_tokens_generated_total[1m])
```

## Troubleshooting

### Error: "No CUDA devices found"

**Symptoms**: vLLM containers won't start, "CUDA_ERROR_NO_DEVICE"

**Solutions**:
1. Verify GPU drivers: `nvidia-smi`
2. Ensure NVIDIA Container Runtime is installed:
   ```bash
   docker run --rm --runtime=nvidia nvidia/cuda:12.0.0-runtime-ubuntu22.04 nvidia-smi
   ```
3. Check Docker daemon config includes nvidia runtime:
   ```bash
   cat /etc/docker/daemon.json | grep nvidia
   ```

### Error: "Failed to allocate tensor" or CUDA OOM

**Symptoms**: Model fails during inference with memory errors

**Solutions**:
1. Reduce `gpu_memory_utilization` in `.env`:
   ```bash
   LLAMA33_GPU_MEMORY_UTILIZATION=0.80  # Reduce from 0.90
   ```
2. Increase shared memory in docker-compose:
   ```yaml
   shm_size: 24gb  # Increase from 16gb
   ```
3. Restart model:
   ```bash
   ./scripts/restart-model.sh llama33
   ```
4. Check concurrent requests aren't overloading GPU

### Error: "Connection refused" when accessing vLLM

**Symptoms**: `curl http://localhost:8001/health` → "Connection refused"

**Solutions**:
1. Check if service is running:
   ```bash
   ./scripts/status.sh
   docker ps | grep vllm
   ```
2. Wait for warmup (can take 30-60s after start):
   ```bash
   # Watch logs during startup
   docker-compose -f compose/docker-compose.blackwell.yml logs -f vllm-llama33
   ```
3. Check port not in use by another service:
   ```bash
   lsof -i :8001
   ```

### Error: "Model not found on HuggingFace hub"

**Symptoms**: `download-model.sh` fails, model doesn't exist

**Solutions**:
1. Verify model names are correct in `model-lib.sh`
2. Check HuggingFace token if model is gated:
   ```bash
   export HF_TOKEN=hf_your_token
   huggingface-cli download meta-llama/Llama-2-70b-chat
   ```
3. Try manual download to test connectivity:
   ```bash
   huggingface-cli download --repo-type model \
     meta-llama/Llama-3.3-70B-Instruct-AWQ
   ```

### Error: "vLLM + DeepSeek CPU memory at 100%"

**Symptoms**: System becomes unresponsive during model warmup

**Solutions**:
1. Reduce max_model_len temporarily:
   ```bash
   DEEPSEEK_MAX_MODEL_LEN=8192  # Reduce from 16384
   ./scripts/restart-model.sh deepseek
   ```
2. Increase Docker memory limits
3. Close other applications to free system RAM

### MIMO and DeepSeek conflict

**Symptoms**: Can't start deepseek because mimo is running

**Solutions**:
```bash
# Properly swap
./scripts/swap-deepseek.sh --enable

# Or manual
./scripts/stop-model.sh mimo
sleep 3  # Wait for GPU memory to free
./scripts/start-model.sh deepseek
```

### "NCCL initialization failed" (multi-GPU tensor-parallel)

**Symptoms**: MIMO fails with "NCCL_ERROR", or hangs on tensor-parallel init

**Solutions**:
1. Ensure `ipc: host` is set in docker-compose (already done)
2. Set NCCL environment in compose:
   ```yaml
   environment:
     - NCCL_DEBUG=INFO
     - NCCL_IB_DISABLE=1  # If no InfiniBand
   ```
3. Check network between GPUs is valid (usually automatic on same machine)

### HuggingFace authentication timeout

**Symptoms**: Download stuck at "Downloading..." for hours

**Solutions**:
1. Add HF_TOKEN to `.env` if model is private/gated
2. Test token:
   ```bash
   export HF_TOKEN=hf_your_token
   huggingface-cli whoami
   ```
3. Check internet connectivity
4. Try manual download with timeout:
   ```bash
   timeout 300 huggingface-cli download \
     --repo-type model \
     --cache-dir /models \
     meta-llama/Llama-3.3-70B-Instruct-AWQ
   ```

### "Port already in use"

**Symptoms**: `docker-compose up` fails with "Address already in use"

**Solutions**:
```bash
# Find what's using the port
lsof -i :8001

# Kill existing process/container
docker ps -a | grep llm
docker rm -f llm-llama33

# Try again
./scripts/start-model.sh llama33
```

### LiteLLM router not routing correctly

**Symptoms**: Requests to LiteLLM don't reach correct backend

**Solutions**:
1. Verify litellm-config.yml has correct backend endpoints:
   ```bash
   cat config/litellm-config.yml | grep api_base
   ```
2. Test direct connection to backend:
   ```bash
   curl http://blackwell:8001/health
   curl http://a30:8003/health
   ```
3. Check LiteLLM logs:
   ```bash
   docker logs litellm-proxy | grep -E "ERROR|routing|backend"
   ```
4. Reload config (some changes require restart):
   ```bash
   docker restart litellm-proxy
   ```

## Performance Tuning

### GPU Memory Utilization

Start conservative, increase if stable:

```bash
# Conservative (safer, lower throughput)
GPU_MEMORY_UTILIZATION=0.80

# Balanced (recommended)
GPU_MEMORY_UTILIZATION=0.88

# Aggressive (higher throughput, higher OOM risk)
GPU_MEMORY_UTILIZATION=0.95
```

Update in `.env` and restart model:

```bash
./scripts/restart-model.sh llama33
```

### Max Model Length

Reduce if getting OOM during longer inferences:

```bash
# Shorter context (faster, lower VRAM)
LLAMA33_MAX_MODEL_LEN=16384

# Default
LLAMA33_MAX_MODEL_LEN=32768

# Extended (higher VRAM, slower)
LLAMA33_MAX_MODEL_LEN=49152
```

### Batch Size / Request Queue

vLLM auto-tunes, but can monitor:

```bash
# Check queue depth in logs
docker-compose -f compose/docker-compose.blackwell.yml logs -f vllm-llama33 | grep -i queue
```

## Advanced

### Custom vLLM Parameters

Edit docker-compose files to add vLLM args:

In `compose/docker-compose.blackwell.yml`:

```yaml
command: >
  --model /models/llama-3.3-70b-instruct-awq
  --served-model-name llama33
  --port 8000
  --gpu-memory-utilization 0.90
  --max-model-len 32768
  --tensor-parallel-size 1
  --trust-remote-code
  --dtype half
  --enable-prefix-caching
```

Common useful flags:
- `--dtype half`: Use float16 (smaller memory footprint)
- `--enable-prefix-caching`: KV cache optimization for common prefixes
- `--enforce-eager`: Disable automatic scheduling (for debugging)
- `--disable-custom-all-reduce`: Fix NCCL issues sometimes

### Multi-Node Tensor Parallelism

If models need more than 2 GPUs, split across nodes:

```yaml
command: >
  --model /models/llama-3.3-70b
  --tensor-parallel-size 4
  --pipeline-parallel-size 1
  --distributed-executor-backend ray
```

Requires Ray setup, beyond scope of this guide.

## License & Attribution

- **vLLM**: Apache 2.0
- **LiteLLM**: Apache 2.0
- **Docker**: Various (see individual images)

## Support & Contributions

For issues or improvements:
1. Check troubleshooting section above
2. Review Docker logs: `docker-compose logs [service]`
3. Check GPU health: `nvidia-smi`
4. Verify network connectivity between servers

---

**Last Updated**: May 2024  
**vLLM Version**: Latest  
**Docker Compose Version**: 1.29+
