[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceIso,
    [Parameter(Mandatory)][string]$DestinationIso,
    [Parameter(Mandatory)][string]$OscdimgPath,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run PowerShell or Terraform from an elevated Administrator terminal."
    }
}

function Remove-DirectoryWithRetry {
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$MaxAttempts = 10,
        [switch]$IgnoreFailure
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $lastError = $null
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            return
        }
        catch {
            $lastError = $_
            if ($attempt -lt $MaxAttempts) {
                Start-Sleep -Seconds 1
            }
        }
    }

    if ($IgnoreFailure) {
        Write-Warning "Could not remove staging directory '$Path' after $MaxAttempts attempts. It will be removed on the next run. $($lastError.Exception.Message)"
        return
    }

    throw "Could not remove staging directory '$Path' after $MaxAttempts attempts. $($lastError.Exception.Message)"
}

function Export-HybridEfiBootImage {
    param(
        [Parameter(Mandatory)][string]$IsoPath,
        [Parameter(Mandatory)][string]$DestinationPath
    )

    # Ubuntu 24.04.2 uses a hybrid ISO with its UEFI FAT image appended as a
    # GPT EFI System Partition rather than storing boot/grub/efi.img in the
    # ISO filesystem. Extract that partition for oscdimg's UEFI El Torito entry.
    $efiSystemPartitionGuid = [guid]"c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
    $sectorSize = [uint64]512
    $stream = [System.IO.File]::Open($IsoPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try {
        $gptHeader = [byte[]]::new(512)
        $stream.Position = 512
        if ($stream.Read($gptHeader, 0, $gptHeader.Length) -ne $gptHeader.Length -or
            [System.Text.Encoding]::ASCII.GetString($gptHeader, 0, 8) -ne "EFI PART") {
            throw "No GPT partition table was found in ISO: $IsoPath"
        }

        $entryLba = [BitConverter]::ToUInt64($gptHeader, 72)
        $entryCount = [BitConverter]::ToUInt32($gptHeader, 80)
        $entrySize = [BitConverter]::ToUInt32($gptHeader, 84)
        if ($entrySize -lt 56) {
            throw "Unsupported GPT partition entry size in ISO: $IsoPath"
        }

        $efiEntry = $null
        for ($index = 0; $index -lt $entryCount; $index++) {
            $entry = [byte[]]::new($entrySize)
            $stream.Position = [int64](($entryLba * $sectorSize) + ([uint64]$index * $entrySize))
            if ($stream.Read($entry, 0, $entry.Length) -ne $entry.Length) {
                throw "Could not read GPT partition entry from ISO: $IsoPath"
            }

            if ([guid]::new([byte[]]$entry[0..15]) -eq $efiSystemPartitionGuid) {
                $efiEntry = $entry
                break
            }
        }

        if ($null -eq $efiEntry) {
            throw "No EFI System Partition was found in ISO: $IsoPath"
        }

        $firstLba = [BitConverter]::ToUInt64($efiEntry, 32)
        $lastLba = [BitConverter]::ToUInt64($efiEntry, 40)
        if ($lastLba -lt $firstLba) {
            throw "EFI System Partition has an invalid size in ISO: $IsoPath"
        }

        $remaining = [int64](($lastLba - $firstLba + 1) * $sectorSize)
        $stream.Position = [int64]($firstLba * $sectorSize)
        $destinationStream = [System.IO.File]::Open($DestinationPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
        try {
            $buffer = [byte[]]::new(1048576)
            while ($remaining -gt 0) {
                $bytesToRead = [Math]::Min([int64]$buffer.Length, $remaining)
                $bytesRead = $stream.Read($buffer, 0, [int]$bytesToRead)
                if ($bytesRead -eq 0) {
                    throw "Could not read the complete EFI System Partition from ISO: $IsoPath"
                }
                $destinationStream.Write($buffer, 0, $bytesRead)
                $remaining -= $bytesRead
            }
        }
        finally {
            $destinationStream.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

Assert-Administrator

if (-not (Test-Path -LiteralPath $SourceIso -PathType Leaf)) {
    throw "Ubuntu ISO not found: $SourceIso"
}
if (-not (Test-Path -LiteralPath $OscdimgPath -PathType Leaf)) {
    throw "oscdimg.exe not found: $OscdimgPath"
}
if ((Test-Path -LiteralPath $DestinationIso -PathType Leaf) -and -not $Force) {
    Write-Host "Using existing unattended installer ISO: $DestinationIso"
    exit 0
}

$destinationDirectory = Split-Path -Parent $DestinationIso
$stagingDirectory = "$DestinationIso.staging"
$outputIso = "$DestinationIso.new"
$mountedImage = $null

try {
    New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    if (Test-Path -LiteralPath $stagingDirectory) {
        Remove-DirectoryWithRetry -Path $stagingDirectory
    }
    New-Item -ItemType Directory -Path $stagingDirectory | Out-Null

    $mountedImage = Mount-DiskImage -ImagePath $SourceIso -PassThru
    $volume = $mountedImage | Get-Volume
    if (-not $volume.DriveLetter) {
        throw "Could not determine a drive letter for mounted ISO: $SourceIso"
    }

    $sourceRoot = "$($volume.DriveLetter):\"
    & robocopy $sourceRoot $stagingDirectory /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
    if ($LASTEXITCODE -gt 7) {
        throw "Failed to copy the Ubuntu ISO contents (robocopy exit code $LASTEXITCODE)."
    }

    $grubConfig = Join-Path $stagingDirectory "boot\grub\grub.cfg"
    if (-not (Test-Path -LiteralPath $grubConfig -PathType Leaf)) {
        throw "Unsupported Ubuntu ISO layout: missing $grubConfig"
    }

    $grubContent = Get-Content -LiteralPath $grubConfig -Raw
    $patchedGrubContent = [regex]::Replace(
        $grubContent,
        '(?m)^(\s*linux\s+.*?)(\s+---\s*)$',
        '$1 autoinstall$2'
    )
    if ($patchedGrubContent -eq $grubContent) {
        throw "Could not add the autoinstall kernel argument to $grubConfig"
    }

    # robocopy preserves the source ISO's read-only file attribute. Clear it
    # before modifying the copied GRUB configuration in the staging directory.
    Set-ItemProperty -LiteralPath $grubConfig -Name IsReadOnly -Value $false
    [System.IO.File]::WriteAllText(
        $grubConfig,
        $patchedGrubContent,
        [System.Text.UTF8Encoding]::new($false)
    )

    $biosBootImage = Join-Path $stagingDirectory "boot\grub\i386-pc\eltorito.img"
    if (-not (Test-Path -LiteralPath $biosBootImage -PathType Leaf)) {
        throw "Unsupported Ubuntu ISO layout: missing BIOS boot image $biosBootImage"
    }

    $efiBootImage = Join-Path $stagingDirectory "boot\grub\efi.img"
    if (-not (Test-Path -LiteralPath $efiBootImage -PathType Leaf)) {
        Export-HybridEfiBootImage -IsoPath $SourceIso -DestinationPath $efiBootImage
    }

    $bootData = "-bootdata:2#p0,e,b$biosBootImage#pEF,e,b$efiBootImage"
    if (Test-Path -LiteralPath $outputIso -PathType Leaf) {
        Remove-Item -LiteralPath $outputIso -Force
    }
    & $OscdimgPath -m -o -u2 -udfver102 $bootData $stagingDirectory $outputIso | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "oscdimg failed with exit code $LASTEXITCODE while creating $outputIso"
    }

    if (Test-Path -LiteralPath $DestinationIso -PathType Leaf) {
        Remove-Item -LiteralPath $DestinationIso -Force
    }
    Move-Item -LiteralPath $outputIso -Destination $DestinationIso

    Write-Host "Created unattended installer ISO: $DestinationIso"
}
finally {
    if ($mountedImage) {
        $null = Dismount-DiskImage -ImagePath $SourceIso -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $stagingDirectory) {
        Remove-DirectoryWithRetry -Path $stagingDirectory -IgnoreFailure
    }
    if (Test-Path -LiteralPath $outputIso -PathType Leaf) {
        Remove-Item -LiteralPath $outputIso -Force
    }
}
