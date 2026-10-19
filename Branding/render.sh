#!/bin/sh
# Render the brand SVGs into the PNG/PDF files the asset catalog uses.
# Needs: brew install librsvg, and Pillow (scripts/.venv) to drop alpha from the icons.
set -e
cd "$(dirname "$0")"
mkdir -p png pdf
for f in app-icon-light app-icon-dark app-icon-tinted; do rsvg-convert -w 1024 -h 1024 svg/$f.svg -o png/$f.png; done
for f in mark mark-reversed logo logo-reversed; do rsvg-convert -f pdf svg/$f.svg -o pdf/$f.pdf; done
../scripts/.venv/bin/python -I -c "
from PIL import Image
for n in ('app-icon-light', 'app-icon-dark'):
    p = f'png/{n}.png'; Image.open(p).convert('RGB').save(p)"
A=../Kcal/Assets.xcassets
cp png/app-icon-light.png $A/AppIcon.appiconset/AppIcon.png
cp png/app-icon-dark.png $A/AppIcon.appiconset/AppIcon-Dark.png
cp png/app-icon-tinted.png $A/AppIcon.appiconset/AppIcon-Tinted.png
cp pdf/logo.pdf pdf/logo-reversed.pdf $A/Logo.imageset/
cp pdf/logo-reversed.pdf $A/LogoReversed.imageset/
cp pdf/mark.pdf pdf/mark-reversed.pdf $A/LogoMark.imageset/
echo "Rendered."
