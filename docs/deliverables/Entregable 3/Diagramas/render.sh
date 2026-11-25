#!/bin/sh
# Uso: sh render.sh <archivo.puml>  -> genera .png y .svg con Kroki
f="$1"; b="${f%.puml}"
curl -s -X POST https://kroki.io/plantuml/png -H "Content-Type: text/plain" --data-binary "@$f" -o "$b.png"
curl -s -X POST https://kroki.io/plantuml/svg -H "Content-Type: text/plain" --data-binary "@$f" -o "$b.svg"
ls -l "$b.png" "$b.svg" | awk '{print $5, $9}'
file "$b.png" | cut -c1-80
