$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$build = Join-Path $root "build"

New-Item -ItemType Directory -Force -Path $build | Out-Null

$functions = @(
    @{
        Name = "taskflow"
        Source = Join-Path $root "app\taskflow"
        Output = Join-Path $build "taskflow.zip"
    },
    @{
        Name = "incident_classifier"
        Source = Join-Path $root "app\incident_classifier"
        Output = Join-Path $build "incident_classifier.zip"
    }
)

foreach ($function in $functions) {
    if (Test-Path $function.Output) {
        Remove-Item $function.Output -Force
    }

    Compress-Archive `
        -Path (Join-Path $function.Source "lambda_function.py") `
        -DestinationPath $function.Output `
        -CompressionLevel Optimal

    Write-Host "Packaged $($function.Name): $($function.Output)"
}

Write-Host "Lambda packaging completed."
