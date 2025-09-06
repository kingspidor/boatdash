param(
  [string]boatdash = "boatdash",
  [string]BoatDash (ESP32-S3, ESP-IDF 5.4) = "BoatDash (ESP32-S3, ESP-IDF 5.4)",
  [string]main = "main"
)
Stop = 'Stop'
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  Write-Error "Install GitHub CLI first: winget install GitHub.cli"
}
if (-not (Test-Path .git)) { git init | Out-Null }
if (-not (git branch --show-current)) { git checkout -b main }
git add .
git commit -m "chore: scaffold boatdash" | Out-Null
# Creates a repo under your account; requires 'gh auth login'
& gh repo create boatdash --public --source=. --remote=origin --push --description BoatDash (ESP32-S3, ESP-IDF 5.4)
Write-Host "Created and pushed to GitHub repo: boatdash"
