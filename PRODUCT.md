# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

<!-- Aplicación de escritorio Windows (WPF dentro de PowerShell 5.1). No es web. -->

## Stack

Un solo archivo `WinTurbo.ps1` (Windows PowerShell 5.1 + WPF/XAML embebido). Sin dependencias externas, sin módulos ni recursos aparte. La interfaz gráfica se abre por defecto. `-Console` abre el menú de texto, y `-Preset`, `-ConfigFile`, `-Report`, `-Undo`, `-DisableUpdates` y `-EnableUpdates` siguen funcionando sin ventana.

## Users

Técnico que da soporte a varios PCs (clientes, familia, oficina). Llega a equipos distintos, a menudo lentos o recién instalados, y necesita diagnosticar, aplicar un preset y dejarlo todo reversible en poco tiempo. Trabaja con permisos de administrador, frecuentemente con el cliente al lado.

## Product Purpose

Optimizar Windows 10/11 (rendimiento, privacidad, limpieza, reparación, Windows Update y apps) de forma segura y reversible. El éxito significa que el equipo queda más rápido, sin romper funciones, con un respaldo para deshacer cada cambio y una prueba medible del antes y el después.

## Positioning

A diferencia de WinUtil y herramientas similares:
- se adapta al hardware (portátil o sobremesa, SSD o HDD, RAM, máquina virtual);
- guarda el valor ORIGINAL de cada cambio y permite deshacerlo;
- tiene modo simulación;
- verifica el estado real después de aplicar los cambios;
- mide el arranque y el estado del equipo antes y después;
- su bloqueo de Windows Update no se revierte solo (se ejecuta como SYSTEM y una tarea guardiana lo mantiene).

## Operating Context

- Se ejecuta en el equipo del cliente, elevado, a menudo en pantallas de portátil de 1366×768 o 1920×1080 con escalado del 125–150 %.
- Las sesiones son cortas: diagnosticar, aplicar un preset o una selección, limpiar, reiniciar y comprobar el informe.
- Las configuraciones se exportan en JSON para repetirlas en otros equipos.

## Capabilities and Constraints

- Ajustes con tres niveles de riesgo: Seguro, Moderado y Avanzado.
- Presets: Básico, Equilibrado, Gaming y Máximo.
- Bloatware, programas de inicio, limpieza, reparación (DISM → SFC → CHKDSK), DNS con benchmark, Windows Update (modo estable, sin drivers, bloqueo total, bloqueo compatible con Microsoft Store, reactivar), apps con winget, deshacer e informe.
- Las operaciones largas no deben congelar la interfaz.
- No desactiva Defender, el firewall ni UAC.

## Brand Commitments

Nombre: WinTurbo. Idioma de la interfaz: español. Tono directo y honesto sobre riesgos (cada ajuste dice qué hace y qué se pierde).

## Evidence on Hand

No hay métricas publicadas, testimonios ni benchmarks. No se deben inventar. Las métricas que se muestran son las medidas en el propio equipo.

## Product Principles

1. Reversible por defecto: nada se aplica sin respaldo ni posibilidad de deshacer (o se avisa explícitamente cuando no la hay).
2. Verificar, no suponer: mostrar el estado real después de cada acción.
3. Adaptarse al equipo antes que aplicar recetas iguales para todos.
4. Honestidad sobre el riesgo: cada cambio indica su nivel y su contrapartida.
5. Rapidez para el técnico: un preset y una limpieza en pocos clics.

## Accessibility & Inclusion

Debe funcionar con escalado alto de Windows y con teclado (Tab/Enter). Ningún estado puede depender solo del color.
