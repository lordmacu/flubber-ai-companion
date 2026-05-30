using Flubber.Core.AI;

namespace Flubber.Core.Agent;

/// <summary>Catálogo de herramientas (esquema OpenAI). Puerto del bloque `tools` de Agent.swift.</summary>
public static class AgentTools
{
    private static ToolDef Fn(string name, string desc, Dictionary<string, object?> props, string[] required) =>
        new(name, desc, new Dictionary<string, object?>
        {
            ["type"] = "object",
            ["properties"] = props,
            ["required"] = required,
        });

    private static Dictionary<string, object?> Str(string desc) => new() { ["type"] = "string", ["description"] = desc };
    private static Dictionary<string, object?> StrType => new() { ["type"] = "string" };

    public static readonly IReadOnlyList<ToolDef> All = new List<ToolDef>
    {
        Fn("buscar_web", "Busca en internet (DuckDuckGo) y devuelve resultados con título, fragmento y URL.",
            new() { ["query"] = Str("qué buscar") }, new[] { "query" }),
        Fn("leer_pagina", "Descarga una página web y devuelve su texto.",
            new() { ["url"] = Str("URL completa") }, new[] { "url" }),
        Fn("clima", "Consulta el clima actual de un lugar.",
            new() { ["lugar"] = Str("ciudad o lugar") }, new[] { "lugar" }),
        Fn("fecha_hora", "Devuelve la fecha y hora actuales.", new(), Array.Empty<string>()),
        Fn("recordatorio", "Programa un recordatorio (notificación) tras unos segundos.",
            new() { ["texto"] = StrType, ["segundos"] = new Dictionary<string, object?> { ["type"] = "number" } }, new[] { "texto", "segundos" }),
        Fn("controlar_slime", "Controla a la mascota: bailar, rodar, pasear, feliz, dormir, color o skin.",
            new()
            {
                ["accion"] = Str("bailar|rodar|pasear|feliz|dormir|color|skin"),
                ["tema"] = Str("color o tema del skin (opcional)"),
            }, new[] { "accion" }),
        Fn("ver_pantalla", "Toma una captura de la pantalla del usuario y la analiza. Úsala cuando pregunten qué ven, un error en pantalla, etc. Si mencionan una app concreta (el navegador, Code, Figma…), pásala en 'app' para capturar SOLO esa ventana; si no, captura toda la pantalla.",
            new()
            {
                ["pregunta"] = Str("qué quieres saber de la pantalla (opcional)"),
                ["app"] = Str("app/ventana a capturar, ej. 'navegador', 'Chrome', 'Code' (opcional; vacío = toda la pantalla)"),
            }, Array.Empty<string>()),
        Fn("navegador_url", "Devuelve la URL y el título de la pestaña activa del navegador.", new(), Array.Empty<string>()),
        Fn("navegador_js", "Ejecuta JavaScript en la pestaña activa del navegador (Chrome/Edge/Brave) para leer o manipular la página: extraer texto, hacer clic, llenar formularios, navegar (location.href=...), hacer scroll, etc. Devuelve lo que retorne el JS. Pide confirmación.",
            new() { ["codigo"] = Str("código JavaScript para la pestaña activa (ej. document.body.innerText)") }, new[] { "codigo" }),
        Fn("abrir", "Abre una URL en el navegador o una app (pide confirmación al usuario).",
            new() { ["objetivo"] = Str("URL o nombre de app") }, new[] { "objetivo" }),
        Fn("ejecutar_comando", "Ejecuta un comando de shell en el equipo (pide confirmación al usuario).",
            new() { ["comando"] = Str("comando de PowerShell/cmd") }, new[] { "comando" }),
    };
}
