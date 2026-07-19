param(
    [Parameter(Mandatory = $true)][string]$ImagePath,
    [Parameter(Mandatory = $true)][string]$AlphaPath,
    [Parameter(Mandatory = $true)][string]$OutputPath
)

Add-Type -AssemblyName System.Drawing

$source = [System.Drawing.Bitmap]::FromFile((Resolve-Path $ImagePath))
$alpha = [System.IO.File]::ReadAllBytes((Resolve-Path $AlphaPath))
$pixelCount = $source.Width * $source.Height
if ($alpha.Length -ne $pixelCount) {
    $source.Dispose()
    throw "Alpha byte count $($alpha.Length) does not match image pixel count $pixelCount."
}

$target = New-Object System.Drawing.Bitmap $source.Width, $source.Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
for ($y = 0; $y -lt $source.Height; $y++) {
    for ($x = 0; $x -lt $source.Width; $x++) {
        $index = $y * $source.Width + $x
        $rgb = $source.GetPixel($x, $y)
        $target.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($alpha[$index], $rgb.R, $rgb.G, $rgb.B))
    }
}

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory -and -not (Test-Path $outputDirectory)) {
    New-Item -ItemType Directory -Force $outputDirectory | Out-Null
}
$target.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
$target.Dispose()
$source.Dispose()

Get-Item $OutputPath | Select-Object FullName, Length
