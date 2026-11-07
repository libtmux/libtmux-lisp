"""Extract trusted pinned tmux schema; reject unrecognized C declarations.

The host C preprocessor expands upstream hook/string macros. A restricted
initializer reader extracts the schema. A separately compiled C view checks
all extracted fields. Source defaults are deliberately outside this schema.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1] / "build/options-catalog"
FILES = ('options-table.c', 'tmux.h', 'options.c', 'cmd-show-options.c',
         'cmd-set-option.c', 'key-string.c', 'colour.c')
FIELDS = {'name', 'alternative_name', 'type', 'scope', 'flags', 'minimum',
          'maximum', 'choices', 'default_str', 'default_num', 'default_arr',
          'separator', 'pattern', 'text', 'unit'}
DEFAULT_FIELDS = {'default_str', 'default_num', 'default_arr'}
TYPES = ['STRING', 'NUMBER', 'KEY', 'COLOUR', 'FLAG', 'CHOICE', 'COMMAND']
SCOPES = {'OPTIONS_TABLE_SERVER': 'server', 'OPTIONS_TABLE_SESSION': 'session',
          'OPTIONS_TABLE_WINDOW': 'window', 'OPTIONS_TABLE_PANE': 'pane'}
FLAGS = {'OPTIONS_TABLE_IS_ARRAY': 'array', 'OPTIONS_TABLE_IS_HOOK': 'hook',
         'OPTIONS_TABLE_IS_STYLE': 'style', 'OPTIONS_TABLE_IS_COLOUR': 'colour'}
REPRESENTATIONS = {'string': 'string', 'number': 'integer', 'key': 'tmux-key-string',
                   'colour': 'tmux-colour-string', 'flag': 'boolean',
                   'choice': 'choice-string', 'command': 'tmux-command-source'}

class Unsupported(ValueError):
    pass

def require(ok, message):
    if not ok:
        raise Unsupported(message)

TOKEN = re.compile(r'''\s+|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[A-Za-z_][A-Za-z_0-9]*|0[xX][0-9a-fA-F]+[uUlL]*|[0-9]+[uUlL]*|<<|>>|[{}\[\]().,;=|+*\-]''', re.S)

def lex(text):
    tokens = []
    pos = 0
    while pos < len(text):
        match = TOKEN.match(text, pos)
        require(match is not None, f'unsupported C token at byte {pos}: {text[pos:pos+60]!r}')
        token = match.group()
        if not token.isspace():
            tokens.append(token)
        pos = match.end()
    return tokens

class Reader:
    def __init__(self, tokens):
        self.tokens = tokens
        self.pos = 0

    def peek(self):
        return self.tokens[self.pos] if self.pos < len(self.tokens) else None

    def take(self, expected=None):
        value = self.peek()
        require(value is not None, 'unexpected end of C initializer')
        if expected is not None:
            require(value == expected, f'expected {expected!r}, received {value!r} at token {self.pos}')
        self.pos += 1
        return value

    def expression(self, terminators):
        result = []
        stack = []
        pairs = {')': '(', ']': '[', '}': '{'}
        while self.peek() is not None:
            token = self.peek()
            if not stack and token in terminators:
                break
            self.take()
            if token in ('(', '[', '{'):
                stack.append(token)
            elif token in pairs:
                require(stack and stack.pop() == pairs[token], 'unbalanced C initializer')
            result.append(token)
        require(result and not stack, 'empty or unbalanced C expression')
        return result

def c_string(tokens):
    if tokens == ['NULL']:
        return None
    out = bytearray()
    escapes = {'a': 7, 'b': 8, 'f': 12, 'n': 10, 'r': 13, 't': 9,
               'v': 11, '\\': 92, '"': 34, "'": 39, '?': 63}
    for token in tokens:
        require(token.startswith('"') and token.endswith('"'), f'unsupported C string expression: {tokens}')
        value = token[1:-1]
        i = 0
        while i < len(value):
            c = value[i]
            i += 1
            if c != '\\':
                out.extend(c.encode('utf-8'))
                continue
            require(i < len(value), 'trailing C string escape')
            c = value[i]
            i += 1
            if c in escapes:
                out.append(escapes[c])
            elif c in '01234567':
                digits = c
                while len(digits) < 3 and i < len(value) and value[i] in '01234567':
                    digits += value[i]
                    i += 1
                n = int(digits, 8)
                require(n <= 255, 'C octal escape exceeds one byte')
                out.append(n)
            elif c == 'x':
                start = i
                while i < len(value) and value[i] in '0123456789abcdefABCDEF':
                    i += 1
                require(i > start, 'empty C hex escape')
                n = int(value[start:i], 16)
                require(n <= 255, 'C hex escape exceeds one byte')
                out.append(n)
            else:
                raise Unsupported(f'unsupported C escape: {c!r}')
    require(b'\x00' not in out, 'embedded NUL in schema string')
    return out.decode('utf-8')

def integer(tokens):
    reader = Reader(tokens)
    precedence = {'|': 1, '<<': 2, '>>': 2, '+': 3, '-': 3, '*': 4}
    def parse(minimum=0):
        token = reader.take()
        if token == '(':
            value = parse()
            reader.take(')')
        elif token in ('+', '-'):
            value = parse(5)
            if token == '-': value = -value
        else:
            require(re.fullmatch(r'(?:0[xX][0-9a-fA-F]+|0|[1-9][0-9]*)[uUlL]*', token),
                    f'unsupported integer expression: {tokens}')
            literal = re.sub('[uUlL]+$', '', token)
            value = int(literal, 16 if literal.lower().startswith('0x') else 10)
        while reader.peek() in precedence and precedence[reader.peek()] >= minimum:
            op = reader.take()
            rhs = parse(precedence[op] + 1)
            if op == '+': value += rhs
            elif op == '-': value -= rhs
            elif op == '*': value *= rhs
            elif op == '|': value |= rhs
            elif op == '<<':
                require(0 <= rhs <= 63, 'unbounded C shift')
                value <<= rhs
            else:
                require(0 <= rhs <= 63, 'unbounded C shift')
                value >>= rhs
            require(abs(value) < 2**64, 'integer expression exceeds extraction profile')
        return value
    value = parse()
    require(reader.peek() is None, f'unconsumed integer expression: {tokens}')
    return value

def symbolic_bits(tokens, allowed):
    if not tokens:
        return []
    require(len(tokens) % 2 == 1, f'bad bit expression: {tokens}')
    result = []
    for i, token in enumerate(tokens):
        if i % 2:
            require(token == '|', f'unsupported bit operator: {token}')
        else:
            require(token in allowed, f'unknown schema flag/scope: {token}')
            require(token not in result, f'repeated schema flag/scope: {token}')
            result.append(token)
    return result

def parse_table(text):
    diagnostic_prelude = ('#pragma GCC diagnostic push\n'
                          '#pragma GCC diagnostic ignored "-Wpedantic"\n'
                          '#pragma GCC diagnostic pop\n')
    if text.startswith(diagnostic_prelude):
        text = text[len(diagnostic_prelude):]
    r = Reader(lex(text))
    arrays = {}
    array_declarations = []
    entries = None
    aliases = None
    while r.peek() is not None:
        start = r.pos
        if r.peek() == 'static':
            for token in ('static', 'const', 'char', '*'):
                r.take(token)
            name = r.take()
            require(re.fullmatch('options_table_[a-z_0-9]+', name), f'unknown static table: {name}')
            for token in ('[', ']', '=', '{'): r.take(token)
            values = []
            while r.peek() != '}':
                values.append(c_string(r.expression({',', '}'})))
                if r.peek() == ',': r.take(',')
            r.take('}'); r.take(';')
            require(values and values[-1] is None and None not in values[:-1], f'bad NULL-terminated string table: {name}')
            require(name not in arrays, f'duplicate string table: {name}')
            arrays[name] = values[:-1]
            array_declarations.append(' '.join(r.tokens[start:r.pos]))
            continue
        for token in ('const', 'struct'): r.take(token)
        kind = r.take()
        variable = r.take()
        require((kind, variable) in (('options_table_entry', 'options_table'),
                                    ('options_name_map', 'options_other_names')), f'unsupported declaration: {kind} {variable}')
        for token in ('[', ']', '=', '{'): r.take(token)
        items = []
        while r.peek() != '}':
            r.take('{')
            if kind == 'options_name_map':
                left = c_string(r.expression({','})); r.take(',')
                right = c_string(r.expression({'}'}))
                item = [left, right]
            else:
                item = {}
                while r.peek() != '}':
                    r.take('.')
                    field = r.take()
                    require(field in FIELDS and field not in item, f'unknown/duplicate designated field: {field}')
                    r.take('=')
                    item[field] = r.expression({',', '}'})
                    if r.peek() == ',': r.take(',')
            r.take('}')
            items.append(item)
            if r.peek() == ',': r.take(',')
        r.take('}'); r.take(';')
        if kind == 'options_name_map':
            require(aliases is None and items[-1] == [None, None], 'bad alias sentinel/declaration')
            aliases = items[:-1]
            require(all(a and b for a,b in aliases), 'NULL alias before sentinel')
        else:
            require(entries is None and items[-1] == {'name': ['NULL']}, 'bad option sentinel/declaration')
            entries = items[:-1]
    require(entries is not None and aliases is not None, 'missing top-level table')
    require(len(entries) < 4096, 'too many schema nodes')
    return arrays, array_declarations, entries, aliases

def schema_header(header):
    match = re.search(r'/\* Option table entries\. \*/(.*?)/\* Common command usages\. \*/', header, re.S)
    require(match is not None, 'unsupported tmux.h schema section')
    block = match.group(1)
    enum = re.search(r'enum options_table_type\s*\{([^}]+)\}', block, re.S)
    actual = [x.strip() for x in enum.group(1).split(',') if x.strip()]
    require(actual == ['OPTIONS_TABLE_' + x for x in TYPES], f'unknown type enum: {actual}')
    defines = {}
    for key, value in re.findall(r'^#define\s+(OPTIONS_TABLE_\w+)\s+([^\n]+)$', block, re.M):
        defines[key] = integer(lex(value))
    require(set(defines) <= set(SCOPES) | set(FLAGS) | {'OPTIONS_TABLE_NONE'}, 'unknown schema bit constant')
    require(set(SCOPES) <= set(defines), 'missing schema scopes')
    return block, defines

ORACLE = r'''
#include <stdio.h>
#include <stdlib.h>
static void js(const char *s) {
  if (!s) { fputs("null", stdout); return; }
  putchar('"');
  for (const unsigned char *p=(const unsigned char *)s; *p; p++) {
    if (*p=='"' || *p=='\\') { putchar('\\'); putchar(*p); }
    else if (*p<32) printf("\\u%04x", *p);
    else putchar(*p);
  }
  putchar('"');
}
int main(void) {
  printf("{\"integer_profile\":{\"int_bits\":%zu,\"short_bits\":%zu,\"uint_max\":%u},\"options\":[", sizeof(int)*8, sizeof(short)*8, UINT_MAX);
  size_t count=sizeof(options_table)/sizeof(options_table[0]);
  if (count>4096 || options_table[count-1].name!=NULL) return 4;
  for (size_t i=0; i<count-1; i++) {
    const struct options_table_entry *o=&options_table[i];
    if (i) putchar(',');
    fputs("{\"name\":",stdout); js(o->name);
    printf(",\"type\":%d,\"scope\":%d,\"flags\":%d,\"minimum\":%u,\"maximum\":%u,\"choices\":",o->type,o->scope,o->flags,o->minimum,o->maximum);
    if (!o->choices) fputs("null",stdout);
    else { putchar('['); for (size_t n=0; o->choices[n]; n++) { if(n)putchar(','); js(o->choices[n]); } putchar(']'); }
    fputs(",\"alternative_name\":",stdout); js(o->alternative_name);
    fputs(",\"separator\":",stdout); js(o->separator);
    fputs(",\"pattern\":",stdout); js(o->pattern);
    fputs(",\"text\":",stdout); js(o->text);
    fputs(",\"unit\":",stdout); js(o->unit);
    putchar('}');
  }
  fputs("],\"aliases\":[",stdout);
  for (size_t i=0; options_other_names[i].from; i++) {
    if(i)putchar(','); putchar('['); js(options_other_names[i].from); putchar(','); js(options_other_names[i].to); putchar(']');
  }
  fputs("]}\n",stdout);
  return 0;
}
'''

def line_for_name(source, name):
    direct = re.search(r'(?:\.name\s*=|OPTIONS_TABLE_(?:PANE_HOOK|WINDOW_HOOK|HOOK)\s*\()\s*"' + re.escape(name) + r'"', source)
    if direct is None and name.startswith('after-'):
        direct = re.search(r'OPTIONS_TABLE_AFTER_HOOK\s*\(\s*"' + re.escape(name[6:]) + '"', source)
    require(direct is not None, f'cannot locate source entry: {name}')
    return source.count('\n', 0, direct.start()) + 1

def command(argv, *, input=None):
    started = time.monotonic()
    result = subprocess.run(argv, input=input, capture_output=True, timeout=.9)
    require(result.returncode == 0, f'command failed {argv!r}: {result.stderr.decode(errors="replace")}')
    return result.stdout, round(time.monotonic() - started, 6)

def extract(pin, source, cc):
    version = pin['tmux']
    build = ROOT / 'generated' / version
    build.mkdir(parents=True, exist_ok=True)
    table = source['options-table.c'].decode()
    header = source['tmux.h'].decode()
    section, defines = schema_header(header)
    includes = re.findall(r'^#include[^\n]*$', table, re.M)
    require(includes == ['#include <sys/types.h>', '#include <string.h>', '#include "tmux.h"'], f'unknown include set: {includes}')
    directives = set(re.findall(r'^#(\w+)', table, re.M))
    require(directives == {'include', 'define'}, f'unsupported conditional/source directive: {directives}')
    input_buffer = re.findall(r'^#define\s+INPUT_BUF_DEFAULT_SIZE\s+[^\n]+$', header, re.M)
    require(len(input_buffer) <= 1, 'ambiguous input buffer bound')
    translation = '#include <limits.h>\n' + '\n'.join(input_buffer) + '\n' + re.sub(r'^#include[^\n]*$', '', table, flags=re.M)
    (build / 'preprocess-input.c').write_text(translation)
    preprocessed, preprocess_seconds = command([cc, '-E', '-P', '-std=c11', '-x', 'c', '-'], input=translation.encode())
    (build / 'preprocessed.c').write_bytes(preprocessed)
    arrays, array_decls, entries, aliases = parse_table(preprocessed.decode())
    names = []
    raw = []
    normalized = []
    c_entries = []
    for entry in entries:
        require({'name', 'type', 'scope'} <= set(entry), 'entry missing required fields')
        name = c_string(entry['name'])
        require(name and re.fullmatch('[a-z][a-z0-9-]*', name) and name not in names, f'unknown/duplicate built-in name: {name}')
        names.append(name)
        require(len(entry['type']) == 1 and entry['type'][0] in ['OPTIONS_TABLE_' + x for x in TYPES], f'unknown type: {entry["type"]}')
        type_name = entry['type'][0].removeprefix('OPTIONS_TABLE_').lower()
        scope_names = symbolic_bits(entry['scope'], SCOPES)
        flag_names = symbolic_bits(entry.get('flags', []), FLAGS)
        require(all(x in defines for x in flag_names), 'flag has no pinned header definition')
        minimum = integer(entry.get('minimum', ['0']))
        maximum = integer(entry.get('maximum', ['0']))
        require(0 <= minimum <= maximum <= 2**32-1, f'unsupported bound/profile: {name}')
        if type_name == 'number':
            require({'minimum', 'maximum'} <= set(entry), f'number omits explicit bounds: {name}')
        choice_values = None
        choice_table = None
        if 'choices' in entry:
            require(len(entry['choices']) == 1 and entry['choices'][0] in arrays, f'unknown choice table: {name}')
            choice_table = entry['choices'][0]
            choice_values = arrays[choice_table]
        require((type_name == 'choice') == (choice_values is not None), f'choice/type disagreement: {name}')
        row = {'name': name, 'type': TYPES.index(type_name.upper()),
               'scope': sum(defines[x] for x in scope_names), 'flags': sum(defines[x] for x in flag_names),
               'minimum': minimum, 'maximum': maximum, 'choices': choice_values}
        for field in ('alternative_name', 'separator', 'pattern', 'text', 'unit'):
            row[field] = c_string(entry.get(field, ['NULL']))
        raw.append(row)
        scopes = [SCOPES[x] for x in scope_names]
        native_scopes = []
        for scope in scopes:
            native_scopes.extend({'server': ['server'], 'session': ['global-session', 'session'],
                                  'window': ['global-window', 'window'], 'pane': ['pane']}[scope])
        record = {'name': name, 'declared_type': type_name,
                  'value_representation': REPRESENTATIONS[type_name],
                  'declared_scopes': scopes, 'native_scopes': native_scopes,
                  'flags': [FLAGS[x] for x in flag_names],
                  'array': 'OPTIONS_TABLE_IS_ARRAY' in flag_names,
                  'hook': 'OPTIONS_TABLE_IS_HOOK' in flag_names,
                  'minimum': minimum if type_name == 'number' else None,
                  'maximum': maximum if type_name == 'number' else None,
                  'choices': choice_values, 'choice_table': choice_table,
                  'separator': row['separator'], 'pattern': row['pattern'],
                  'pattern_language': 'fnmatch' if row['pattern'] is not None else None,
                  'unit': row['unit'], 'description': row['text'],
                  'source': {'file': 'options-table.c', 'line': line_for_name(table, name)}}
        require(not record['hook'] or (record['array'] and type_name == 'command'), f'unknown hook representation: {name}')
        normalized.append(record)
        c_entries.append('{ ' + ', '.join('.' + field + ' = ' + ' '.join(value)
                                         for field, value in entry.items() if field not in DEFAULT_FIELDS) + ' }')
    require(all(target in names for _, target in aliases), 'alias target is not a catalog entry')
    alias_c = 'const struct options_name_map options_other_names[] = {' + ','.join(
        '{' + json.dumps(left) + ',' + json.dumps(right) + '}' for left, right in aliases) + ', {NULL,NULL}};'
    oracle_source = '#include <sys/types.h>\n#include <limits.h>\n#include <stddef.h>\n' + section + '\n' + '\n'.join(array_decls) + '\n'
    oracle_source += 'const struct options_table_entry options_table[] = {\n' + ',\n'.join(c_entries) + ',\n{.name=NULL}};\n' + alias_c + '\n' + ORACLE
    (build / 'schema-oracle.c').write_text(oracle_source)
    executable = build / 'schema-oracle'
    _, compile_seconds = command([cc, '-std=gnu11', '-Werror', '-O0', str(build / 'schema-oracle.c'), '-o', str(executable)])
    oracle_bytes, execute_seconds = command([str(executable)])
    executable_hash = hashlib.sha256(executable.read_bytes()).hexdigest()
    executable.unlink()
    (build / 'schema-oracle.json').write_bytes(oracle_bytes)
    oracle = json.loads(oracle_bytes)
    require(oracle['integer_profile'] == {'int_bits': 32, 'short_bits': 16, 'uint_max': 4294967295}, 'unsupported C ABI for numeric bounds')
    require(oracle['options'] == raw and oracle['aliases'] == aliases, 'Python/C schema disagreement')
    show = source['cmd-show-options.c'].decode()
    flags = re.search(r'cmd_show_options_entry.*?\.args = \{ "([^"]+)"', show, re.S).group(1)
    string_keys = 'options_array_correct_key' in source['options.c'].decode()
    capabilities = {'show_options_format': 'F:' in flags,
                    'array_key_kind': 'integer-or-string' if string_keys else 'integer',
                    'array_numeric_key_maximum': 4294967295 if string_keys else 2147483647,
                    'user_options': {'declared_type': 'string', 'native_scopes': ['server', 'global-session', 'session', 'global-window', 'window', 'pane']},
                    'user_event_hooks': 'hooks_add_event(name)' in source['cmd-set-option.c'].decode()}
    version_data = {'version': version, 'commit': pin['commit'], 'integer_profile': oracle['integer_profile'],
                    'capabilities': capabilities, 'count': len(normalized),
                    'type_counts': dict(sorted(Counter(x['declared_type'] for x in normalized).items())),
                    'hook_count': sum(x['hook'] for x in normalized),
                    'array_count': sum(x['array'] for x in normalized),
                    'aliases': [{'from': left, 'to': right} for left, right in aliases],
                    'options': normalized}
    checks = {'version': version, 'result': 'PASS', 'parsed_entries': len(entries),
              'compiled_entries': len(oracle['options']), 'all_schema_fields_equal': True,
              'preprocess_seconds': preprocess_seconds, 'compile_seconds': compile_seconds,
              'execute_seconds': execute_seconds, 'oracle_executable_sha256': executable_hash,
              'oracle_executable_removed': not executable.exists()}
    return version_data, checks

def rejected_construct_checks():
    checks = []
    cases = [
        ('unknown flag', lambda: symbolic_bits(['OPTIONS_TABLE_IS_GUESSED'], FLAGS)),
        ('function call bound', lambda: integer(lex('runtime_bound()'))),
        ('integer conditional', lambda: integer(lex('1 ? 2 : 3'))),
        ('unrecognized string prefix', lambda: c_string(['L', '"wide"'])),
        ('unrecognized C escape', lambda: c_string(['"\\q"'])),
        ('trailing initializer code', lambda: parse_table('int unrelated_function(void) { return 1; }'))]
    for name, test in cases:
        try:
            test()
        except Unsupported as error:
            checks.append({'case': name, 'result': 'PASS', 'diagnostic': str(error)})
        else:
            raise AssertionError('unsupported construct accepted: ' + name)
    return checks

def main():
    global ROOT
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', required=True, type=Path)
    parser.add_argument('--tmux-source', required=True, type=Path)
    parser.add_argument('--cc', default='cc')
    parser.add_argument('--output', type=Path, default=ROOT)
    args = parser.parse_args()
    ROOT = args.output.resolve()
    ROOT.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    catalog_path = args.repo / 'tools/tmux-sources.json'
    pins = [p for p in json.loads(catalog_path.read_text())['cells'] if p['purpose'] == 'supported']
    require(len(pins) == 12, 'unexpected source pin set; review before regeneration')
    compiler, _ = command([args.cc, '--version'])
    manifests = []
    versions = []
    verification = []
    for pin in pins:
        dest = ROOT / 'sources' / pin['tmux']
        dest.mkdir(parents=True, exist_ok=True)
        source = {}
        files = {}
        for name in FILES:
            result, _ = command(['git', '-C', str(args.tmux_source), 'show', pin['commit'] + ':' + name])
            (dest / name).write_bytes(result)
            source[name] = result
            files[name] = {'sha256': hashlib.sha256(result).hexdigest(),
                           'url': f"https://github.com/tmux/tmux/blob/{pin['commit']}/{name}"}
        manifests.append({'version': pin['tmux'], 'commit': pin['commit'], 'files': files})
        version, check = extract(pin, source, args.cc)
        versions.append(version)
        verification.append(check)
    catalog = {'schema': 'libtmux.native-options-catalog/1',
               'status': 'proposed-source-data',
               'defaults': 'Source and runtime default values are intentionally omitted; this schema describes complete built-in discovery and value contracts.',
               'source_catalog_sha256': hashlib.sha256(catalog_path.read_bytes()).hexdigest(),
               'versions': versions}
    encoded = json.dumps(catalog, ensure_ascii=False, indent=2) + '\n'
    (ROOT / 'catalog.json').write_text(encoded)
    deltas = []
    for before, after in zip(versions, versions[1:]):
        left = {x['name']: x for x in before['options']}
        right = {x['name']: x for x in after['options']}
        changes = []
        for name in sorted(left.keys() & right.keys()):
            fields = {key: {'before': left[name][key], 'after': right[name][key]}
                      for key in right[name] if key not in ('source', 'description') and left[name][key] != right[name][key]}
            if fields: changes.append({'name': name, 'fields': fields})
        deltas.append({'from': before['version'], 'to': after['version'],
                       'added': sorted(right.keys() - left.keys()), 'removed': sorted(left.keys() - right.keys()), 'changed': changes})
    (ROOT / 'deltas.json').write_text(json.dumps(deltas, ensure_ascii=False, indent=2) + '\n')
    (ROOT / 'sources.json').write_text(json.dumps({'compiler': compiler.decode().splitlines()[0],
                                                 'source_catalog_sha256': catalog['source_catalog_sha256'],
                                                 'records': manifests}, indent=2) + '\n')
    results = {'result': 'PASS', 'started_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
               'script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
               'catalog_sha256': hashlib.sha256(encoded.encode()).hexdigest(),
               'catalog_bytes': len(encoded.encode()), 'versions': verification,
               'unsupported_constructs': rejected_construct_checks(),
               'probe_interval_seconds': round(time.monotonic() - started, 6)}
    (ROOT / 'extraction-verification.json').write_text(json.dumps(results, indent=2) + '\n')
    print(json.dumps({'result': 'PASS', 'catalog_sha256': results['catalog_sha256'],
                      'counts': {v['version']: v['count'] for v in versions},
                      'probe_interval_seconds': results['probe_interval_seconds']}, indent=2))

if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        ROOT.mkdir(parents=True, exist_ok=True)
        (ROOT / 'last-failure.json').write_text(json.dumps({'result': 'FAIL', 'error': str(error)}, indent=2) + '\n')
        raise
