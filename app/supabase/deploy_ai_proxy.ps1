# Despliega la Edge Function ai_proxy al proyecto vinculado en .temp/linked-project.json
#
# UNA VEZ: crea un token en https://supabase.com/dashboard/account/tokens
# Luego en PowerShell (solo esta sesión):
#   $env:SUPABASE_ACCESS_TOKEN = "tu_token_aqui"
#   .\supabase\deploy_ai_proxy.ps1
#
# O en una sola línea:
#   $env:SUPABASE_ACCESS_TOKEN="..."; .\supabase\deploy_ai_proxy.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not $env:SUPABASE_ACCESS_TOKEN) {
  Write-Error "Falta SUPABASE_ACCESS_TOKEN. Crea un token en Supabase Dashboard > Account > Access Tokens y exportalo como variable de entorno."
}

$linkPath = Join-Path $PSScriptRoot ".temp/linked-project.json"
if (-not (Test-Path $linkPath)) {
  Write-Error "No existe $linkPath. Ejecuta: npx supabase link --project-ref TU_REF"
}

$ref = (Get-Content $linkPath -Raw | ConvertFrom-Json).ref
Write-Host "Desplegando ai_proxy al proyecto $ref ..."

npx --yes supabase@latest functions deploy ai_proxy --project-ref $ref

if ($LASTEXITCODE -eq 0) {
  Write-Host "Listo: ai_proxy desplegada."
} else {
  exit $LASTEXITCODE
}
