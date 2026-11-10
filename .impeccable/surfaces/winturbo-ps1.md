---
version: 1
slug: "winturbo-ps1"
primary_target: "WinTurbo.ps1"
related_targets: []
---

# WinTurbo · interfaz de escritorio (WPF)

Modo: Operate. Ventana WPF dentro de WinTurbo.ps1 (un solo archivo). La abre por defecto un técnico que da soporte a varios PCs y la usa con el cliente al lado.

Tarea: diagnosticar el equipo, aplicar un preset o una selección de ajustes, limpiar, reparar, gestionar Windows Update y deshacer, sin que la interfaz se congele y con el estado real siempre visible.

Momento memorable: las cintas de color en relieve que marcan lo que ya se tocó en el equipo.

Pendiente: no hay cancelación de tareas en curso; solo se puede esperar a que terminen.

## Direction contract

THESIS: Cada cambio queda etiquetado como el técnico rotula un equipo, con una cinta de color pegada sobre lo que tocó. Rechaza el panel de tarjetas Fluent con interruptores azules, igual al de cualquier optimizador.

OWN-WORLD: Barra lateral grafito #16181D; fondo de carcasa gris frío #E9EBEE; superficies blancas con un trazo de 1 px #D5D8DE. Las cintas son rectángulos planos de color con letra blanca en mayúsculas condensadas Bahnschrift, espaciadas, y un brillo superior de 1 px. Azul #1F6FEB para acciones e identidad; verde #2EA043 Seguro/aplicado; ámbar #D29922 Moderado; rojo #DA3633 Avanzado/bloqueado. Registro de actividad oscuro #1C1F25 con Consolas. Campos de color planos: sin degradados ni sombras difusas. Números tabulares. Iconos Segoe Fluent Icons.

STORY: El técnico ve en segundos qué equipo es, cómo estaba y cómo está, elige un preset sabiendo cuánto tarda y qué arriesga, lo aplica sin que la ventana se bloquee y comprueba con las cintas y la tabla espejo que se aplicó.

FIRST VIEWPORT: A la izquierda, una barra lateral de 232 px con la cinta WINTURBO, la navegación de 10 secciones con contadores y el interruptor de simulación abajo. A la derecha, un encabezado con el equipo y el SO, y a su derecha los botones «Guardar informe» y «Optimizar · Equilibrado», este último el principal. Debajo, dos columnas: a la izquierda la ficha del equipo con las cintas de lo aplicado (380 px) y a la derecha la tabla espejo antes/después alrededor de un eje grafito de 2 px. Después, una fila con los 4 presets indicando número de ajustes y duración estimada. Abajo de todo, un registro de 150 px con la barra de progreso y la ruta del respaldo.

FORM: Cinta rotuladora del técnico, posición 6 de 7 en mi lista ordenada. seed:32043c7235c05d8f. Mejoras tomadas de cada rival: cifras tabulares (Datamatics), numeración correlativa de respaldos (Factory), color plano (zoológico), densidad de una línea por ajuste (convención), columnas espejo antes/después (Labanotación) y duración estimada con total (casete).

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
