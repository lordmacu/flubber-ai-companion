# 🟢 Flubber — mascota slime con IA para macOS

Flubber es una **mascota de escritorio** pixel-art para macOS, hecha 100% en
**Swift + AppKit** (sin archivos de imagen: todo el arte se dibuja por código).
No es solo un adorno: es un **Tamagotchi** que vive en tiempo real **y** un
**agente de IA** capaz de buscar en internet, ver tu pantalla, controlar el
navegador y ejecutar acciones — todo conversando con él en un chat integrado.

![build](https://img.shields.io/badge/build-swiftc-orange) ![macOS](https://img.shields.io/badge/macOS-12%2B-blue)

---

## 🚀 Compilar y ejecutar

```bash
./build.sh        # compila y crea Flubber.app
open Flubber.app  # lánzalo (vive en la barra de menús: icono 🟢)
```

Requiere macOS 12+ y las herramientas de línea de comandos de Xcode (`swiftc`).

---

## 🐹 Tamagotchi (vida real)

Flubber tiene necesidades que **decaen en tiempo real**, incluso con la app
cerrada (guarda su estado y calcula el tiempo transcurrido al abrir).

- **Necesidades:** 🍖 hambre · 😊 felicidad · ⚡ energía · 🫧 limpieza · ✚ salud.
- **Ciclo de vida:** huevo → bebé → niño → adulto. Evoluciona según qué tan bien lo cuides; puede **enfermarse** y, si lo abandonas, **morir** (y renacer como huevo 🥚).
- **Popó:** hace popó cada cierto tiempo; si no limpias, se ensucia y atrae moscas 🪰.
- **Cuidados por gesto (menos botones):**
  - 🎮 **Jugar** → doble clic sobre él.
  - 🛁 **Lavar** → frota el mouse de lado a lado encima.
  - 💤 **Dormir** → automático cuando se queda sin energía (despierta si lo tocas, le hablas o lo cuidas).
  - 🍖 **Alimentar** / 💊 **Medicina** → aparecen como botones **solo cuando hace falta** (hambre / enfermo).
- **HUD:** al pasar el mouse aparecen los botones de cuidado, que se **llenan de color** como indicador del nivel de cada necesidad.
- **Clic derecho** sobre el slime → menú con todas las acciones (alimentar, jugar, bailar, pasear, rodar, chatear…).
- **Avisos del sistema** cuando tiene hambre/sueño/está sucio o enfermo.

## ✨ Animaciones

Camina por la pantalla, **mira al cursor**, salta al hacer clic, suelta
corazones con doble clic, baila 💃, rueda 🤸 (y se marea), persigue el cursor,
bosteza, duerme con "Z", se sonroja, y reacciona con caras según su ánimo
(triste, enfermo, feliz…).

- **Físicas:** no puede salir de la pantalla; si lo arrastras contra un borde y lo sueltas, se **pega a la pared y se escurre** hasta abajo 🫧.
- Mientras "trabaja" en el chat, se anima en su sitio: **se balancea al buscar**, **se gira de espaldas al mirar tu pantalla**, **mueve la boca al hablar** y pulsa al pensar.

## 🎨 Skins

Cambia de color (verde/azul/morado/rosa) o pídele a la IA **"crear un skin"** por
tema (ej. "lava", "galaxia") y recolorea su cuerpo conservando las animaciones.

---

## 🧠 IA (opcional)

Flubber soporta **dos proveedores**, elegibles en la pantalla de configuración:

| Proveedor | Endpoint | Modelos |
|---|---|---|
| **MiniMax** (Token/Coding Plan) | API compatible Anthropic | MiniMax-M2.7 / M2.5 / M2.1 / M2 |
| **Claude** (Anthropic) | Messages API | Opus 4.8 / Sonnet 4.6 / **Haiku 4.5** |

Configúralo en 🟢 → **Configurar IA**: elige proveedor, pulsa **"Abrir consola"**
para sacar tu clave, pégala, elige modelo y **Prueba la conexión**. Solo se
muestran los campos del proveedor activo. La clave se guarda en un archivo local
protegido (`config.json`, permisos `600`).

> Sin clave, Flubber sigue funcionando con **frases enlatadas**.

### 💬 Chat integrado

El botón 💬 (o clic derecho → Hablar) abre un **panel de chat pixel sobre el
slime**, no una ventana aparte:

- **Streaming real** (SSE): el texto aparece **token a token** mientras el modelo lo genera.
- **Markdown renderizado** (negritas, itálicas, `código`, listas).
- **Varias conversaciones**: ☰ lista, ＋ nueva, ✕ cerrar; se guardan en disco.
- **Campo multilínea** con botón de enviar ➤ (crece con el texto). `Enter` envía, `Esc` cierra, rueda para scroll.
- **Copiar** cualquier burbuja (botón ⧉ al pasar el mouse).
- Mientras chateas, el slime **no deambula** ni mueve el diálogo.

### 🤖 Agente con herramientas

Flubber decide solo cuándo usar sus herramientas (function calling):

| Herramienta | Qué hace |
|---|---|
| 🔎 `buscar_web` | Busca en internet (buscador nativo de MiniMax, o DuckDuckGo) |
| 📄 `leer_pagina` | Descarga y resume una URL |
| 🌡️ `clima` / 🕐 `fecha_hora` / ⏰ `recordatorio` | Utilidades |
| 👁️ `ver_pantalla` | Toma una captura y la analiza ("¿qué hay en mi pantalla?"). Puede capturar **solo una app** ("¿qué ves en el navegador?") |
| 🌐 `navegador_url` / `navegador_js` | Lee la pestaña activa y **ejecuta JavaScript** (leer, hacer clic, llenar formularios, navegar) en Safari/Chrome/Brave/Edge/Arc |
| 🎨 `controlar_slime` | Bailar, rodar, color, crear skin por tema |
| 🔗 `abrir` / 💻 `ejecutar_comando` | Abre apps/URLs y ejecuta comandos del sistema |

**Seguridad:** abrir cosas, ejecutar comandos y controlar el navegador **piden
confirmación** mostrando la acción exacta, con opción **"Permitir siempre"**
(menú → "Restablecer permisos" para revertir). Las búsquedas/lecturas corren directo.

**Anti-alucinación:** temperatura baja + el prompt obliga a **verificar con
herramientas** datos reales, citar fuentes y admitir cuando no sabe.

### 👁️ Visión y capturas

- Captura **toda la pantalla** o **una app concreta**.
- La ventana de Flubber **no aparece** en su propia captura ni en **grabaciones / compartir pantalla** (Meet, Chrome, QuickTime).
- La captura se optimiza a **JPEG** antes de enviarla (más liviano).
- La captura se muestra como **miniatura** en el chat (clic para abrir); puedes adjuntarla manualmente con 👁️ y quitarla con la ✕.

---

## 🌐 Idiomas

Sigue el idioma del sistema; cambia entre **Español / English** al vuelo desde el
menú (afecta interfaz, prompts y respuestas).

## 🔐 Permisos de macOS (una vez)

- **Grabación de pantalla** → para `ver_pantalla` (Ajustes → Privacidad → Grabación de pantalla).
- **Automatización** + **"Permitir JavaScript desde Apple Events"** en el navegador (Chrome: Ver → Desarrollador; Safari: Desarrollo) → para controlar el navegador.

> Privacidad: al usar la IA, el texto, capturas o estado se envían al proveedor
> (MiniMax/Anthropic). Los comandos se ejecutan en tu Mac solo tras tu aprobación.

---

## 🛠️ Personalizar

- **Balance del Tamagotchi** (tasas, umbrales, edades): `enum Tuning` en [`Sources/PetStats.swift`](Sources/PetStats.swift).
- **Colores / aspecto:** `enum Pal` en [`Sources/main.swift`](Sources/main.swift).
- **Personalidad / prompts / frases:** [`Sources/Personality.swift`](Sources/Personality.swift).
- **Herramientas del agente:** [`Sources/Agent.swift`](Sources/Agent.swift).
- **Probar rápido el ciclo de vida:** `open --env SLIMEPET_TIMESCALE=200 Flubber.app` (acelera el tiempo).

## 📁 Archivos

```
Sources/
  main.swift          # vista, render, HUD, chat, ventana, AppDelegate
  PetStats.swift      # modelo Tamagotchi (necesidades, ciclo de vida, persistencia)
  Personality.swift   # prompts y frases (bilingüe)
  MiniMax.swift       # backends de IA (MiniMax/Claude), streaming SSE, config
  Agent.swift         # bucle de agente + herramientas + captura de pantalla
  Conversations.swift # almacén de conversaciones
  Loc.swift           # idioma (ES/EN)
build.sh              # compila y empaqueta Flubber.app
```

Datos del usuario: `~/Library/Application Support/SlimePet/`
(`state.json`, `config.json`, `conversations.json`, `shots/`, `slimepet.log`).

## ⚙️ CI

GitHub Actions compila la app en cada push y sube `Flubber.app.zip` como
artefacto ([`.github/workflows/build.yml`](.github/workflows/build.yml)).

---

Hecho con 💚 por Cristian. Flubber te quiere. 🐸
