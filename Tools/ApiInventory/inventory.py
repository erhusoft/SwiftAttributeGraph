"""Names-only inventory of the public API of SwiftUI and SwiftUICore (macOS SDK).

Reads the .swiftinterface files of the installed SDK and writes only symbol names, kinds and approximate member counts:
no declarations, no signatures and no bodies are copied. Usage (from the repository root):

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 -I Tools/ApiInventory/inventory.py docs/inventario-api-swiftui.csv

The member counts are approximate (public member lines found directly inside each type or extension block).
"""
import re, subprocess, collections, csv, sys, os

sdk = subprocess.check_output(['xcrun', '--show-sdk-path'], env={**os.environ, 'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer'}, text=True).strip()
fw = sdk + '/System/Library/Frameworks'
ATTR = r'(?:@[A-Za-z_][A-Za-z0-9_.]*(?:\([^)]*\))?\s+)*'
TYPE = re.compile(r'^\s*' + ATTR + r'(?:public|open)\s+(?:final\s+)?(struct|class|enum|protocol|actor|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)')
EXT = re.compile(r'^\s*' + ATTR + r'(?:public\s+)?extension\s+([A-Za-z_][A-Za-z0-9_.]*)')
MEMBER = re.compile(r'^\s*' + ATTR + r'(?:public|open)\s+(?:static\s+|final\s+|class\s+|mutating\s+|nonmutating\s+|override\s+|convenience\s+|required\s+)*(func|var|let|init|subscript|case|typealias|associatedtype)\b')

def scan(module):
    path = f'{fw}/{module}.framework/Versions/A/Modules/{module}.swiftmodule/arm64e-apple-macos.swiftinterface'
    types = {}; members = collections.Counter(); ext_blocks = collections.Counter()
    stack = []   # entries: ('type'|'ext', name) or ('block', None)
    for line in open(path, encoding='utf-8', errors='replace'):
        s = line.rstrip('\n')
        if s.lstrip().startswith('//'): continue
        top = stack[-1] if stack else None
        scope_name = None
        if top and top[0] in ('type', 'ext'): scope_name = top[1]
        elif not stack:
            m = TYPE.match(s)
            if m and m.group(1) != 'typealias':
                types[m.group(2)] = m.group(1)
        # member counted when directly inside a type or an extension
        if scope_name is not None and MEMBER.match(s): members[scope_name] += 1
        # push/pop braces
        opens = s.count('{') - s.count('}')
        if opens > 0:
            t = None if stack and stack[-1][0] == 'block' else (TYPE.match(s) if not scope_name else None)
            e = EXT.match(s) if (not stack) else None
            if e: stack.append(('ext', e.group(1).split('.')[-1])); ext_blocks[e.group(1).split('.')[-1]] += 1
            elif t and t.group(1) != 'typealias': stack.append(('type', t.group(2)))
            else:
                nested = TYPE.match(s) if scope_name else None
                if nested and nested.group(1) != 'typealias': stack.append(('type', nested.group(2)))
                else: stack.append(('block', None))
            for _ in range(opens - 1): stack.append(('block', None))
        elif opens < 0:
            for _ in range(-opens):
                if stack: stack.pop()
    return types, members, ext_blocks

rows = []
for module in ['SwiftUICore', 'SwiftUI']:
    types, members, ext = scan(module)
    for name, kind in types.items():
        rows.append((module, kind, name, members.get(name, 0), ext.get(name, 0)))
    only_ext = [n for n in ext if n not in types]
    for name in only_ext:
        rows.append((module, 'extension-only', name, members.get(name, 0), ext[name]))

out = sys.argv[1] if len(sys.argv) > 1 else 'inventario-swiftui.csv'
with open(out, 'w', newline='') as f:
    w = csv.writer(f); w.writerow(['module', 'kind', 'name', 'public_members_approx', 'extension_blocks', 'status', 'uses_in_sample_apps'])
    w.writerows([r + ('pendiente', '') for r in sorted(rows)])

by = collections.Counter((r[0], r[1]) for r in rows)
print('Resumen (tipos por módulo y clase):')
for k, v in sorted(by.items()): print(f'  {k[0]:12} {k[1]:15} {v}')
print(f'Total símbolos de primer nivel: {len(rows)}')
first = ['View','ViewBuilder','Text','VStack','HStack','ZStack','Spacer','ScrollView','Button','State','Binding','Environment','ForEach','List','Image','TextField','Toggle','Group','Section','NavigationStack','LazyVStack','Color','Font','Animation']
idx = {r[2]: r for r in rows}
print('\nPrimer corte (miembros públicos aproximados | bloques de extensión):')
for n in first:
    r = idx.get(n)
    print(f'  {n:16}', (f'{r[0]:11} {r[1]:8} miembros≈{r[3]:4} ext={r[4]}' if r else 'no encontrado como tipo de primer nivel'))
print('\n30 tipos con más miembros:')
for r in sorted(rows, key=lambda r: -r[3])[:30]: print(f'  {r[2]:28} {r[0]:11} {r[1]:9} miembros≈{r[3]}')
