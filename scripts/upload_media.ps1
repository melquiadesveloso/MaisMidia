Param(
  [Parameter(Mandatory=$true)][string]$AcademyId,
  [Parameter(Mandatory=$true)][string]$Bucket,
  [string]$Region = "us-east-1",
  [string]$Path = "."
)

function Write-Info($m){ Write-Host $m -ForegroundColor Green }
function Write-Warn($m){ Write-Host $m -ForegroundColor Yellow }
function Write-Err($m){ Write-Host $m -ForegroundColor Red }

if (-not (Test-Path $Path)) { Write-Err "Caminho não existe: $Path"; exit 1 }

$exts = @('jpg','jpeg','png','gif','mp4','avi','mov','webm')
$files = Get-ChildItem -Path $Path -Recurse -File | Where-Object { $exts -contains $_.Extension.TrimStart('.') }

foreach($f in $files){
  $key = "academies/$AcademyId/$($f.Name)"
  Write-Info "Enviando $($f.FullName) -> s3://$Bucket/$key"
  aws s3 cp "$($f.FullName)" "s3://$Bucket/$key" --region $Region --metadata "academy-id=$AcademyId" | Out-Null
}

Write-Info "Concluído. Total: $($files.Count) arquivos."

