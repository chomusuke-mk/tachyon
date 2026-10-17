$ErrorActionPreference = 'Stop';

# --- Script de desinstalación para Tachyon ---

$packageName = 'tachyon'
$installerType = 'exe'
$silentArgs = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART'
$softwareName = 'Tachyon*'

# Buscamos la llave de registro de InnoSetup para Tachyon
[array]$key = Get-UninstallRegistryKey -SoftwareName $softwareName
if ($key.Count -eq 1) {
    # InnoSetup a veces envuelve la ruta en comillas. Las removemos.
    $uninstallString = $key.UninstallString -replace '"', ''
    
    if ($uninstallString -ne $null -and $uninstallString -ne '') {
        Write-Host "Found uninstaller: $uninstallString"
        Uninstall-ChocolateyPackage -PackageName $packageName -FileType 'exe' -SilentArgs $silentArgs -File $uninstallString
    }
} elseif ($key.Count -eq 0) {
    Write-Warning "Uninstall key not found for '$softwareName'."
} else {
    Write-Warning "There are multiple entries for '$softwareName'. Please check the registry manually."
}
