# Script para preparar el despliegue automático de Frifalca C.A.
# Este script compila la web y el APK, y los organiza en la carpeta de Hosting.

Write-Host "--- Iniciando proceso de preparación de despliegue ---" -ForegroundColor Cyan

# 1. Compilar Web
Write-Host "Compilando versión Web..." -ForegroundColor Yellow
flutter build web --release

# 2. Asegurar que la carpeta de destino existe
$publicDir = "build/web"
if (!(Test-Path $publicDir)) {
    New-Item -ItemType Directory -Path $publicDir
}

# 3. Copiar version.json a la carpeta pública
Write-Host "Copiando archivo de versión..." -ForegroundColor Green
if (Test-Path "version.json") {
    Copy-Item "version.json" "$publicDir/version.json" -Force
} else {
    Write-Warning "No se encontró version.json en la raíz. Asegúrate de tenerlo para que la app detecte cambios."
}

Write-Host "--- ¡Preparación completada! Ahora puedes ejecutar 'firebase deploy' o el script hará el deploy por ti si lo activas. ---" -ForegroundColor Cyan
