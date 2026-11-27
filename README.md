# ShadeVeil

Utilidad nativa de escritorio para Windows 10/11 (PowerShell 5.1 y 7+ / WPF) que integra un **velo de pantalla click-through** para reducir la iluminación percibida por privacidad y comodidad visual, con control deslizante intuitivo de opacidad, soporte multi-monitor, bandeja del sistema y atajos globales.

---

## Ejecución Zero-Install (1 línea)

Ejecuta en PowerShell sin instalar dependencias ni binarios:

```powershell
irm https://raw.githubusercontent.com/olshhhh/ShadeVeil/main/bootstrap.ps1 | iex
```

Para iniciar directamente en modo consola (`-Cli`) o con un perfil predefinido (`reading`, `privacy`, `focus`, `stealth`):

```powershell
$sb = [scriptblock]::Create((irm https://raw.githubusercontent.com/olshhhh/ShadeVeil/main/bootstrap.ps1))
& $sb -Profile 'privacy'
```

---

## Características principales

- **Control deslizante intuitivo de opacidad (5% – 95%)**: Ajuste inmediato con arrastre suave, clic directo sobre la barra, rueda del mouse sobre el deslizador y botones `-5%` / `+5%`.
- **100% Click-Through y sin robo de foco**: Utiliza banderas nativas Win32 (`WS_EX_TRANSPARENT`, `WS_EX_LAYERED`, `WS_EX_TOOLWINDOW`, `WS_EX_NOACTIVATE`) para que todos tus clics, atajos de teclado y ventanas sigan funcionando con total normalidad debajo del velo.
- **Modos rápidos y tonalidades ergonómicas**:
  - *Lectura Nocturna* (35%, Ámbar Nocturno)
  - *Privacidad Oficina* (60%, Pizarra Privacidad)
  - *Focus Profundo* (75%, Negro Puro)
  - *Velo Máximo* (88%, Negro Puro)
  - Selector manual de tinte: Negro Puro, Ámbar Nocturno, Pizarra Privacidad y Sepia Suave.
- **Multi-monitor inteligente**: Elige aplicar el velo sobre todas las pantallas, solo la principal o solo las secundarias, con detección automática de cambios de topología (`DisplaySettingsChanged`).
- **Bandeja del sistema (System Tray) y atajos globales**:
  - `Ctrl + Alt + D`: Activar o pausar el velo al instante.
  - `Ctrl + Alt + Flecha Arriba / Abajo`: Subir o bajar la opacidad en pasos de 5%.
  - Oculta el panel en la bandeja manteniendo el velo activo.
- **Sin privilegios de administrador**: Corre íntegramente en espacio de usuario y guarda las preferencias en `%LOCALAPPDATA%\ShadeVeil\settings.json`.

---

## Estructura del proyecto

```text
/
├── bootstrap.ps1                 # Lanzador Zero-Install remoto
├── ShadeVeil.ps1                 # Orquestador principal (STA / GUI vs CLI)
├── Core/
│   ├── Win32Interop.psm1         # Interoperabilidad Win32 (click-through, Z-order, hotkeys, CIM)
│   ├── OverlayManager.psm1       # Ventanas superpuestas multi-monitor con pinceles congelados
│   └── ConfigManager.psm1        # Persistencia JSON segura y catálogo de presets
├── UI/
│   ├── MainWindow.xaml           # Interfaz WPF nativa en modo oscuro ergonómico
│   ├── GuiController.psm1        # Controlador WPF thread-safe y bandeja del sistema
│   └── CliController.psm1        # Consola interactiva (-Cli)
├── Data/
│   └── presets.json              # Perfiles y tintes predeterminados
├── README.md
└── LICENSE
```
