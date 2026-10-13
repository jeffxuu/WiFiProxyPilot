<div align="center">
  <h1>WiFi Proxy Pilot</h1>
  <h3>Cambio inteligente de proxy según la red Wi-Fi en Windows</h3>
  <p>Una utilidad ligera y moderna para Windows que cambia automáticamente el proxy del sistema según los SSID de Wi-Fi, las direcciones de puerta de enlace y tus reglas.</p>

  ![Windows 11](https://img.shields.io/badge/Windows-11-0078D4)
  ![.NET 8](https://img.shields.io/badge/.NET-8-512BD4)
  ![WPF](https://img.shields.io/badge/UI-WPF-6557E8)
  [![Release](https://img.shields.io/github/v/release/jeffxuu/WiFiProxyPilot)](https://github.com/jeffxuu/WiFiProxyPilot/releases)
  [![Licencia MIT](https://img.shields.io/badge/License-MIT-green)](LICENSE)
  [![GitHub Stars](https://img.shields.io/github/stars/jeffxuu/WiFiProxyPilot?style=flat)](https://github.com/jeffxuu/WiFiProxyPilot/stargazers)
</div>

**[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português (Brasil)](README.pt-BR.md) · [Русский](README.ru.md) · [Tiếng Việt](README.vi.md)**

**Tu Wi-Fi cambia. Tu proxy lo sigue.** Usa un proxy alojado en la puerta de enlace de las redes Wi-Fi habituales y conexión directa en las redes que elijas. Contrólalo desde una interfaz WPF moderna o la bandeja del sistema.

> **v3.2.0-beta.1 está en desarrollo.** Las capturas muestran la aplicación WPF real con datos de red simulados. La aceptación con redes reales, inicio de sesión/suspensión, instalación y desinstalación sigue separada de las pruebas de regresión aisladas. La interfaz actual está en chino simplificado; estas traducciones del README no implican que la interfaz esté traducida. El repositorio sigue siendo Private hasta que su propietario decida publicarlo, por lo que los indicadores externos y Star History pueden no estar disponibles.

## Capturas de pantalla

![Vista general: aplicación WPF real, red simulada](docs/images/dashboard.png)

| Reglas Wi-Fi | Configuración |
| --- | --- |
| ![Vista previa de reglas Wi-Fi](docs/images/rules.png) | ![Vista previa de configuración](docs/images/settings.png) |

![Bandeja del sistema: menú real con datos simulados](docs/images/tray.png)

<details>
<summary>Vista previa del tema oscuro</summary>

![Tema oscuro: diseño anterior de la vista general WPF](docs/images/dashboard-dark.png)

</details>

Todas las imágenes son capturas reales de la aplicación en un entorno aislado, **no pruebas de una conexión de proxy real**. La captura oscura usa un diseño anterior de la vista general. La captura de la bandeja muestra el menú real de la aplicación con los mismos datos simulados.

## Funciones principales

- Reconoce la red Wi-Fi conectada y compara tus reglas con el SSID completo, sin distinguir mayúsculas de minúsculas.
- Obtiene la **puerta de enlace IPv4 predeterminada** de la interfaz Wi-Fi física actual y aplica el puerto que hayas configurado, `7890` por defecto.
- Permite conexión directa en las redes seleccionadas. Las nuevas instalaciones empiezan **sin reglas Wi-Fi incorporadas**; todas las reglas se pueden editar o eliminar.
- Ofrece una interfaz WPF inspirada en macOS, temas claro y oscuro, bandeja del sistema y un monitor de fondo independiente.
- Distingue la gestión automática, el estado del proxy manual de Windows y los diagnósticos opcionales TCP/HTTP. Que el proxy esté activado no demuestra que haya acceso a Internet.
- Guarda la configuración de forma atómica y distingue entre «guardado» y «aplicado por el monitor».
- Conserva la copia del proxy manual original y protege cambios posteriores realizados por ti o por otra aplicación.
- Publica el código con licencia MIT para facilitar su revisión y las contribuciones.

## Descarga e instalación

**[Descargar la última versión publicada: v3.0.0 anterior](https://github.com/jeffxuu/WiFiProxyPilot/releases/latest)** · **[Ver versiones](https://github.com/jeffxuu/WiFiProxyPilot/releases)** · **[Artefactos de compilación v3.2](https://github.com/jeffxuu/WiFiProxyPilot/actions/workflows/build.yml)**

La v3.0.0 publicada contiene la interfaz y el comportamiento anteriores; **no** incluye la interfaz WPF v3.2 de estas capturas. v3.1.0 es una Draft Prerelease. Actualmente no hay una versión v3.2 publicada. Los artefactos de compilación requieren acceso al repositorio y caducan; los borradores no son descargas públicas. Revisa la versión, sus notas y SHA256 antes de instalar. El indicador Release muestra versiones publicadas, no la versión en desarrollo.

La plataforma prevista es **Windows 11 x64**, con Windows PowerShell 5.1, el servicio WLAN y Windows Script Host. El EXE autocontenido no requiere instalar .NET, Python, Node.js ni WebView2 por separado. No se afirma compatibilidad con otras versiones de Windows. Las políticas de una organización pueden limitar la información WLAN, el proxy o las tareas programadas. Las compilaciones actuales no están firmadas; mantén activadas las protecciones de seguridad de Windows.

Descarga el EXE o extrae el ZIP y compara su hash con el archivo `SHA256.txt` incluido:

```powershell
Get-FileHash .\WiFiProxySwitcher.exe -Algorithm SHA256
```

El ejecutable conserva el nombre `WiFiProxySwitcher.exe` por compatibilidad con las actualizaciones. Ejecútalo con tu usuario interactivo normal de Windows. Abrir la ventana v3.2 no activa por sí solo la gestión del proxy. No instales para tu cuenta habitual usando la cuenta de otro administrador.

## Inicio rápido

1. **Descarga** una compilación y comprueba su versión y hash.
2. **Configura** el puerto de un proxy que ya exista en tu puerta de enlace Wi-Fi y añade los nombres de las redes que deben conectarse directamente.
3. **Activa el cambio automático** después de revisar la configuración que gestionará la aplicación.

**La puerta de enlace debe ejecutar realmente un servicio de proxy. WiFi Proxy Pilot no proporciona un servidor proxy ni nodos VPN.** Con un punto de acceso Android, la puerta de enlace IPv4 actual se obtiene automáticamente; configura el puerto de escucha de la aplicación proxy del teléfono y permite conexiones desde el dispositivo Windows conectado. Un punto de acceso por sí solo no es un proxy.

## Cómo funciona

```text
Wi-Fi conectado → Leer una instantánea estable del SSID/interfaz → Comparar reglas
  ├─ Coincide una regla de conexión directa → Desactivar el proxy manual de Windows
  └─ No coincide                          → Obtener la puerta de enlace IPv4 Wi-Fi
                                            → Aplicar puerta de enlace + puerto configurado
```

El monitor verifica la red actual antes de aplicar cambios, para no reutilizar una puerta de enlace antigua tras cambiar de Wi-Fi. Un SSID desconocido, rutas ausentes o interfaces ambiguas conservan la configuración existente, muestran una explicación y provocan un nuevo intento. Una desconexión confirmada desactiva el proxy manual. PAC y la detección automática conservan sus valores y pueden seguir influyendo en el tráfico de las aplicaciones.

## Gestión de reglas Wi-Fi

Abre **Reglas Wi-Fi** para añadir, renombrar, eliminar o añadir la red actual cuando se detecte de forma fiable. Se admiten listas vacías. Se compara el nombre completo con `OrdinalIgnoreCase`, no prefijos ni subcadenas. Se conservan los espacios válidos; los nombres deben ocupar entre 1 y 32 bytes UTF-8 y no contener caracteres de control.

**Guardar y aplicar** comprueba ediciones simultáneas y escribe de forma atómica. «Guardado» confirma la escritura; «Aplicado» exige una señal reciente y compatible del monitor, con la misma revisión y una red estable. Si falta esa confirmación, la aplicación indica que la aplicación en segundo plano está pendiente. Cancelar descarta los cambios sin guardar. Las reglas eliminadas no reaparecen automáticamente.

## Bandeja del sistema y modos de proxy

| Acción | Efecto |
| --- | --- |
| Activar el cambio automático | Volver a observar la red y gestionar el proxy manual según tus reglas |
| Pausar | Detener las escrituras automáticas; conservar el proxy actual |
| Conexión directa | Pausar la gestión y desactivar únicamente el proxy manual de Windows |
| Comprobar ahora | Solicitar una nueva observación de red y una evaluación estable |
| Cerrar la ventana | Ocultarla en la bandeja por defecto; el monitor continúa |
| Salir de la interfaz | Cerrar la interfaz y la bandeja; el monitor independiente continúa |
| Restaurar la configuración original | Detener la gestión y restaurar la copia original con comprobación de conflictos |

La intención de pausa o conexión directa se conserva al reiniciar la interfaz y al iniciar sesión. El inicio del monitor al iniciar sesión y el inicio de la bandeja son ajustes independientes.

**Strict** aplica la regla seleccionada e informa de los fallos de diagnóstico sin desactivar el proxy silenciosamente. **Safe** puede pasar a conexión directa tras el número configurado de fallos consecutivos, de modo que parte del tráfico podría evitar el proxy. Un diagnóstico desconocido no cuenta como recuperación. El diagnóstico TCP solo demuestra que es posible conectar a un puerto; el diagnóstico HTTP hace una petición real a través del proxy hacia la URL HTTP configurada. Ninguno garantiza que funcionen todos los sitios o aplicaciones.

## Recuperación y desinstalación

La copia del proxy manual original está en `state/proxy-before-install.json`, dentro del directorio de instalación. Las actualizaciones la conservan junto con tus reglas; no crean otra copia «original». Los cambios de configuración conservan el archivo válido anterior. Mantén estos archivos locales privados.

Si ya tienes una instalación, abre el EXE candidato y usa **Configuración → Operaciones avanzadas → Reparar instalación / Actualizar**. No desinstales primero ni sustituyas tu configuración por los valores del repositorio. Consulta la [migración de configuración](docs/CONFIG_MIGRATION.md).

Usa **Restaurar configuración original**, **Configuración → Operaciones avanzadas → Desinstalar** o Aplicaciones instaladas de Windows. La restauración y la desinstalación comparan los valores actuales con los originales y con los últimos escritos por esta herramienta. Los cambios externos posteriores producen un conflicto en vez de ser sobrescritos. Forzar la restauración exige una decisión explícita; también puedes desinstalar conservando el proxy actual. Solo se eliminan tareas y registros de inicio propios y archivos de producto verificados, protegiendo archivos ajenos o modificados por el usuario. El modo directo conserva la copia original.

## Seguridad y privacidad

- Los SSID, la configuración del proxy, el estado y los registros se procesan localmente; no se necesita una cuenta en la nube ni un servicio de analítica.
- La aplicación no recopila contraseñas Wi-Fi. Los diagnósticos opcionales se conectan al proxy seleccionado y, en modo HTTP, a la URL que configures.
- Se conserva la copia original del proxy. La instalación y las tareas respetan la identidad del usuario actual y las comprobaciones de permisos.
- La aplicación gestiona el **proxy manual** del usuario actual de Windows; no modifica DNS, rutas ni reglas de cortafuegos.
- Los registros y diagnósticos pueden contener identificadores de red. Revísalos y anonimízalos antes de compartirlos.

Los commits históricos y los materiales de versiones antiguas contienen ejemplos de redes y rutas de máquina. Mantener el repositorio Private no los elimina. La publicación requiere que su propietario revise por separado la [auditoría previa a la publicación](docs/PUBLIC_REPOSITORY_AUDIT.md). Para problemas de seguridad, consulta [SECURITY.md](SECURITY.md).

## Preguntas frecuentes

**¿Cómo cambiar automáticamente el proxy según la red Wi-Fi en Windows 11?** Configura el puerto del proxy de la puerta de enlace, añade los SSID de conexión directa y activa el cambio automático. El monitor evalúa cambios Wi-Fi estables y aplica el proxy manual de Windows para el usuario actual.

**¿Cómo usar la puerta de enlace de un punto de acceso Android como proxy de Windows?** Ejecuta un servicio proxy separado en el teléfono, permite el acceso de los dispositivos conectados y configura su puerto en Pilot. La puerta de enlace se detecta desde la interfaz Wi-Fi actual. Si no es accesible, revisa el servicio y el cortafuegos del teléfono.

**¿WiFi Proxy Pilot incluye una VPN?** No. Gestiona la configuración del proxy manual de Windows; tú proporcionas el servicio. Las aplicaciones con proxy propio o que ignoren los ajustes de Windows pueden comportarse de otra manera.

**¿Por qué el proxy está activado pero no hay Internet?** Puede que la puerta de enlace no tenga un proxy, que el puerto sea incorrecto, que el servicio esté detenido o que falle el destino. Comprueba los diagnósticos TCP/HTTP por separado. Pausa conserva la configuración; Directa desactiva el proxy manual. PAC todavía puede influir en el tráfico.

**¿Cómo evitar el proxy en ciertas redes Wi-Fi?** Añade sus SSID completos a Reglas Wi-Fi y guarda/aplica. Todas las reglas se pueden editar y eliminar; una lista vacía es válida.

**¿Cómo restaurar los ajustes de proxy de Windows?** Elige Restaurar configuración original y revisa cualquier conflicto por cambios externos. Directa solo desactiva el proxy manual; no restaura el servidor original ni la lista de excepciones.

**¿La aplicación sigue funcionando al cerrar la ventana?** Sí. X oculta la ventana en la bandeja por defecto. Salir de la interfaz también deja activo el monitor independiente; usa Pausa o Restaurar para cambiar la gestión de fondo.

**¿Por qué no se puede leer la red actual?** Los permisos WLAN/ubicación, las políticas de la organización, rutas ausentes, un monitor detenido o una señal antigua pueden impedir un estado fiable. La interfaz muestra el motivo y la última observación válida sin presentar datos antiguos como actuales.

**¿Qué se ha probado?** Consulta los [resultados v3.2](docs/TEST_RESULTS_V3_2.md), la [evidencia de rendimiento](docs/PERFORMANCE_V3_2.md) y la [lista de publicación](docs/RELEASE_CHECKLIST.md). Las pruebas aisladas no equivalen a aceptación con redes o instalaciones reales; una meta de rendimiento no es un resultado medido.

## Star History

Si WiFi Proxy Pilot facilita tu trabajo, considera dar una estrella al proyecto.

<a href="https://star-history.com/#jeffxuu/WiFiProxyPilot&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date" />
    <img alt="WiFi Proxy Pilot Star History" src="https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date" />
  </picture>
</a>

El SVG oficial en vivo usa los datos reales de GitHub de este repositorio. Mientras sea Private, el servicio externo no puede mostrar su historial a todo el mundo. Se deberá comprobar de nuevo tras publicarlo; no se inventan estrellas ni crecimiento, ni se sustituye un historial vacío por datos ficticios. Consulta la [guía oficial de inserción](https://www.star-history.com/blog/how-to-use-github-star-history/).

## Contribuciones y hoja de ruta

Los usuarios con acceso al repositorio pueden enviar incidencias y pull requests. Describe la compilación, el comportamiento esperado y observado y la evidencia anonimizada. Consulta [CONTRIBUTING.md](CONTRIBUTING.md) para el proceso de compilación y revisión en Windows. No incluyas configuraciones personales, copias del proxy, credenciales ni registros sin anonimizar.

Trabajo previsto: aceptación real de actualizaciones, inicio de sesión, suspensión y desinstalación; comprobaciones pendientes de accesibilidad y diseño WPF; mejoras de rendimiento al iniciar; y traducción de la interfaz. Son planes, no funciones ya entregadas; las actualizaciones automáticas no están implementadas.

Compila con el SDK de `global.json` y Windows PowerShell:

```powershell
powershell.exe -NoProfile -File tests\Run-Tests.ps1 -ResultPath artifacts\engine-results.json
powershell.exe -NoProfile -File release\Build.ps1
```

La compilación crea un EXE autocontenido `win-x64` sin instalarlo ni cambiar el proxy del equipo. Las identidades existentes `WiFiProxySwitcher` de instalación, registro, mutex y tareas se mantienen por compatibilidad.

## Licencia

El código del proyecto está bajo [MIT](LICENSE). Los materiales de terceros conservan sus propias condiciones; consulta los [avisos de terceros](docs/THIRD_PARTY_NOTICES.md). Se usan las fuentes instaladas en Windows y no se redistribuyen.
