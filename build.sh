#!/bin/sh

TEXINPUTS=".:src:out:src/abstract:src/intro:src/clustering:src/memory:src/io:src/scheduling:${TEXINPUTS}"
BIBINPUTS="~/src/bib:${BIBINPUTS}"
LATEX=lualatex
export LATEX TEXINPUTS BIBINPUTS

rubber --verbose --unsafe -I "${TEXINPUTS}" --pdf src/main.ltx
# ${LATEX} --output-directory=./out main.ltx
# biber --decodecharsset=full --input-directory=./out --output-directory=./out main
# makeindex -t out/main.ilg -o out/main.ind out/main.idx
# ${LATEX} --output-directory=./out main.ltx
# ${LATEX} --output-directory=./out main.ltx
