# ShadeVeil

Utilidad nativa y ultraligera para Windows 10/11 (PowerShell 5.1 y 7+ / WPF) que superpone un **velo de atenuación *click-through*** en pantalla para mejorar la privacidad y el descanso visual, con un control deslizante intuitivo de opacidad (5% – 95%), soporte multi-monitor, bandeja del sistema y atajos globales.

---

## Ejecución Zero-Install (1 línea)

Ejecuta en PowerShell sin instalar dependencias, ejecutables ni librerías externas:

```powershell
irm https://raw.githubusercontent.com/olshhhh/ShadeVeil/main/bootstrap.ps1 | iex
```

Para iniciar con un perfil (`reading`, `privacy`, `focus`, `stealth`), en modo consola (`-Cli`) o ejecutar la verificación de solo lectura (`-Test`):

```powershell
$sb = [scriptblock]::Create((irm https://raw.githubusercontent.com/olshhhh/ShadeVeil/main/bootstrap.ps1))
& $sb -Profile 'privacy'
```

---

## Pensado para principiantes y usuarios avanzados

### Para uso diario simple
- **Control deslizante intuitivo (5% – 95%)**: Arrastra la barra, haz clic en cualquier punto, usa la rueda del mouse o pulsa `-5%` / `+5%`. Incluye una etiqueta descriptiva en tiempo real (*Lectura cómoda*, *Privacidad equilibrada*, etc.) y tope de seguridad al 95% para evitar pantallas totalmente negras.
- **Modos rápidos en 1 clic**: *Lectura Nocturna* (35% ámbar), *Privacidad Oficina* (60% pizarra), *Focus Profundo* (75% negro) y *Velo Máximo* (88% negro).
- **Seguridad y emergencia**: Pulsa `Ctrl + Alt + D` desde cualquier programa (o `Esc` dentro de la ventana) para pausar el velo al instante.
- **Instancia única automática**: Si lo abres dos veces por error, no apila dos velos oscuros; simplemente trae tu panel existente al frente.

### Para usuarios avanzados y PCs antiguos
- **Motor optimizado para hardware modesto**: Pinceles congelados en caché (`Freeze()`), cero sombras o desenfoques costosos (`DropShadowEffect`/`BlurEffect`), guardado diferido en disco (350 ms) para evitar escrituras en cada paso del deslizador y sincronización Z-Order inactiva cuando el usuario no cambia de ventana.
- **100% Click-Through y Per-Monitor DPI**: Banderas Win32 nativas (`WS_EX_TRANSPARENT`, `WS_EX_LAYERED`, `WS_EX_TOOLWINDOW`, `WS_EX_NOACTIVATE`) y `PerMonitorAwareV2` para alineación exacta en monitores con distinto escalado.
- **Opciones avanzadas colapsables**: Color hexadecimal personalizado (`#RRGGBB`), estado en vivo del registro de atajos globales, modo Eco (opcionalmente desactivar protección sobre barra de tareas en PCs muy antiguos) y acceso directo a `%LOCALAPPDATA%\ShadeVeil\settings.json`.
- **Atajos**:
  - `Ctrl + Alt + D`: Activar / pausar velo globalmente.
  - `Ctrl + Alt + ↑ / ↓`: Subir o bajar opacidad en ±5%.
  - Clic izquierdo en el icono de bandeja: Mostrar u ocultar el panel de control.

---

## Verificación automática (solo lectura)

Puedes validar sintaxis AST, integridad JSON/XAML, importación de módulos en `Set-StrictMode -Version Latest` y sincronización del manifiesto ejecutando:

```powershell
.\Tests\Verify-ShadeVeil.ps1
```

---

## Estructura del proyecto

```text
/
├── bootstrap.ps1                 # Lanzador Zero-Install remoto
├── ShadeVeil.ps1                 # Orquestador principal (DPI, STA / GUI vs CLI)
├── Core/
│   ├── Win32Interop.psm1         # Interoperabilidad Win32 (click-through, DPI, Z-order, hotkeys, CIM)
│   ├── OverlayManager.psm1       # Ventanas superpuestas multi-monitor con caché de pinceles
│   └── ConfigManager.psm1        # Persistencia JSON segura y catálogo de presets
├── UI/
│   ├── MainWindow.xaml           # Interfaz WPF ligera, responsiva y sin efectos pesados
│   ├── GuiController.psm1        # Controlador WPF thread-safe, instancia única y bandeja
│   └── CliController.psm1        # Consola interactiva (-Cli)
├── Data/
│   └── presets.json              # Perfiles y tintes predeterminados
├── Tests/
│   └── Verify-ShadeVeil.ps1      # Pruebas automatizadas en modo solo lectura
├── README.md
└── LICENSE
```
