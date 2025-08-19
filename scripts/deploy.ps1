Param(
  [string]$Environment = "prod",
  [string]$Region = "us-east-1"
)

function Write-Info($msg){ Write-Host ("[" + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + "] " + $msg) -ForegroundColor Green }
function Write-Err($msg){ Write-Host ("[" + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + "] " + $msg) -ForegroundColor Red }

try {
  Write-Info "Verificando AWS CLI e Terraform..."
  aws --version | Out-Null
  terraform -version | Out-Null

  Write-Info "Instalando dependências da Lambda..."
  Push-Location lambda
  if (Test-Path requirements.txt) {
    pip install -r requirements.txt -t . | Out-Null
  }
  Pop-Location

  Write-Info "Inicializando Terraform..."
  Push-Location infrastructure/terraform
  terraform init | Out-Null
  terraform apply -auto-approve -var "environment=$Environment" -var "region=$Region"

  $apiUrl = terraform output -raw api_gateway_url
  $cdnUrl = terraform output -raw cloudfront_url
  $bucket = terraform output -raw s3_bucket_name
  Pop-Location

  Write-Info "Publicando frontend no S3..."
  aws s3 sync "frontend" "s3://$bucket/" --delete | Out-Null

  Write-Host "\nURLs:" -ForegroundColor Cyan
  Write-Host "API: $apiUrl" -ForegroundColor Yellow
  Write-Host "CloudFront: $cdnUrl" -ForegroundColor Yellow
  Write-Host "Bucket: s3://$bucket" -ForegroundColor Yellow

  Write-Host "\nAtualize frontend/script.js substituindo REPLACE_WITH_API_URL por: $apiUrl" -ForegroundColor Cyan
}
catch {
  Write-Err $_
  exit 1
}

