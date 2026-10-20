#!/usr/bin/env python3
"""Verifica que las cifras de las paginas HTML coinciden con las que produce el codigo (solo biblioteca estandar).

Recalcula todo desde datos/*.csv con sql/consultas.sql (y el analisis en Python, si existe) y lo compara, en CADA pagina .html
de la raiz, con el bloque <script type="application/json" id="datos"> y con el valor crudo de cada tarjeta (atributo data-valor).
Sale con codigo 0 si coinciden y 1 si no. El texto ya formateado de las tarjetas (por ejemplo "985") no se vuelve a leer.

Uso:  python python/verificar.py
"""
import json
import re
import sys
from pathlib import Path

AQUI = Path(__file__).resolve().parent
RAIZ = AQUI.parent
sys.path.insert(0, str(AQUI))

import calcular  # noqa: E402


def extraer_bloque(html, nombre):
    m = re.search(r'<script type="application/json" id="datos">(.*?)</script>', html, re.S)
    if not m:
        raise ValueError(f'{nombre} no trae el bloque <script type="application/json" id="datos">')
    return json.loads(m.group(1))


def paginas_html():
    paginas = sorted(RAIZ.glob("*.html"))
    if not paginas:
        raise ValueError("no hay paginas .html en la raiz del paquete")
    return paginas


def tarjetas(html):
    """Las tarjetas con su indicador y su valor crudo: (kpi, valor)."""
    return re.findall(r'<article class="tarjeta"[^>]*?data-kpi="([^"]+)"[^>]*?data-valor="([^"]*)"', html)


def recalcular(config):
    resultados = calcular.calcular(config, RAIZ / "datos", RAIZ / "sql" / "consultas.sql")
    analisis = {}
    if config.get("analisis_python"):
        import analisis as modulo  # noqa: E402
        analisis = modulo.calcular_analisis(config, resultados)
    return resultados, analisis


def diferencias(esperado, publicado):
    return sorted(k for k in set(esperado) | set(publicado) if esperado.get(k) != publicado.get(k))


def mismo_valor(crudo, resultado):
    """El valor crudo de una tarjeta contra el recalculado; una tarjeta sin valor se escribe vacia."""
    if not resultado or "valor" not in resultado:
        return False
    esperado = resultado["valor"]
    if esperado is None:
        return crudo == ""
    try:
        return abs(float(crudo) - float(esperado)) <= 1e-9 * max(1.0, abs(float(esperado)))
    except ValueError:
        return False


def revisar_pagina(html, nombre, resultados, analisis):
    bloque = extraer_bloque(html, nombre)
    malos = [k for k in diferencias(resultados, bloque.get("resultados", {}))]
    malos += [f"{k} (analisis)" for k in diferencias(analisis, bloque.get("analisis", {}))]
    malos += [f"{kpi} (tarjeta)" for kpi, crudo in tarjetas(html) if not mismo_valor(crudo, resultados.get(kpi))]
    return malos


def main():
    try:
        config = calcular.leer_config()
        resultados, analisis = recalcular(config)
        paginas = paginas_html()
        malos = []
        for pagina in paginas:
            en_pagina = revisar_pagina(pagina.read_text(encoding="utf-8"), pagina.name, resultados, analisis)
            malos += en_pagina if len(paginas) == 1 else [f"{pagina.name}: {k}" for k in en_pagina]
    except Exception as e:  # noqa: BLE001 - cualquier fallo de lectura o calculo es "no verificado"
        print(f"NO VERIFICADO: {e}")
        sys.exit(1)
    if malos:
        print("NO VERIFICADO: las cifras del HTML no coinciden con las recalculadas en: " + ", ".join(malos))
        sys.exit(1)
    cifras = len(resultados) + len(analisis)
    if len(paginas) == 1:
        print(f"VERIFICADO: las {cifras} cifras del HTML coinciden con las recalculadas desde los datos")
    else:
        nombres = ", ".join(p.name for p in paginas)
        print(f"VERIFICADO: las {cifras} cifras de las {len(paginas)} paginas HTML ({nombres}) coinciden con las recalculadas desde los datos")


if __name__ == "__main__":
    main()
