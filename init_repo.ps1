param(
  [string]$Name = "boatdash",
  [ValidateSet('public','private')] [string]$Visibility = 'public',
  [string]$Desc = "BoatDash (ESP32-S3, ESP-IDF 5.4)",
  [string]$Owner = "kingspidor",       # change if pushing to a different account
  [switch]$Force
)
$ErrorActionPreference = 'Stop'

function New-IfMissing {
  param([string]$Path,[string]$Content)
  if (-not (Test-Path $Path) -or $Force) { $Content | Set-Content -Encoding utf8 -Path $Path }
}

# --- Basic repo hygiene files ---
New-IfMissing ".gitattributes" @'
* text=auto eol=lf
'@

New-IfMissing ".gitignore" @'
# IDF build artifacts
build/
managed_components/
CMakeCache.txt
cmake-build-*/
*.pyc
.vscode/
.idea/
.DS_Store
sdkconfig
sdkconfig.old
littlefs_image.bin
'@

# LICENSE (MIT)
$year = (Get-Date).Year
New-IfMissing "LICENSE" @"
MIT License

Copyright (c) $year $Owner

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"@

# README (short)
New-IfMissing "README.md" @"
# $Name

ESP32‑S3 boat dashboard with SoftAP Web UI, WebSockets, LittleFS assets, AP+STA, and SoftAP‑only OTA with rollback (ESP‑IDF 5.4). See `Spec-1-ESP32S3 SoftAP + OTA (Async)` for details.

## Quick build
```powershell
idf.py set-target esp32s3
idf.py menuconfig   # set Partition Table: custom -> partitions.csv, Flash size: 16MB
idf.py build
idf.py -p COMx flash monitor
```
"@

# Ensure project‑root IDF component manifest depends on official esp_littlefs
New-IfMissing "idf_component.yml" @'
dependencies:
  idf: ">=5.0"
  espressif/esp_littlefs: "^1"
'@

# --- Create & push Git repo via SSH ---
if (-not (Test-Path .git)) { git init | Out-Null }
# create main if it doesn't exist
try { git rev-parse --abbrev-ref HEAD | Out-Null } catch { git checkout -b main | Out-Null }

# Stage & commit
if ($Force) { git add -A } else { git add . }
if (-not (git log -1 2>$null)) { git commit -m "chore: initial import" | Out-Null } else { git commit -m "chore: repo bootstrap" -a | Out-Null }

# Make sure gh uses SSH
try { gh config set git_protocol ssh 2>$null | Out-Null } catch {}

# Try to create the repo; if it exists, just set remote and push
$createArgs = @("repo","create",$Name,"--$Visibility","--source",".","--remote","origin","--push","--description",$Desc)
try {
  gh @createArgs | Out-Null
}
catch {
  # If already exists, add remote and push
  $remote = "git@github.com:$Owner/$Name.git"
  if (-not (git remote 2>$null | Select-String -SimpleMatch "origin")) { git remote add origin $remote }
  git push -u origin main
}

Write-Host "\nRepo ready: $(git config --get remote.origin.url)" -ForegroundColor Green
