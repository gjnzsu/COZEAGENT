# PowerShell script to switch to OpenAI ChatGPT
# Usage: .\switch_to_openai.ps1 -ApiKey "your-api-key-here" -Model "gpt-4o"
# Run this from the GenAIChatbot root directory

param(
    [Parameter(Mandatory=$true)]
    [string]$ApiKey,
    
    [Parameter(Mandatory=$false)]
    [string]$Model = "gpt-4o"
)

# Path to .env file in generative-ai-chatbot directory
$projectDir = Join-Path $PSScriptRoot "generative-ai-chatbot"
$envFile = Join-Path $projectDir ".env"

# Validate model name
$validModels = @("gpt-4o", "gpt-4o-mini", "gpt-4.1", "gpt-4-turbo", "gpt-4", "gpt-3.5-turbo", "gpt-3.5-turbo-0125")
if ($Model -notin $validModels) {
    Write-Host "⚠ Warning: '$Model' may not be a valid OpenAI model." -ForegroundColor Yellow
    Write-Host "Valid models: $($validModels -join ', ')" -ForegroundColor Yellow
    Write-Host "Continuing anyway..." -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "Switching chatbot to OpenAI ChatGPT..." -ForegroundColor Cyan
Write-Host ""

# Check if project directory exists
if (-not (Test-Path $projectDir)) {
    Write-Host "❌ Error: Cannot find 'generative-ai-chatbot' directory!" -ForegroundColor Red
    Write-Host "Please run this script from: C:\SourceCode\GenAIChatbot" -ForegroundColor Yellow
    exit 1
}

# Check if .env file exists
if (Test-Path $envFile) {
    Write-Host "Found .env file. Updating configuration..." -ForegroundColor Yellow
    
    # Read existing .env file
    $content = Get-Content $envFile
    
    # Update or add LLM_PROVIDER
    if ($content -match "^LLM_PROVIDER=") {
        $content = $content -replace "^LLM_PROVIDER=.*", "LLM_PROVIDER=openai"
    } else {
        $content += "LLM_PROVIDER=openai"
    }
    
    # Update or add OPENAI_API_KEY
    if ($content -match "^OPENAI_API_KEY=") {
        $content = $content -replace "^OPENAI_API_KEY=.*", "OPENAI_API_KEY=$ApiKey"
    } else {
        $content += "OPENAI_API_KEY=$ApiKey"
    }
    
    # Update or add OPENAI_MODEL
    if ($content -match "^OPENAI_MODEL=") {
        $content = $content -replace "^OPENAI_MODEL=.*", "OPENAI_MODEL=$Model"
    } else {
        $content += "OPENAI_MODEL=$Model"
    }
    
    # Write back to file
    $content | Set-Content $envFile
    
    Write-Host "✓ Updated .env file successfully!" -ForegroundColor Green
} else {
    Write-Host ".env file not found. Creating new one..." -ForegroundColor Yellow
    
    # Create new .env file
    @"
# LLM Provider Configuration
LLM_PROVIDER=openai
OPENAI_API_KEY=$ApiKey
OPENAI_MODEL=$Model
"@ | Set-Content $envFile
    
    Write-Host "✓ Created .env file successfully!" -ForegroundColor Green
}

Write-Host ""
Write-Host "Configuration updated:" -ForegroundColor Cyan
Write-Host "  Provider: openai" -ForegroundColor White
Write-Host "  Model: $Model" -ForegroundColor White
Write-Host "  API Key: $($ApiKey.Substring(0, [Math]::Min(10, $ApiKey.Length)))..." -ForegroundColor White
Write-Host ""
Write-Host "You can now run:" -ForegroundColor Green
Write-Host "  cd generative-ai-chatbot" -ForegroundColor White
Write-Host "  python src/chatbot.py" -ForegroundColor White

