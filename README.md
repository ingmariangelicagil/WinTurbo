# WinTurbo: optimizador de Windows 10 y 11

Un solo script de PowerShell que mejora el rendimiento, la privacidad y el mantenimiento de cualquier PC con Windows. Toma lo mejor de **Chris Titus Tech WinUtil** y de otras herramientas parecidas, y corrige sus puntos débiles.

## Cómo usarlo

1. Guarda `WinTurbo.ps1` en el equipo.
2. Clic derecho en Inicio → **Terminal (Administrador)**.
3. Ejecuta:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; & "C:\ruta\WinTurbo.ps1"
```

Si no lo abres como administrador, o lo abres en PowerShell 7 o en PowerShell de 32 bits, el script se vuelve a lanzar solo en Windows PowerShell 5.1 de 64 bits con permisos elevados.

### Versión .exe (un solo archivo)

`dist\WinTurbo.exe` (unos 240 KB) lleva WinTurbo.ps1 dentro. Doble clic y Windows pide permisos de administrador. Admite los mismos parámetros que el script:

```powershell
.\WinTurbo.exe                                  # interfaz gráfica
.\WinTurbo.exe -Preset Equilibrado -Silent       # sin ventana, para varios equipos
.\WinTurbo.exe -DisableUpdates -KeepStore
```

**Cómo funciona por dentro:**
- **Lanzador:** es un pequeño programa en C# que extrae el script a `C:\ProgramData\WinTurbo\App`.
- **Carpeta protegida:** el dueño son los Administradores y solo SYSTEM y Administradores pueden escribir en ella.
- **Integridad:** antes de ejecutarlo comprueba su SHA-256 y luego lo lanza con Windows PowerShell 5.1 de 64 bits.

No se usa PS2EXE porque convierte el script de otra forma y la interfaz dejaría de funcionar: sus tareas en segundo plano necesitan el archivo `.ps1` real.

**Regenerar** después de cambiar WinTurbo.ps1 (usa el compilador de C# que trae Windows, sin descargar nada):

```powershell
.\Build-Exe.ps1
```

### Firma digital

`Build-Exe.ps1` firma **WinTurbo.ps1** (antes de embeberlo) y **WinTurbo.exe** con Authenticode, SHA-256 y sello de tiempo de DigiCert. El sello mantiene la firma válida aunque el certificado caduque. Junto al .exe quedan:
- `WinTurbo-firma.cer`: el certificado público;
- `WinTurbo.exe.sha256`: el hash para comprobar que el archivo no se ha alterado.

**El certificado actual es autofirmado** (`CN=WinTurbo Code Signing`, válido hasta 2031, guardado en tu almacén de usuario):
- **Lo que garantiza:** cualquier cambio en el .exe o el .ps1 rompe la firma, y Windows lo detecta.
- **Lo que no hace:** no quita el aviso de SmartScreen en equipos de clientes, porque Windows no conoce ese certificado.

**Para que tus equipos lo reconozcan como de confianza**, ejecuta esto en cada uno como administrador (solo en equipos tuyos: añade un certificado raíz de confianza):

```powershell
Import-Certificate -FilePath .\WinTurbo-firma.cer -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath .\WinTurbo-firma.cer -CertStoreLocation Cert:\LocalMachine\TrustedPublisher
```

**Para distribuir a clientes sin avisos** hace falta un certificado de firma de código comercial (OV o EV) de una autoridad como Certum, Sectigo o DigiCert. Se compra y requiere verificar tu identidad. Desde 2023 la clave privada se entrega en un token de hardware o en la nube. Cuando lo tengas:

```powershell
.\Build-Exe.ps1 -CertThumbprint <huella del certificado>
```

**Cada cambio en WinTurbo.ps1 invalida su firma:** vuelve a ejecutar `.\Build-Exe.ps1`, que firma y compila de nuevo.

### Interfaz gráfica

Sin parámetros se abre la **ventana de WinTurbo**. Tiene una barra lateral con 10 secciones: Panel, Ajustes, Bloatware, Programas de inicio, Limpieza, Mantenimiento, Red y DNS, Windows Update, Apps y Deshacer. Abajo hay un registro de actividad con barra de progreso.

- **Nunca se congela:** cada acción se ejecuta en segundo plano y su progreso se ve en el registro inferior.
- **Cintas de color:** marcan lo que ya está aplicado en el equipo y el riesgo de cada ajuste (verde seguro, ámbar moderado, rojo avanzado).
- **Antes y después:** el Panel compara la línea base con el estado actual (arranque, RAM, procesos, servicios, apps de inicio, temporales y espacio).
- **Modo simulación:** el interruptor de la barra lateral muestra lo que se haría sin cambiar nada.
- **Una sola ventana a la vez:** si ya está abierta, avisa.
- **Menú de texto:** sigue disponible con `-Console`. Si el script se ejecuta sin archivo (`irm | iex`), se usa automáticamente.

### Modo automático

```powershell
.\WinTurbo.ps1 -Preset Equilibrado            # aplica el preset recomendado (pide confirmación)
.\WinTurbo.ps1 -Preset Gaming -DryRun         # muestra lo que haría sin tocar nada
.\WinTurbo.ps1 -Preset Basico -Silent         # sin preguntas (para varios equipos)
.\WinTurbo.ps1 -ConfigFile .\WinTurbo-config.json -Silent
.\WinTurbo.ps1 -Report                        # informe y comparación con la línea base
.\WinTurbo.ps1 -Undo                          # deshacer
```

## Análisis de WinUtil (ChrisTitusTech/winutil)

| Área | Qué hace WinUtil |
|---|---|
| Arquitectura | Interfaz gráfica WPF, unos 120 archivos `.ps1` que `Compile.ps1` junta en uno solo; configuración en JSON (`tweaks.json`, `applications.json`, `preset.json`, `dns.json`, `feature.json`). |
| Ajustes | 69 entradas: ajustes "Essential" (telemetría, historial de actividad, ConsumerFeatures, WPBT, ubicación, servicios, Delivery Optimization, limpieza, "Finalizar tarea", punto de restauración), ajustes "Advanced" (Edge/OneDrive, IA de Windows, IPv6, Teredo, indexación, apps en segundo plano, efectos visuales, almacenamiento reservado) y preferencias de interfaz. |
| Presets | Minimal (4), Standard (12), Advanced (17) y AppxDefault (18 apps que se quitan). |
| Servicios | Lo que empezó como una lista enorme de servicios en manual se ha quedado en **5**, porque desactivar servicios a lo loco rompía cosas. Es una lección importante. |
| Otros | Instalación de apps con winget o choco, reparación (chkdsk, SFC, DISM), restablecer red y Windows Update, DNS con benchmark, plan Ultimate Performance, O&O ShutUp10, ISO de Windows. |
| Deshacer | Cada ajuste guarda `OriginalValue` en el JSON, es decir, **el valor por defecto de Windows, no el que tenía tu equipo**. Si ya habías cambiado algo, al deshacer no vuelve a tu configuración. |
| Puntos débiles | No distingue portátil de sobremesa ni SSD de HDD. No tiene modo simulación. No mide antes y después. El orden de reparación es CHKDSK → SFC → DISM, y SFC debería ir después de DISM. Los ajustes de usuario (HKCU) se aplican a la cuenta equivocada si elevas con otro administrador. |

### Otras herramientas revisadas y qué se tomó de cada una

| Herramienta | Qué se tomó |
|---|---|
| **Sophia Script** (farag2) | Catálogo modular con funciones reversibles, desactivar tareas programadas de telemetría (CEIP, Appraiser), Sensor de almacenamiento y avisos cuando el administrador no es el usuario de la sesión. |
| **Win11Debloat** (Raphire) | Lista de bloatware por grupos (patrocinadas, Copilot, Xbox…), quitar el aprovisionamiento para que las apps no vuelvan, Bing y Recall desactivados. |
| **Optimizer** (hellzerg) | Gestor de programas de inicio, limpieza por categorías y DNS predefinidos. |
| **privacy.sexy** | Cada cambio con su descripción y su nivel de riesgo, y la capacidad de revertirlo. |
| **O&O ShutUp10++** | Clasificación en "recomendado, con cuidado y avanzado", que aquí se llama Seguro, Moderado y Avanzado. |
| **AtlasOS / ReviOS** | Ajustes para juegos (MMCSS, HAGS, Game DVR, Power Throttling) **solo en los presets que los necesitan**. |
| **Autoruns / Administrador de tareas** | Desactivar el inicio con la clave `StartupApproved`, igual que Windows, sin borrar nada. |

## Qué mejora WinTurbo

1. **Se adapta al hardware.** En portátiles se omiten los planes de máximo rendimiento, la hibernación y Power Throttling para no gastar batería. Con menos de 8 GB de RAM se añaden solos los efectos visuales ligeros y se bloquean las apps en segundo plano.
2. **Deshacer de verdad.** Antes de cada cambio guarda **el valor que tenía tu equipo**: registro, servicios, tareas, DNS, plan de energía y scripts. Lo guarda en `C:\ProgramData\WinTurbo\Respaldos\*.json` y crea además un punto de restauración, aunque Windows solo permita uno cada 24 horas.
3. **Modo simulación** (`-DryRun` o tecla S en el menú): muestra cada clave, servicio y tarea que cambiaría.
4. **Estado visible.** Junto a cada ajuste aparece `(aplicado)` si ya está activo en el equipo.
5. **Mide antes y después.** La primera vez guarda una línea base y luego compara tiempo de arranque real (registro de eventos 100 de Diagnostics-Performance), procesos, servicios, RAM, apps de inicio, temporales y espacio libre.
6. **Reparación en el orden correcto:** DISM → SFC → CHKDSK, y además optimización de unidades (TRIM en SSD, desfragmentar en HDD).
7. **Limpieza segura.** Solo borra temporales con más de 24 horas, para no romper instaladores que estén en marcha.
8. **Servicios con criterio.** Solo se tocan servicios que no rompen nada al quedar en manual. Nunca la cola de impresión, Bluetooth, Wi-Fi ni audio.
9. **Exporta e importa** tu selección en JSON para aplicarla en otros equipos.

## Desactivar Windows Update sin que vuelva a activarse

```powershell
.\WinTurbo.ps1 -DisableUpdates -KeepStore   # bloqueo compatible con Microsoft Store (recomendado)
.\WinTurbo.ps1 -DisableUpdates              # bloqueo total
.\WinTurbo.ps1 -EnableUpdates               # reactivar (también deshace bloqueos de WinUtil)
```

En la interfaz están en la sección **Windows Update**. En el menú de consola, en 9 → opción 8 (con Tienda), 5 (total) y 6 (reactivar).

| Modo | wuauserv (motor de descarga) | Actualizaciones automáticas | Microsoft Store |
|---|---|---|---|
| **Con Tienda** | Manual: solo arranca cuando la Tienda lo pide | Bloqueadas: UsoSvc, Medic, Health Tools y tareas desactivadas | Funciona |
| **Total** | Deshabilitado | Bloqueadas | No descarga (error 0x80070422) |

En el modo con Tienda, la tarea guardiana nunca detiene wuauserv, para no cortar una descarga en curso. La página de Windows Update de Configuración puede mostrar un error: es esperado, porque depende de UsoSvc.

**Por qué el bloqueo de WinUtil se revierte solo** (`Invoke-WPFUpdatesdisable.ps1`):

| # | Fallo | Consecuencia |
|---|---|---|
| 1 | No desactiva **WaaSMedicSvc** (servicio Medic de Windows Update). | El Medic existe solo para "reparar" Windows Update: vuelve a activar wuauserv, UsoSvc, BITS y las tareas. Su propio script de restaurar sí lo toca, el de desactivar no. |
| 2 | Desactiva las tareas de `UpdateOrchestrator` y `WaaSMedic` como administrador, con `-ErrorAction SilentlyContinue`. | Esas tareas solo las puede modificar SYSTEM. Falla con "Acceso denegado", el error queda oculto y la interfaz lo marca como hecho. |
| 3 | Ignora **uhssvc** (Update Health Tools) y **sedsvc / rempl** (Remediation). | Restauran la configuración de Windows Update. |
| 4 | Es de un solo uso. | Una actualización acumulativa o el Medic deshacen el cambio y nada lo vuelve a aplicar. |
| 5 | No comprueba el resultado. | Muestra "hecho" aunque haya fallado. |
| 6 | Se apoya en las políticas `NoAutoUpdate` y `AUOptions`. | **Windows Home las ignora.** |
| 7 | Desactiva BITS y borra SoftwareDistribution. | Rompe descargas de otras apps sin aportar nada al bloqueo. |

**Cómo lo resuelve WinTurbo:**
- El bloqueo se ejecuta **como SYSTEM**: servicios wuauserv, UsoSvc, WaaSMedicSvc, uhssvc y sedsvc, más todas las tareas de WindowsUpdate, UpdateOrchestrator, WaaSMedic, UpdateAssistant y rempl.
- Una **tarea guardiana** (`\WinTurbo\Bloqueo de Windows Update`) vuelve a aplicarlo al arrancar y cada hora.
- **Se verifica el estado real** y se muestra elemento por elemento: BLOQUEADO, PARCIAL o ACTIVO.
- **Defender sigue protegido:** actualiza sus firmas por su canal propio (MMPC), sin Windows Update.
- **Reactivar restaura el estado original** guardado antes del bloqueo y no "reactiva todo". También limpia los bloqueos de WinUtil y de otras herramientas: políticas, servidor WSUS falso, página oculta de Configuración, reglas que niegan permisos a SYSTEM y BITS desactivado.
- **El script que corre como SYSTEM está protegido:** vive en `C:\ProgramData\WinTurbo\Seguro`, donde solo SYSTEM y Administradores pueden escribir.

> Sin Windows Update no llegan parches de seguridad. Reactívalo de vez en cuando (opción 6), instala lo crítico y vuelve a bloquearlo.

## Presets

| Preset | Para quién |
|---|---|
| Básico | Cualquier PC, también de trabajo. Solo privacidad, anuncios y ajustes seguros. |
| **Equilibrado** | Recomendado. Privacidad y rendimiento sin perder funciones. |
| Gaming | Equilibrado más HAGS, prioridad MMCSS, sin aceleración del ratón, plan Ultimate y sin limitación de red. |
| Máximo | Todo lo anterior más indexación desactivada, almacenamiento reservado, efectos visuales al mínimo y Edge limpio. |

## Qué NO hace (a propósito)

- No desactiva Windows Defender, el firewall, UAC ni las actualizaciones de seguridad.
- No toca Spooler, Bluetooth, Wi-Fi, audio ni servicios de red.
- No aplica mitos de rendimiento como vaciar Prefetch, ajustar Nagle, cambiar "LargeSystemCache" o usar "limpiadores de registro".
- No borra archivos de OneDrive al desinstalarlo.

## Pruebas realizadas

Hay **47 escenarios automatizados**. Los que tocarían el sistema real usan simulaciones (mocks), y el registro solo se modifica en claves de prueba de HKCU:

- **Relanzamiento:** combinaciones de parámetros y rutas con espacios.
- **Menú de consola:** selecciones mal escritas.
- **Presets en 4 perfiles de equipo:** portátil Win11, sobremesa Win10 con HDD y 4 GB, máquina virtual y Win10 1809.
- **Registro:** escribir y deshacer con los 6 tipos de valor, sin cambios al repetir un preset y sin escribir nada en simulación.
- **Respaldos:** archivos dañados y numeración correlativa.
- **Script SYSTEM:** los modos Block, BlockStore y Unblock.
- **Estado de Windows Update:** sin permisos y en modo Tienda.
- **DNS:** filtrado de adaptadores virtuales.
- **Interfaz:** se renderizan las 10 secciones a 1360×860 y a tamaño de portátil al 125 % (1093×614).

## Fallos encontrados y corregidos en la depuración

- **PowerShell de 32 bits:** relanzaba en 32 bits y los ajustes se escribían en WOW6432Node, donde Windows no los lee. Ahora se relanza con `Sysnative`.
- **DNS en adaptadores virtuales:** se cambiaba el DNS de "Npcap Loopback Adapter" y de VPN. Ahora se excluyen por nombre.
- **"Limitación de red" siempre como no aplicado:** `0xffffffff` llegaba como 4294967295 y el registro lo devolvía como -1. Ahora se comparan los 32 bits.
- **Estado de Windows Update sin permisos:** decía "bloqueado" aunque no pudiera leer las tareas. Ahora muestra "sin datos".
- **Ajustes ya aplicados:** se reescribían y llenaban el respaldo. Ahora se omiten.
- **Deshacer DNS:** usaba el índice del adaptador, que cambia al reinstalar drivers. Ahora busca por nombre.
- **Rutas con `[` o `]`:** rompían las tareas de la interfaz.
- **Reactivar desde la ventana:** abría Configuración sin preguntar.
- **Tarea guardiana:** la repetición podía no ser indefinida.
- **Registro en disco:** un fallo puntual de escritura lo apagaba para toda la sesión.
- **Varias ventanas abiertas a la vez:** podían cruzar cambios.
- **Modo de lenguaje restringido** (AppLocker/WDAC): ahora se detecta y se avisa.

## Recomendaciones

**Para el técnico, en cada equipo:**
1. **Revisa el Panel antes de tocar nada.** Si dice HDD, menos de 8 GB o menos de 20 GB libres, dilo al cliente: ningún ajuste iguala un SSD o más RAM.
2. **Usa el preset Equilibrado y reinicia.** Vuelve al Panel después: el tiempo de arranque real solo se actualiza tras reiniciar.
3. **Equipos de trabajo o con software corporativo:** usa Básico. Moderado y Avanzado pueden chocar con las políticas de la empresa.
4. **Repite la misma configuración en varios equipos:** usa Ajustes → Exportar en uno y `-ConfigFile ... -Silent` en el resto.
5. **Windows Update:** prefiere *Modo estable* en Pro y el bloqueo *con Tienda* en Home. Reactívalo una vez al mes, instala los parches de seguridad y vuelve a bloquear.
6. **Si algo falla:** usa Deshacer (el respaldo más reciente primero). Si no basta, Abrir Restaurar sistema.

**Para el proyecto, en orden de impacto:**
1. **Firmar el script** con un certificado de firma de código, para no depender de `-ExecutionPolicy Bypass`.
2. **Probarlo como administrador** en una máquina virtual de Windows 10 y otra de 11 antes de usarlo con clientes. Las pruebas de este repositorio no ejecutaron nada como SYSTEM ni como administrador.
3. **Aplicar los ajustes de usuario** también al perfil *Default*, para que las cuentas nuevas los hereden (como hace Sophia Script).
4. **Poder cancelar una tarea en curso** desde la interfaz. Hoy solo se puede esperar o cerrar la ventana; el respaldo se guarda en cada cambio, así que lo aplicado se puede deshacer.
5. **Comprobar la integridad del archivo** (hash SHA-256 publicado) al distribuirlo por USB o por red.

## Recomendaciones de uso

- Usa primero `-DryRun` o el preset **Equilibrado**, reinicia y revisa el **Informe** (opción 11).
- Si algo falla, ve a **Deshacer** (opción 12) y empieza por el respaldo más reciente.
