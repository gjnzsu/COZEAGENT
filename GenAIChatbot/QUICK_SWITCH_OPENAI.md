# 快速切换到 OpenAI ChatGPT

## 方法 1: 使用 PowerShell 脚本 (推荐)

在 `C:\SourceCode\GenAIChatbot` 目录下运行：

```powershell
.\switch_to_openai.ps1 -ApiKey "你的API密钥" -Model "gpt-4o"
```

**可用的模型名称：**
- `gpt-4o` - 最新最强大的模型 (推荐)
- `gpt-4o-mini` - 经济实惠版本
- `gpt-3.5-turbo` - 快速且经济
- `gpt-4-turbo` - GPT-4 增强版
- `gpt-4` - 原始 GPT-4

**示例：**
```powershell
# 使用 GPT-4o (推荐)
.\switch_to_openai.ps1 -ApiKey "sk-proj-..." -Model "gpt-4o"

# 使用 GPT-3.5 Turbo (经济实惠)
.\switch_to_openai.ps1 -ApiKey "sk-proj-..." -Model "gpt-3.5-turbo"
```

## 方法 2: 手动编辑 .env 文件

1. 打开 `generative-ai-chatbot\.env` 文件
2. 修改或添加以下内容：

```env
LLM_PROVIDER=openai
OPENAI_API_KEY=你的API密钥
OPENAI_MODEL=gpt-4o
```

## 方法 3: 设置环境变量 (临时)

在 PowerShell 中：

```powershell
$env:LLM_PROVIDER="openai"
$env:OPENAI_API_KEY="你的API密钥"
$env:OPENAI_MODEL="gpt-4o"
```

## 运行聊天机器人

配置完成后，运行：

```powershell
cd generative-ai-chatbot
python src/chatbot.py
```

## 常见问题

### 错误: "无法识别脚本文件"
- 确保你在 `C:\SourceCode\GenAIChatbot` 目录下
- 或者使用完整路径: `.\generative-ai-chatbot\switch_to_openai.ps1`

### PowerShell 执行策略错误
如果遇到执行策略错误，运行：
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### 模型名称错误
确保使用正确的模型名称（见上面的列表）。`gpt-5.1` 不存在，请使用 `gpt-4o` 或 `gpt-3.5-turbo`。

