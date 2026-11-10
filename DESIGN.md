---
name: WinTurbo
description: Optimizador reversible de Windows 10/11 para técnicos, en una ventana WPF de un solo archivo.
colors:
  azul-senal: "#1F6FEB"
  azul-senal-hover: "#1A5FCC"
  azul-senal-pulsado: "#164FA8"
  azul-foco: "#0B3D91"
  azul-seleccion: "#E8F0FD"
  cinta-verde: "#1A7F37"
  cinta-ambar: "#D29922"
  cinta-roja: "#C42B2B"
  cinta-negra: "#2B2F37"
  cinta-gris: "#6B717C"
  cinta-brillo: "#FFFFFF40"
  texto-peligro: "#B42318"
  lavado-peligro: "#FDECEC"
  texto-aviso: "#9A6700"
  aviso-fondo: "#FFF6DD"
  aviso-trazo: "#D29922"
  aviso-tinta: "#5C4400"
  grafito-riel: "#16181D"
  riel-hover: "#22262D"
  riel-activo: "#2B2F37"
  riel-texto: "#C9CCD3"
  riel-tenue: "#8A8F99"
  riel-trazo: "#6B717C"
  carcasa: "#E9EBEE"
  superficie: "#FFFFFF"
  trazo-superficie: "#D5D8DE"
  divisor: "#ECEEF1"
  lavado-hover: "#F1F3F5"
  lavado-pulsado: "#E4E7EB"
  tinta: "#16181D"
  tinta-secundaria: "#565C67"
  tinta-deshabilitada: "#5B616B"
  tinta-no-aplica: "#6B717C"
  trazo-boton: "#A9AEB8"
  trazo-control: "#7D828C"
  pulgar-scroll: "#9EA4AE"
  registro-fondo: "#1C1F25"
  registro-texto: "#C9CCD3"
  registro-claro: "#F0F3F6"
  registro-estado: "#A9AEB8"
  registro-tenue: "#8A8F99"
  registro-verde: "#56D364"
  registro-amarillo: "#E3B341"
  registro-rojo: "#FF7B72"
  registro-cian: "#79C0FF"
  registro-azul: "#58A6FF"
  registro-ambar: "#D29922"
typography:
  headline:
    fontFamily: "Segoe UI, sans-serif"
    fontSize: "24px"
    fontWeight: 600
  subtitle:
    fontFamily: "Segoe UI, sans-serif"
    fontSize: "13.5px"
    fontWeight: 400
  title:
    fontFamily: "Segoe UI, sans-serif"
    fontSize: "16px"
    fontWeight: 600
  section:
    fontFamily: "Segoe UI, sans-serif"
    fontSize: "15px"
    fontWeight: 600
  category:
    fontFamily: "Segoe UI, sans-serif"
    fontSize: "13px"
    fontWeight: 600
  body:
    fontFamily: "Segoe UI, sans-serif"
    fontSize: "14px"
    fontWeight: 400
  body-strong:
    fontFamily: "Segoe UI, sans-serif"
    fontSize: "14px"
    fontWeight: 600
  body-secondary:
    fontFamily: "Segoe UI, sans-serif"
    fontSize: "13px"
    fontWeight: 400
  meta:
    fontFamily: "Segoe UI, sans-serif"
    fontSize: "12.5px"
    fontWeight: 400
  caption:
    fontFamily: "Segoe UI, sans-serif"
    fontSize: "12px"
    fontWeight: 400
  numeric:
    fontFamily: "Segoe UI, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    fontFeature: "tnum"
  tape-label:
    fontFamily: "Bahnschrift SemiBold Condensed, Bahnschrift, Segoe UI, sans-serif"
    fontSize: "11px"
    fontWeight: 600
    letterSpacing: "0.1em"
  tape-label-panel:
    fontFamily: "Bahnschrift SemiBold Condensed, Bahnschrift, Segoe UI, sans-serif"
    fontSize: "12px"
    fontWeight: 600
    letterSpacing: "0.1em"
  tape-brand:
    fontFamily: "Bahnschrift SemiBold Condensed, Bahnschrift, Segoe UI, sans-serif"
    fontSize: "15px"
    fontWeight: 600
    letterSpacing: "0.1em"
  mono:
    fontFamily: "Consolas, monospace"
    fontSize: "12.5px"
    fontWeight: 400
  icon:
    fontFamily: "Segoe Fluent Icons, Segoe MDL2 Assets"
    fontSize: "16px"
    fontWeight: 400
rounded:
  tape: "2px"
  check: "3px"
  row: "4px"
  control: "6px"
  surface: "8px"
  pill: "10px"
spacing:
  "2": "2px"
  "6": "6px"
  "8": "8px"
  "10": "10px"
  "12": "12px"
  "14": "14px"
  "16": "16px"
  "20": "20px"
  "24": "24px"
  "28": "28px"
  "32": "32px"
components:
  button-primary:
    backgroundColor: "{colors.azul-senal}"
    textColor: "{colors.superficie}"
    typography: "{typography.body-strong}"
    rounded: "{rounded.control}"
    padding: "7px 14px"
  button-primary-hover:
    backgroundColor: "{colors.azul-senal-hover}"
  button-primary-pressed:
    backgroundColor: "{colors.azul-senal-pulsado}"
  button-primary-disabled:
    backgroundColor: "{colors.carcasa}"
    textColor: "{colors.tinta-deshabilitada}"
  button-secondary:
    backgroundColor: "{colors.superficie}"
    textColor: "{colors.tinta}"
    typography: "{typography.body-strong}"
    rounded: "{rounded.control}"
    padding: "7px 14px"
  button-secondary-hover:
    backgroundColor: "{colors.lavado-hover}"
  button-secondary-pressed:
    backgroundColor: "{colors.lavado-pulsado}"
  button-secondary-disabled:
    backgroundColor: "{colors.lavado-hover}"
    textColor: "{colors.tinta-deshabilitada}"
  button-danger:
    backgroundColor: "{colors.superficie}"
    textColor: "{colors.texto-peligro}"
    typography: "{typography.body-strong}"
    rounded: "{rounded.control}"
    padding: "7px 14px"
  button-danger-hover:
    backgroundColor: "{colors.lavado-peligro}"
  surface:
    backgroundColor: "{colors.superficie}"
    rounded: "{rounded.surface}"
    padding: "16px 20px"
  preset-card:
    backgroundColor: "{colors.superficie}"
    rounded: "{rounded.surface}"
    padding: "14px 16px"
  warning-banner:
    backgroundColor: "{colors.aviso-fondo}"
    textColor: "{colors.aviso-tinta}"
    rounded: "{rounded.surface}"
    padding: "12px 16px"
  nav-item:
    textColor: "{colors.riel-texto}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "8px 10px 8px 8px"
  nav-item-hover:
    backgroundColor: "{colors.riel-hover}"
  nav-item-active:
    backgroundColor: "{colors.riel-activo}"
    textColor: "{colors.superficie}"
  sim-switch:
    backgroundColor: "{colors.riel-activo}"
    rounded: "{rounded.pill}"
    width: "38px"
    height: "20px"
  sim-switch-on:
    backgroundColor: "{colors.azul-senal}"
  checkbox:
    backgroundColor: "{colors.superficie}"
    rounded: "{rounded.check}"
    size: "18px"
  checkbox-checked:
    backgroundColor: "{colors.azul-senal}"
  list-row:
    padding: "4px"
    height: "34px"
  list-row-hover:
    backgroundColor: "{colors.lavado-hover}"
    rounded: "{rounded.row}"
  list-row-selected:
    backgroundColor: "{colors.azul-seleccion}"
    rounded: "{rounded.row}"
  tape-green:
    backgroundColor: "{colors.cinta-verde}"
    textColor: "{colors.superficie}"
    typography: "{typography.tape-label}"
    rounded: "{rounded.tape}"
    padding: "2px 7px"
  tape-amber:
    backgroundColor: "{colors.cinta-ambar}"
    textColor: "{colors.tinta}"
    typography: "{typography.tape-label}"
    rounded: "{rounded.tape}"
    padding: "2px 7px"
  tape-red:
    backgroundColor: "{colors.cinta-roja}"
    textColor: "{colors.superficie}"
    typography: "{typography.tape-label}"
    rounded: "{rounded.tape}"
    padding: "2px 7px"
  tape-black:
    backgroundColor: "{colors.cinta-negra}"
    textColor: "{colors.superficie}"
    typography: "{typography.tape-label}"
    rounded: "{rounded.tape}"
    padding: "2px 7px"
  tape-grey:
    backgroundColor: "{colors.cinta-gris}"
    textColor: "{colors.superficie}"
    typography: "{typography.tape-label}"
    rounded: "{rounded.tape}"
    padding: "2px 7px"
  tape-blue:
    backgroundColor: "{colors.azul-senal}"
    textColor: "{colors.superficie}"
    typography: "{typography.tape-label}"
    rounded: "{rounded.tape}"
    padding: "2px 7px"
  tape-brand:
    backgroundColor: "{colors.azul-senal}"
    textColor: "{colors.superficie}"
    typography: "{typography.tape-brand}"
    rounded: "{rounded.tape}"
    padding: "4px 10px"
  mirror-axis:
    backgroundColor: "{colors.tinta}"
    width: "2px"
  log-panel:
    backgroundColor: "{colors.registro-fondo}"
    textColor: "{colors.registro-texto}"
    typography: "{typography.mono}"
    padding: "12px 24px"
    height: "150px"
  log-panel-collapsed:
    height: "64px"
  progress-bar:
    backgroundColor: "{colors.riel-activo}"
    rounded: "{rounded.check}"
    height: "6px"
  progress-indicator:
    backgroundColor: "{colors.azul-senal}"
    rounded: "{rounded.check}"
  scrollbar-thumb:
    backgroundColor: "{colors.pulgar-scroll}"
    rounded: "{rounded.row}"
    width: "10px"
---

# Design System: WinTurbo

## Overview

**Creative North Star: "La cinta rotuladora del técnico"**

WinTurbo se ve como el banco de trabajo de alguien que da soporte a muchos equipos: un riel grafito a la izquierda, una carcasa gris fría y fichas blancas con un trazo de 1 px donde se lee el estado real del PC. Sobre esa base neutra, lo único que lleva color fuerte son las cintas: rectángulos planos de color con letra blanca condensada en mayúsculas, como las que un técnico pega sobre lo que tocó. Una cinta dice qué se aplicó, qué riesgo tiene o en qué estado está algo. Nunca adorna.

La densidad es de herramienta, no de folleto: una línea por ajuste, filas de 32 a 34 px, cifras tabulares alineadas a la derecha y la tabla espejo antes/después separada por un eje grafito de 2 px. El azul es la voz de la acción (el botón principal, la casilla marcada, el foco, la entrada activa del riel) y de la identidad; el verde, el ámbar y el rojo solo hablan de estado y riesgo. Todo es color plano: sin degradados, sin sombras difusas, sin transparencias decorativas. La profundidad sale del tono (riel y registro oscuros, carcasa gris, fichas blancas) y del trazo.

Es una ventana WPF nativa dentro de un único `.ps1`. Las fuentes son solo de sistema (Segoe UI, Bahnschrift, Consolas, Segoe Fluent Icons) porque el producto se distribuye como un solo archivo sin recursos aparte; esa restricción es parte del mundo, no una carencia que haya que disimular. Se rechaza expresamente el panel de tarjetas Fluent con interruptores azules que comparten todos los optimizadores.

**Key Characteristics:**
- Cintas de estado planas con brillo superior de 1 px como única firma de color.
- Riel grafito de 232 px y registro oscuro con Consolas en la parte inferior.
- Fichas blancas con trazo de 1 px y esquinas de 8 px sobre carcasa gris fría; sin sombras.
- Un color por estado, y cada estado siempre escrito con palabras.
- Cifras tabulares en todo lo que se compara o se cuenta.
- Azul reservado para actuar, enfocar y la identidad.

## Colors

Neutros fríos casi sin croma, un azul de acción y cuatro tonos de cinta saturados que significan siempre lo mismo.

### Primary
- **Azul señal** (azul-senal): el botón principal de cada página, la casilla y el radio marcados, el interruptor encendido, la píldora de la entrada activa del riel, la barra de progreso, el borde del preset elegido, el anillo de foco y la cinta de marca. Es el único color que invita a pulsar.
- **Azul señal hover / pulsado** (azul-senal-hover, azul-senal-pulsado): los dos pasos del botón principal bajo el puntero y al pulsar.
- **Azul de foco profundo** (azul-foco): el trazo de 2,5 px de la casilla y el radio cuando tienen el foco de teclado, para que se distinga del estado marcado (que ya es azul).
- **Lavado azul de selección** (azul-seleccion): la fila de ajuste seleccionada cuyo detalle se muestra en el panel lateral.

### Secondary
Los tonos de cinta. Cada uno es un estado o un riesgo, y la letra se elige para superar AA con texto de 11 px.
- **Verde aplicado** (cinta-verde, texto blanco): Seguro, Aplicado, Activo, Más rápido. También es el color del texto de un cambio a mejor en la tabla espejo.
- **Ámbar moderado** (cinta-ambar, texto en tinta grafito): Moderado y Parcial. Es la única cinta con letra oscura, porque el blanco no alcanza contraste sobre ámbar.
- **Rojo avanzado** (cinta-roja, texto blanco): Avanzado, Bloqueado y Sin deshacer.
- **Negro de registro** (cinta-negra, texto blanco): el número correlativo de respaldo (`#0001 · Preset Equilibrado`) y el requisito Reiniciar.
- **Gris inerte** (cinta-gris, texto blanco): Deshecho, Sin datos y No existe; lo que ya no tiene efecto o no se pudo leer.
- **Brillo de cinta** (cinta-brillo, blanco al 25 %): el trazo superior de 1 px que da el relieve de cinta. En XAML se escribe `#40FFFFFF` (ARGB).

### Tertiary
Avisos y peligro en texto, nunca como relleno de botón.
- **Rojo de peligro** (texto-peligro): letra de los botones destructivos; su trazo usa el rojo de cinta y su hover el **lavado de peligro** (lavado-peligro).
- **Ámbar de aviso** (texto-aviso): texto de un cambio a peor en la tabla espejo y de notas como «No se aplicará en este equipo» o la advertencia de Windows Home.
- **Franja de aviso** (aviso-fondo, aviso-trazo, aviso-tinta): la ficha amarilla pálida con trazo ámbar y letra marrón oscura que avisa de que se ejecuta con otra cuenta de administrador.

### Neutral
- **Grafito de riel** (grafito-riel): fondo del riel de navegación.
- **Grafito de registro** (registro-fondo): fondo del registro de actividad inferior, un punto más claro que el riel.
- **Riel hover / activo** (riel-hover, riel-activo): fondos de entrada del riel bajo el puntero y seleccionada; el activo es también la pista de la barra de progreso y del interruptor apagado.
- **Gris de carcasa** (carcasa): fondo de la ventana detrás de las fichas.
- **Blanco de ficha** (superficie) con **trazo de ficha** (trazo-superficie): toda superficie de contenido.
- **Divisor de fila** (divisor): separador inferior de 1 px de cada fila de lista y de la tabla espejo.
- **Lavado hover / pulsado** (lavado-hover, lavado-pulsado): fondo de botón secundario y fila bajo el puntero, y al pulsar.
- **Tinta** (tinta): texto principal; también el eje de la tabla espejo.
- **Tinta secundaria** (tinta-secundaria): subtítulos, etiquetas de la ficha del equipo, descripciones, metadatos y valores de línea base. Es el gris de texto más usado del sistema (6,7:1 sobre blanco).
- **Tinta deshabilitada / no aplica** (tinta-deshabilitada, tinta-no-aplica): botones inactivos y nombres de ajustes que no aplican en este equipo.
- **Trazos de control** (trazo-boton, trazo-control): borde del botón secundario y de la casilla o radio sin marcar.
- **Texto del riel** (riel-texto, riel-tenue): entradas del riel y, en tenue, contadores, versión y la línea de hardware.
- **Texto del registro** (registro-texto, registro-claro, registro-estado, registro-tenue): línea normal, título de la tarea, estado de la tarea y ruta del respaldo.
- **Pulgar de desplazamiento** (pulgar-scroll).

### Registro
Los colores de línea del registro, en tonos claros legibles sobre grafito: **registro-verde** (éxito, `+`), **registro-amarillo** (aviso), **registro-rojo** (error), **registro-cian** (simulación e información), **registro-azul** y **registro-ambar** (equivalentes de DarkCyan y DarkYellow de la consola). Se asignan por nombre de color de consola para que la salida de `Write-Host` conserve su significado en la ventana.

### Named Rules
**La Regla de la Cinta Que Informa.** Una cinta marca un estado o un riesgo, nunca decora: no se usa para títulos, categorías, contadores ni para dar color a una zona vacía. La única excepción es la marca WINTURBO del riel, que es la identidad del producto.

**La Regla de Un Color por Estado.** Cada estado tiene un solo color y cada color de cinta un solo significado: verde Seguro/Aplicado/Activo, ámbar Moderado/Parcial, rojo Avanzado/Bloqueado/Sin deshacer, negro respaldo/Reiniciar, gris Deshecho/Sin datos/No existe, azul Modo simulación. La cinta lleva siempre la palabra; ningún estado depende solo del color.

**La Regla del Azul que Actúa.** El azul señal significa «puedes actuar aquí» o «aquí está el foco». No se usa para riesgo ni para estado salvo la cinta de Modo simulación, que es el estado de la sesión entera.

**La Regla del Color Plano.** Campos de color lisos. Sin degradados, sin sombras difusas y sin variantes de cinta hechas con opacidad.

## Typography

**Display Font:** Segoe UI (fuente de la interfaz de Windows)
**Body Font:** Segoe UI
**Label/Mono Font:** Bahnschrift SemiBold Condensed para las cintas (con Bahnschrift y Segoe UI de reserva); Consolas para el registro; Segoe Fluent Icons (con Segoe MDL2 Assets de reserva) para los iconos.

**Character:** Segoe UI hace el trabajo neutro y legible de una herramienta de Windows; Bahnschrift condensada en mayúsculas espaciadas pone la voz de rotuladora, y Consolas da al registro el aspecto de una consola real. Solo fuentes de sistema: el producto es un único archivo.

### Hierarchy
- **Headline** (SemiBold, 24 px): título de página (`EDUARDO · Windows 11 Home 26H2`, `Ajustes`). Uno por página.
- **Subtitle** (Regular, 13,5 px, tinta secundaria): la línea bajo el título que explica la página o su estado.
- **Title** (SemiBold, 16 px): nombre de preset y título del panel de detalle de un ajuste.
- **Section** (SemiBold, 15 px): encabezados dentro de una ficha o entre bloques (`Equipo`, `Antes · después`, `Presets`).
- **Category** (SemiBold, 13 px, tinta secundaria): grupos dentro de la lista de ajustes (`Privacidad`, `Rendimiento`).
- **Body** (Regular, 14 px): texto de fila, valores y el tamaño base de la ventana. **Body Strong** (SemiBold, 14 px) para el valor «Ahora», los títulos de fila con descripción y los botones.
- **Body Secondary** (Regular, 13 px, tinta secundaria): descripciones de preset, de acción y de ajuste.
- **Meta** (Regular, 12,5 px): textos secundarios de fila, metadatos de preset, estado de la tarea.
- **Caption** (Regular, 12 px): cabeceras de la tabla espejo, contadores del riel, versión, notas al pie.
- **Tape Label** (SemiBold condensada, 11 px, mayúsculas, espacio fino U+200A entre letras): cintas en filas y detalle. 12 px en la ficha del equipo y en el estado de Windows Update; 15 px solo en la marca.
- **Mono** (Consolas, 12,5 px): registro de actividad.
- **Icon** (Segoe Fluent Icons, 16 px): un icono por entrada del riel.

### Named Rules
**La Regla de la Cifra Tabular.** Toda cifra que se compara o se cuenta (tabla espejo, contadores del riel, metadatos de preset, tiempos, resumen por categorías) usa numeración tabular y se alinea a la derecha cuando hay columna.

**La Regla del Espacio Fino.** WPF no tiene espaciado entre letras: la cinta lo consigue intercalando U+200A entre cada carácter en mayúsculas. El nombre accesible de la cinta conserva el texto original sin esos espacios.

## Layout

Ventana de 1360 × 860 px por defecto, recortada al área de trabajo menos 24 px, con mínimo de 960 × 560 px. Unidades en píxeles independientes del dispositivo de WPF, de modo que el escalado del 125–150 % de Windows se respeta solo.

- **Riel fijo** de 232 px a la izquierda, a toda la altura, con margen interior de 12 px (20 px arriba, 14 px abajo): marca arriba, navegación desplazable en el medio, divisor y Modo simulación abajo.
- **Página**: encabezado con márgenes de 32 px laterales, 24 px arriba y 16 px abajo; título y subtítulo a la izquierda, acciones a la derecha separadas 10 px, la principal la última. El cuerpo se desplaza con 32 px laterales y 28 px al pie.
- **Columnas**: separación de 20 px entre fichas lado a lado (Panel en proporción 2:3; Ajustes con columna lateral de 320 px, o 260 px por debajo de 1200 px de ancho). Separación de 12 px entre las cuatro fichas de preset.
- **Ritmo vertical**: 24 px antes de un encabezado de sección, 10 px después; 8 px entre filas de datos de la ficha; 6 px entre cintas en las dos direcciones.
- **Densidad**: una línea por ajuste; filas con casilla de al menos 34 px, filas de la tabla espejo de 32 px. Los nombres largos se ajustan en varias líneas en lugar de truncarse.
- **Registro**: franja inferior bajo el contenido (no bajo el riel), de 64 px en reposo; se despliega a 150 px al empezar una tarea (112 px si la ventana mide menos de 720 px de alto). Márgenes de 24 px laterales y 12 px verticales; columna de tarea de 340 px a la derecha.

## Elevation & Depth

Sistema plano. No hay sombras en ningún elemento. La profundidad se da por tono, del más oscuro al más claro: riel grafito y registro oscuro enmarcan la carcasa gris, y sobre ella las fichas blancas se separan con un trazo de 1 px. El único relieve es el brillo superior de 1 px (blanco al 25 %) de cada cinta, que la hace parecer cinta impresa pegada. El foco del botón es un anillo azul de 2 px separado 3 px del borde, no un resplandor.

### Named Rules
**La Regla del Trazo, No de la Sombra.** Una superficie se distingue con trazo de 1 px y cambio de tono; si algo necesita destacar (el preset elegido), su trazo pasa a 2 px de azul señal.

## Shapes

Esquinas suaves y pequeñas que crecen con el tamaño del objeto: 2 px en la cinta (casi recta, como cinta cortada), 3 px en la casilla y la barra de progreso, 4 px en el pulgar de desplazamiento y en la fila de ajuste seleccionable, 6 px en botones y entradas del riel, 8 px en fichas y en el anillo de foco. El interruptor y su perilla son las únicas formas redondas completas (10 px de radio), junto con el radio. Los trazos son siempre de 1 px salvo la casilla y el radio (1,5 px), el foco (2 px en botón, 2,5 px en casilla y radio), el preset elegido (2 px) y el eje espejo (2 px).

## Components

### Buttons
Botones sobrios de herramienta: rectángulos de 6 px de radio con letra SemiBold de 14 px y relleno de 7 × 14 px.
- **Shape:** esquinas suaves (6 px).
- **Primary:** azul señal con letra blanca; uno por página y siempre el último del grupo de acciones (`Optimizar · Equilibrado`, `Aplicar selección`).
- **Hover / Focus:** el primario oscurece un paso al pasar y otro al pulsar; el secundario pasa a lavado hover y luego a lavado pulsado. El foco de teclado dibuja un anillo azul de 2 px a 3 px del borde con radio 8 px.
- **Secondary:** blanco con trazo gris de 1 px y letra en tinta. Es el botón por defecto.
- **Danger:** blanco con letra roja de peligro y trazo rojo de cinta; al pasar, lavado de peligro. Nunca relleno rojo.
- **Disabled:** el primario pasa a gris de carcasa con letra deshabilitada y trazo de ficha; el secundario a lavado hover.

### Cards / Containers
- **Corner Style:** 8 px.
- **Background:** blanco de ficha sobre gris de carcasa.
- **Shadow Strategy:** ninguna (ver Elevation & Depth).
- **Border:** 1 px en trazo de ficha.
- **Internal Padding:** 16 × 20 px por defecto; 14 × 16 px en fichas de preset; 6 px en la ficha que contiene la lista de ajustes; 12 × 16 px en la franja de aviso.
- **Preset elegido:** trazo de 2 px en azul señal con el relleno reducido 1 px para no mover el contenido. Las fichas de preset se eligen con clic, Intro o Espacio.

### Inputs / Fields
- **Casilla:** cuadrado de 18 px, radio 3 px, trazo de 1,5 px en trazo de control sobre blanco; al pasar, trazo en tinta; marcada, relleno y trazo azul señal con una marca blanca de 2,2 px de grosor con extremos redondeados. Etiqueta a 10 px.
- **Radio:** círculo de 18 px con las mismas reglas; marcado, relleno azul con punto blanco de 8 px.
- **Focus:** trazo azul de foco profundo de 2,5 px.
- **Disabled:** opacidad 45 %.

### Navigation
- **Riel:** entradas con radio 6 px, relleno 8 px (10 px a la derecha) y 2 px de separación; icono Segoe Fluent de 16 px en una columna de 28 px, etiqueta en Body y contador tabular de 12 px en riel tenue a la derecha (`15/36`).
- **Estados:** reposo en texto del riel; hover en riel hover; activa en riel activo con letra blanca y una píldora azul de 3 × 16 px en el borde izquierdo; foco de teclado con trazo azul de 1 px.
- **Modo simulación:** el único interruptor de la interfaz, al pie del riel tras un divisor de 1 px. Pista de 38 × 20 px con perilla de 12 px; encendido, pista azul señal y perilla blanca a la derecha. Al activarlo, cada página muestra la cinta azul `MODO SIMULACIÓN · NO SE CAMBIARÁ NADA` bajo el subtítulo y el título de la ventana lo indica.

### Cinta de estado (signature)
El componente que define el sistema. Borde con relleno del color de estado, trazo superior de 1 px en brillo de cinta, radio 2 px y relleno de 2 × 7 px (4 × 10 px en la marca). Texto en mayúsculas Bahnschrift SemiBold Condensed con espacio fino entre letras, en blanco salvo sobre ámbar. Se alinea a la izquierda en flujo (WrapPanel con 6 px entre cintas) y a la derecha en la columna de riesgo de 96 px de la lista de ajustes. Su nombre accesible es el texto original. Usos: la ficha «Aplicado en este equipo» (una cinta por ajuste aplicado, del color de su riesgo, precedida por el número del último respaldo en negro), el estado de cada ajuste y su riesgo en la lista, el estado real de Windows Update y la lista de respaldos de Deshacer.

### Tabla espejo antes · después (signature)
Columnas de métrica (flexible), línea base (110 px, alineada a la derecha, tinta secundaria), eje (2 px en tinta), ahora (110 px, Body Strong) y cambio (80 px, Body Strong alineado a la derecha). 14 px de aire a cada lado del eje. El cambio se escribe con signo y unidad (`−16.9 pts`, `+3.5 GB`) en verde si mejora y en ámbar de aviso si empeora; sin línea base se muestra `—`. Filas de 32 px con divisor de 1 px.

### Filas de lista
Toda lista usa la misma fila: separador inferior de 1 px en divisor, relleno de 4 px, casilla en columna de 34 px, texto principal en Body con texto secundario en Meta debajo y valor tabular en tinta secundaria a la derecha. En Ajustes la fila entera es seleccionable: lavado hover al pasar y lavado azul de selección al elegirla, con radio de 4 px.

### Registro de actividad y progreso
Franja grafito con Consolas de 12,5 px y una columna de tarea: título SemiBold en registro claro (`Sin tareas en curso`, `Terminado · …`), barra de progreso de 6 px (pista riel activo, indicador azul señal, radio 3 px) y estado en Meta. Guarda las últimas 600 líneas y baja sola al final. La barra se oculta cuando no hay tarea.

## Do's and Don'ts

### Do:
- **Do** usar una cinta solo para un estado o un riesgo, con su palabra escrita y el color que le asigna La Regla de Un Color por Estado.
- **Do** escribir las cintas en mayúsculas Bahnschrift SemiBold Condensed con U+200A entre letras, y dejar el texto original como nombre accesible.
- **Do** separar superficies con el trazo de ficha de 1 px y el cambio de tono carcasa → blanco, nunca con sombra.
- **Do** dejar un único botón primario azul por página, el último del grupo de acciones a la derecha del título.
- **Do** usar numeración tabular en toda cifra comparada o contada, alineada a la derecha en columnas.
- **Do** mostrar la duración estimada (`≈ 3 min`) y el número de ajustes junto a cualquier acción que aplique varios cambios.
- **Do** mantener una línea por ajuste con filas de al menos 34 px y dejar que los nombres largos se ajusten en vez de truncarse.

### Don't:
- **Don't** usar una cinta como adorno, título, categoría o contador; la marca WINTURBO del riel es la única cinta de identidad.
- **Don't** construir listas de ajustes como tarjetas con interruptores azules al estilo Fluent: un ajuste es una fila con casilla, y el único interruptor es Modo simulación en el riel.
- **Don't** usar degradados, sombras difusas ni opacidad para crear variantes de color de una cinta.
- **Don't** usar el azul señal para riesgo, ni el verde, el ámbar o el rojo para acciones.
- **Don't** rellenar de rojo un botón destructivo; va en blanco con letra y trazo rojos.
- **Don't** depender solo del color para un estado: la cinta, el signo del cambio o la palabra deben decirlo también.
- **Don't** cargar fuentes, imágenes ni recursos externos: el producto es un único `.ps1` y solo usa fuentes de sistema.
