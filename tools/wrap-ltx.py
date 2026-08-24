#!/usr/bin/env python3
"""Dead-simple LaTeX line wrapper.  Only touches lines >80 chars.
Splits at the last space before column 72.  Never touches commands,
environments, or blank lines."""

import sys, re

def wrap_line(line, target):
    """Greedy word-wrap of a single line."""
    words = line.split(' ')
    result = []
    cur = ''
    for w in words:
        test = cur + (' ' if cur else '') + w
        if len(test) <= target:
            cur = test
        else:
            if cur:
                result.append(cur)
            cur = w
    if cur:
        result.append(cur)
    return result

ENVS = {'verbatim','tikzpicture','tabularx','tabular','table','figure',
        'equation','align','align*','enumerate','itemize','description',
        'lstlisting','alltt','quote','center'}

def process_file(filepath, target):
    with open(filepath, 'r') as f:
        lines = f.readlines()

    out = []
    env_depth = []

    for line in lines:
        raw = line.rstrip('\n')
        ls = raw.lstrip()

        # Track environments
        m_begin = re.match(r'\\begin\{(\w+)\*?\}', ls)
        m_end = re.match(r'\\end\{(\w+)\*?\}', ls)
        if m_begin and m_begin.group(1) in ENVS:
            env_depth.append(m_begin.group(1))
            out.append(line)
            continue
        if m_end and env_depth and m_end.group(1) == env_depth[-1]:
            env_depth.pop()
            out.append(line)
            continue
        if env_depth:
            out.append(line)
            continue

        # Never wrap blank lines
        if not raw.strip():
            out.append(line)
            continue

        # Never wrap command lines
        if ls and ls[0] == '\\':
            out.append(line)
            continue

        # Never wrap bibliography/glossary entries
        if ls.startswith('%') or ls.startswith('{') or ls.startswith('}'):
            out.append(line)
            continue

        # Only wrap if too long
        if len(raw) > target + 8:  # only touch lines substantially over target
            wrapped = wrap_line(raw, target)
            for wline in wrapped:
                out.append(wline + '\n')
        else:
            out.append(line)

    with open(filepath, 'w') as f:
        f.writelines(out)

if __name__ == '__main__':
    target = int(sys.argv[1]) if len(sys.argv) > 1 else 72
    for fp in sys.argv[2:]:
        b4 = sum(1 for l in open(fp) if len(l.rstrip('\n')) > 80)
        process_file(fp, target)
        af = sum(1 for l in open(fp) if len(l.rstrip('\n')) > 80)
        print(f"  {fp}: {b4} -> {af}")
