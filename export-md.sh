#!/bin/sh

# Pass patterns directly to git ls-files
git ls-files '*.bib' '*.ltx' '*.sh' | while IFS= read -r file; do
    # Skip if file was deleted on disk
    [ -f "$file" ] || continue

    # Map file extensions to markdown language tags
    case "$file" in
        *.bib) lang="bibtex" ;;
        *.ltx) lang="latex" ;;
        *.sh)  lang="bash" ;;
        *)     lang="" ;;
    esac

    # Print Markdown header
    printf '### `%s`\n\n' "$file"

    # Print opening triple backtick + language tag
    printf '```%s\n' "$lang"

    # Print file contents
    cat "$file"

    # Print closing triple backticks
    printf '\n```\n\n---\n\n'
done
