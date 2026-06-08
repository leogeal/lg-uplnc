#!/usr/bin/env python3
"""
uplnc2c -- a UPLNC -> C source-to-source transpiler (bootstrap stage 0).

See ../BOOTSTRAP.md for the overall plan. This tool turns the self-hosting
UPLNC compiler sources (*.e / *.he) into C so that gcc can build a throwaway
"stage 0" compiler, which is then used to self-host the real one.

Design notes
------------
* UPLNC is C-with-different-skin: same expressions, statements and operators,
  but different declaration syntax plus struct *methods*.
* The three declaration contexts differ:
    - struct members : `<type> <name>;`            (type first, no colon)
    - var decls      : `var [extern] <a> : <b>;`   (either order; see below)
    - function params: `<name> : <type>`           (name first, colon)
  For `var`, the side that *is* the type is the one that starts with `*`, `[`
  or a known type-name; the other side is a comma-separated name list.
* Methods dispatch statically (the `func` slots in structs are never assigned
  function pointers). `method S.m(...)` -> `S_m(S* this, ...)`; inside a method
  body a bare field reference is an implicit `this->field`.
* UPLNC calls functions K&R-style (callees are invoked with extra/:mismatched
  args). We therefore emit *old-style* C definitions so the C compiler does not
  enforce prototypes -- faithfully reproducing UPLNC's untyped calls.
* Preprocessor directives (`#define`, `#include`) share C syntax and are passed
  through verbatim (with `.he` include targets rewritten to `.h`).
"""

import sys

# ---------------------------------------------------------------------------
# Lexer
# ---------------------------------------------------------------------------

KEYWORDS = {
    'var', 'func', 'method', 'struct', 'extern',
    'if', 'else', 'while', 'for', 'do', 'return', 'break', 'continue', 'sizeof',
}

# longest-match-first list of multi-char operators
MULTI_OPS = [
    '<<=', '>>=',
    '->', '++', '--', '<<', '>>', '<=', '>=', '==', '!=', '&&', '||',
    '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=',
]
SINGLE_OPS = set('+-*/%&|^~!<>=?:;,.()[]{}')


class Tok:
    __slots__ = ('kind', 'val', 'line')

    def __init__(self, kind, val, line):
        self.kind = kind   # 'id','kw','num','char','str','op','directive','eof'
        self.val = val
        self.line = line

    def __repr__(self):
        return f'Tok({self.kind},{self.val!r})'


def lex(src):
    toks = []
    i, n = 0, len(src)
    line = 1
    at_line_start = True  # only whitespace seen since last newline
    while i < n:
        c = src[i]
        if c == '\n':
            line += 1
            i += 1
            at_line_start = True
            continue
        if c in ' \t\r':
            i += 1
            continue
        # comments
        if c == '/' and i + 1 < n and src[i + 1] == '*':
            i += 2
            while i + 1 < n and not (src[i] == '*' and src[i + 1] == '/'):
                if src[i] == '\n':
                    line += 1
                i += 1
            i += 2
            continue
        if c == '/' and i + 1 < n and src[i + 1] == '/':
            while i < n and src[i] != '\n':
                i += 1
            continue
        # preprocessor directive: '#' at start of line -> whole line, verbatim
        if c == '#' and at_line_start:
            j = i
            while j < n and src[j] != '\n':
                j += 1
            toks.append(Tok('directive', src[i:j].rstrip(), line))
            i = j
            continue
        at_line_start = False
        # identifier / keyword
        if c.isalpha() or c == '_':
            j = i
            while j < n and (src[j].isalnum() or src[j] == '_'):
                j += 1
            word = src[i:j]
            toks.append(Tok('kw' if word in KEYWORDS else 'id', word, line))
            i = j
            continue
        # number (decimal / hex; keep raw text)
        if c.isdigit():
            j = i
            if c == '0' and i + 1 < n and src[i + 1] in 'xX':
                j = i + 2
                while j < n and (src[j].isalnum()):
                    j += 1
            else:
                while j < n and (src[j].isdigit()):
                    j += 1
            toks.append(Tok('num', src[i:j], line))
            i = j
            continue
        # char literal
        if c == "'":
            j = i + 1
            while j < n and src[j] != "'":
                if src[j] == '\\':
                    j += 1
                j += 1
            j += 1
            toks.append(Tok('char', src[i:j], line))
            i = j
            continue
        # string literal
        if c == '"':
            j = i + 1
            while j < n and src[j] != '"':
                if src[j] == '\\':
                    j += 1
                j += 1
            j += 1
            toks.append(Tok('str', src[i:j], line))
            i = j
            continue
        # operators
        for op in MULTI_OPS:
            if src.startswith(op, i):
                toks.append(Tok('op', op, line))
                i += len(op)
                break
        else:
            if c in SINGLE_OPS:
                toks.append(Tok('op', c, line))
                i += 1
            else:
                raise SyntaxError(f'line {line}: unexpected char {c!r}')
    toks.append(Tok('eof', None, line))
    return toks


# ---------------------------------------------------------------------------
# Types  (represented as nested tuples)
#   ('base', name) | ('ptr', inner) | ('arr', size_str, inner)
# ---------------------------------------------------------------------------

def emit_decl(t, name):
    """Build a C declarator: type `t` declaring `name`."""
    if t[0] == 'base':
        sep = ' ' if name else ''
        return f'{t[1]}{sep}{name}'.rstrip()
    if t[0] == 'ptr':
        return emit_decl(t[1], '*' + name)
    if t[0] == 'arr':
        return emit_decl(t[2], f'{name}[{t[1]}]')
    raise ValueError(t)


def emit_type_name(t):
    """A bare type name, e.g. for sizeof()."""
    s = emit_decl(t, '@')
    return s.replace('@', '').rstrip()


def base_of(t):
    """The base type spelling (e.g. 'int', 'char', a struct name)."""
    while t[0] != 'base':
        t = t[-1]
    return t[1]


def declarator(t, name):
    """The declarator part (pointers/arrays + name) without the base type."""
    if t[0] == 'base':
        return name
    if t[0] == 'ptr':
        return declarator(t[1], '*' + name)
    if t[0] == 'arr':
        return declarator(t[2], f'{name}[{t[1]}]')
    raise ValueError(t)


def emit_group_decl(t, names):
    """Declare several names sharing one type: `int *a, *b;`-style."""
    return base_of(t) + ' ' + ', '.join(declarator(t, nm) for nm in names)


# ---------------------------------------------------------------------------
# Parser
# ---------------------------------------------------------------------------

BASE_TYPES = {'int', 'char', 'void', 'long', 'short', 'unsigned'}


class Parser:
    def __init__(self, toks, struct_names):
        self.toks = toks
        self.p = 0
        self.struct_names = struct_names  # set of known struct type names

    # -- token helpers --
    def peek(self, k=0):
        return self.toks[self.p + k]

    def next(self):
        t = self.toks[self.p]
        self.p += 1
        return t

    def at(self, kind, val=None):
        t = self.toks[self.p]
        return t.kind == kind and (val is None or t.val == val)

    def eat(self, kind, val=None):
        t = self.toks[self.p]
        if t.kind != kind or (val is not None and t.val != val):
            raise SyntaxError(
                f'line {t.line}: expected {kind} {val!r}, got {t.kind} {t.val!r}')
        self.p += 1
        return t

    def is_typename(self, tok):
        return tok.kind == 'id' and tok.val in self.struct_names \
            or (tok.kind == 'id' and tok.val in BASE_TYPES)

    # -- types --
    def parse_type(self):
        t = self.peek()
        if t.kind == 'op' and t.val == '*':
            self.next()
            return ('ptr', self.parse_type())
        if t.kind == 'op' and t.val == '[':
            self.next()
            size = self.parse_arraysize()
            self.eat('op', ']')
            return ('arr', size, self.parse_type())
        # base name
        name = self.eat('id').val
        return ('base', name)

    def parse_arraysize(self):
        """Capture tokens up to the matching ']' as a C size expression."""
        parts = []
        depth = 0
        while True:
            t = self.peek()
            if t.kind == 'op' and t.val == '[':
                depth += 1
            elif t.kind == 'op' and t.val == ']':
                if depth == 0:
                    break
                depth -= 1
            parts.append(self.tok_text(t))
            self.next()
        return ''.join(parts)

    @staticmethod
    def tok_text(t):
        return '' if t.val is None else t.val

    # -- top level --
    def parse_unit(self):
        items = []
        while not self.at('eof'):
            items.append(self.parse_toplevel())
        return items

    def parse_toplevel(self):
        t = self.peek()
        if t.kind == 'directive':
            self.next()
            return ('directive', t.val)
        if t.kind == 'kw' and t.val == 'struct':
            return self.parse_struct()
        if t.kind == 'kw' and t.val == 'var':
            return self.parse_var()
        if t.kind == 'kw' and t.val == 'func':
            return self.parse_func()
        if t.kind == 'kw' and t.val == 'method':
            return self.parse_method()
        raise SyntaxError(f'line {t.line}: unexpected top-level {t.kind} {t.val!r}')

    # -- struct --
    def parse_struct(self):
        self.eat('kw', 'struct')
        name = self.eat('id').val
        self.eat('op', '{')
        fields = []   # (type, name)
        methods = []  # method-slot names
        while not self.at('op', '}'):
            if self.at('kw', 'func'):
                self.next()
                mname = self.eat('id').val
                self.eat('op', ';')
                methods.append(mname)
                continue
            ftype = self.parse_type()
            # one or more comma-separated names sharing this type
            names = [self.eat('id').val]
            while self.at('op', ','):
                self.next()
                names.append(self.eat('id').val)
            self.eat('op', ';')
            for nm in names:
                fields.append((ftype, nm))
        self.eat('op', '}')
        self.eat('op', ';')
        return ('struct', name, fields, methods)

    # -- var --
    def parse_var(self):
        self.eat('kw', 'var')
        is_extern = False
        # collect tokens for side1 (up to ':') and side2 (up to ';'),
        # dropping any 'extern' keyword.
        side1 = []
        while not self.at('op', ':'):
            t = self.next()
            if t.kind == 'kw' and t.val == 'extern':
                is_extern = True
            else:
                side1.append(t)
        self.eat('op', ':')
        side2 = []
        while not self.at('op', ';'):
            t = self.next()
            if t.kind == 'kw' and t.val == 'extern':
                is_extern = True
            else:
                side2.append(t)
        self.eat('op', ';')
        # which side is the type?
        if self.side_is_type(side1):
            type_toks, name_toks = side1, side2
        else:
            type_toks, name_toks = side2, side1
        vtype = self.subparse_type(type_toks)
        names = self.names_from(name_toks)
        return ('var', is_extern, vtype, names)

    def side_is_type(self, toks):
        if not toks:
            return False
        t = toks[0]
        if t.kind == 'op' and t.val in ('*', '['):
            return True
        return self.is_typename(t)

    def subparse_type(self, toks):
        sub = Parser(toks + [Tok('eof', None, 0)], self.struct_names)
        return sub.parse_type()

    @staticmethod
    def names_from(toks):
        names = []
        for t in toks:
            if t.kind == 'id':
                names.append(t.val)
            elif t.kind == 'op' and t.val == ',':
                continue
            else:
                raise SyntaxError(f'line {t.line}: bad name token {t.val!r}')
        return names

    # -- func / params --
    def parse_params(self):
        self.eat('op', '(')
        params = []  # (name, type)
        while not self.at('op', ')'):
            params.append(self.parse_one_param())
            if self.at('op', ','):
                self.next()
        self.eat('op', ')')
        return params

    def parse_one_param(self):
        # a param may be `name:type`, `type:name`, or `type name` (no colon).
        # collect its tokens, drop the optional ':' separator, then split.
        toks = []
        while not (self.at('op', ',') or self.at('op', ')')):
            t = self.next()
            if not (t.kind == 'op' and t.val == ':'):
                toks.append(t)
        if self.side_is_type(toks):
            # type leads; the trailing identifier is the name
            sub = Parser(toks + [Tok('eof', None, 0)], self.struct_names)
            ptype = sub.parse_type()
            name = sub.eat('id').val
            return (name, ptype)
        # name leads; the rest is the type
        return (toks[0].val, self.subparse_type(toks[1:]))

    def parse_func(self):
        self.eat('kw', 'func')
        name = self.eat('id').val
        params = self.parse_params()
        if self.at('op', ';'):
            self.next()
            return ('func_proto', name, params)
        body = self.parse_block()
        return ('func', name, params, body)

    def parse_method(self):
        self.eat('kw', 'method')
        sname = self.eat('id').val
        self.eat('op', '.')
        mname = self.eat('id').val
        params = self.parse_params()
        body = self.parse_block()
        return ('method', sname, mname, params, body)

    # -- statements --
    def parse_block(self):
        self.eat('op', '{')
        stmts = []
        while not self.at('op', '}'):
            stmts.append(self.parse_stmt())
        self.eat('op', '}')
        return ('block', stmts)

    def parse_stmt(self):
        t = self.peek()
        if t.kind == 'directive':
            self.next()
            return ('directive', t.val)
        if t.kind == 'op' and t.val == '{':
            return self.parse_block()
        if t.kind == 'op' and t.val == ';':
            self.next()
            return ('empty',)
        if t.kind == 'kw' and t.val == 'var':
            return self.parse_var()  # local decl, same shape
        if t.kind == 'kw' and t.val == 'if':
            self.next()
            self.eat('op', '(')
            cond = self.parse_expr()
            self.eat('op', ')')
            then = self.parse_stmt()
            els = None
            if self.at('kw', 'else'):
                self.next()
                els = self.parse_stmt()
            return ('if', cond, then, els)
        if t.kind == 'kw' and t.val == 'while':
            self.next()
            self.eat('op', '(')
            cond = self.parse_expr()
            self.eat('op', ')')
            return ('while', cond, self.parse_stmt())
        if t.kind == 'kw' and t.val == 'do':
            self.next()
            body = self.parse_stmt()
            self.eat('kw', 'while')
            self.eat('op', '(')
            cond = self.parse_expr()
            self.eat('op', ')')
            self.eat('op', ';')
            return ('do', body, cond)
        if t.kind == 'kw' and t.val == 'for':
            self.next()
            self.eat('op', '(')
            init = None if self.at('op', ';') else self.parse_expr()
            self.eat('op', ';')
            cond = None if self.at('op', ';') else self.parse_expr()
            self.eat('op', ';')
            post = None if self.at('op', ')') else self.parse_expr()
            self.eat('op', ')')
            return ('for', init, cond, post, self.parse_stmt())
        if t.kind == 'kw' and t.val == 'return':
            self.next()
            val = None if self.at('op', ';') else self.parse_expr()
            self.eat('op', ';')
            return ('return', val)
        if t.kind == 'kw' and t.val == 'break':
            self.next()
            self.eat('op', ';')
            return ('break',)
        if t.kind == 'kw' and t.val == 'continue':
            self.next()
            self.eat('op', ';')
            return ('continue',)
        # expression statement
        e = self.parse_expr()
        self.eat('op', ';')
        return ('expr', e)

    # -- expressions (precedence-climbing) --
    def parse_expr(self):
        return self.parse_comma()

    def parse_comma(self):
        e = self.parse_assign()
        if self.at('op', ','):
            items = [e]
            while self.at('op', ','):
                self.next()
                items.append(self.parse_assign())
            return ('comma', items)
        return e

    ASSIGN_OPS = {'=', '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=', '<<=', '>>='}

    def parse_assign(self):
        left = self.parse_cond()
        t = self.peek()
        if t.kind == 'op' and t.val in self.ASSIGN_OPS:
            self.next()
            right = self.parse_assign()
            return ('assign', t.val, left, right)
        return left

    def parse_cond(self):
        c = self.parse_binary(0)
        if self.at('op', '?'):
            self.next()
            a = self.parse_assign()
            self.eat('op', ':')
            b = self.parse_cond()
            return ('cond', c, a, b)
        return c

    # binary operator precedence (low -> high)
    BIN_LEVELS = [
        ['||'],
        ['&&'],
        ['|'],
        ['^'],
        ['&'],
        ['==', '!='],
        ['<', '<=', '>', '>='],
        ['<<', '>>'],
        ['+', '-'],
        ['*', '/', '%'],
    ]

    def parse_binary(self, level):
        if level >= len(self.BIN_LEVELS):
            return self.parse_unary()
        left = self.parse_binary(level + 1)
        ops = self.BIN_LEVELS[level]
        while self.at('op') and self.peek().val in ops:
            op = self.next().val
            right = self.parse_binary(level + 1)
            left = ('bin', op, left, right)
        return left

    PREFIX_OPS = {'++', '--', '+', '-', '!', '~', '*', '&'}

    def parse_unary(self):
        t = self.peek()
        if t.kind == 'kw' and t.val == 'sizeof':
            self.next()
            self.eat('op', '(')
            # sizeof( <type> ) -- operand is always a type in this codebase
            ty = self.parse_type()
            self.eat('op', ')')
            return ('sizeof_type', ty)
        if t.kind == 'op' and t.val in self.PREFIX_OPS:
            self.next()
            return ('un', t.val, self.parse_unary())
        return self.parse_postfix()

    def parse_postfix(self):
        e = self.parse_primary()
        while True:
            t = self.peek()
            if t.kind == 'op' and t.val == '(':
                self.next()
                args = []
                while not self.at('op', ')'):
                    args.append(self.parse_assign())
                    if self.at('op', ','):
                        self.next()
                self.eat('op', ')')
                e = ('call', e, args)
            elif t.kind == 'op' and t.val == '[':
                self.next()
                idx = self.parse_expr()
                self.eat('op', ']')
                e = ('index', e, idx)
            elif t.kind == 'op' and t.val in ('.', '->'):
                self.next()
                fld = self.eat('id').val
                e = ('member', t.val, e, fld)
            elif t.kind == 'op' and t.val in ('++', '--'):
                self.next()
                e = ('post', t.val, e)
            else:
                return e

    def parse_primary(self):
        t = self.peek()
        if t.kind == 'op' and t.val == '(':
            self.next()
            e = self.parse_expr()
            self.eat('op', ')')
            return ('group', e)
        if t.kind in ('num', 'char', 'str'):
            self.next()
            return (t.kind, t.val)
        if t.kind == 'id':
            self.next()
            return ('id', t.val)
        raise SyntaxError(f'line {t.line}: unexpected primary {t.kind} {t.val!r}')


# ---------------------------------------------------------------------------
# Semantic environment (collected across all loaded units)
# ---------------------------------------------------------------------------

class Env:
    def __init__(self):
        self.globals = {}          # name -> type
        self.funcs = set()         # global function names
        self.struct_fields = {}    # struct -> {field: type}
        self.struct_methods = {}   # struct -> set(method names)

    def collect(self, items):
        for it in items:
            k = it[0]
            if k == 'struct':
                _, name, fields, methods = it
                self.struct_fields[name] = {fn: ft for ft, fn in fields}
                self.struct_methods.setdefault(name, set()).update(methods)
            elif k == 'var':
                _, _ext, vtype, names = it
                for nm in names:
                    self.globals[nm] = vtype
            elif k in ('func', 'func_proto'):
                self.funcs.add(it[1])
            elif k == 'method':
                self.struct_methods.setdefault(it[1], set()).add(it[2])


# ---------------------------------------------------------------------------
# Emitter
# ---------------------------------------------------------------------------

PRELUDE = """\
/* generated by uplnc2c -- do not edit.  See ../BOOTSTRAP.md */
/* UPLNC targets i386, where int and pointers are both 4 bytes; build with
   `gcc -std=gnu89 -m32 -w`.  We deliberately include NO libc headers so that
   UPLNC's own identifiers (e.g. `div`) cannot clash with libc prototypes;
   instead we declare the handful of pointer-returning libc routines here so
   their results are not truncated through an implicit `int` return.
   stderr/stdin/stdout come from UPLNC's own `extern` declarations. */
extern void *calloc();
extern void *malloc();
extern void *realloc();
extern void *fopen();
"""


class Emitter:
    def __init__(self, env):
        self.env = env
        self.out = []
        # per-function context
        self.locals = {}     # name -> type (params + locals in scope)
        self.cur_struct = None

    def w(self, s=''):
        self.out.append(s)

    # -- whole unit --
    def emit_unit(self, items, with_prelude=True):
        if with_prelude:
            self.w(PRELUDE)
        # forward typedefs for all structs so self/mutual refs resolve
        struct_names = [it[1] for it in items if it[0] == 'struct']
        for sn in struct_names:
            self.w(f'typedef struct {sn} {sn};')
        if struct_names:
            self.w()
        # forward declarations for every function/method in this unit
        fwd = []
        seen = set()
        for it in items:
            if it[0] in ('func', 'func_proto'):
                name = it[1]
            elif it[0] == 'method':
                name = f'{it[1]}_{it[2]}'
            else:
                continue
            if name not in seen:
                seen.add(name)
                fwd.append(name)
        for name in fwd:
            self.w(f'int {name}();')
        if fwd:
            self.w()
        for it in items:
            self.emit_toplevel(it)
        return '\n'.join(self.out) + '\n'

    def emit_toplevel(self, it):
        k = it[0]
        if k == 'directive':
            self.w(self.fix_directive(it[1]))
        elif k == 'struct':
            self.emit_struct(it)
        elif k == 'var':
            self.emit_var(it, toplevel=True)
        elif k == 'func_proto':
            pass  # already covered by the forward-declaration block
        elif k == 'func':
            self.emit_func(it)
        elif k == 'method':
            self.emit_method(it)
        else:
            raise ValueError(k)

    @staticmethod
    def fix_directive(text):
        # rewrite  #include "x.he"  ->  #include "x.h"
        if text.lstrip().startswith('#include'):
            return text.replace('.he"', '.h"')
        return text

    def emit_struct(self, it):
        _, name, fields, _methods = it
        self.w(f'struct {name} {{')
        for ftype, fname in fields:
            self.w('    ' + emit_decl(ftype, fname) + ';')
        self.w('};')
        self.w()

    def emit_var(self, it, toplevel):
        _, is_extern, vtype, names = it
        prefix = 'extern ' if is_extern else ''
        self.w(f'{prefix}{emit_group_decl(vtype, names)};')

    # K&R-style parameter list + declarations
    def kr_signature(self, name, params, extra_first=None):
        plist = []
        decls = []
        if extra_first is not None:
            pn, pt = extra_first
            plist.append(pn)
            decls.append(emit_decl(pt, pn) + ';')
        for pn, pt in params:
            plist.append(pn)
            decls.append(emit_decl(pt, pn) + ';')
        sig = f'int {name}(' + ', '.join(plist) + ')'
        return sig, decls

    def emit_func(self, it):
        _, name, params, body = it
        sig, decls = self.kr_signature(name, params)
        self.locals = {pn: pt for pn, pt in params}
        self.cur_struct = None
        self.w(sig)
        for d in decls:
            self.w('    ' + d)
        self.emit_block(body, indent=0)
        self.w()

    def emit_method(self, it):
        _, sname, mname, params, body = it
        this_t = ('ptr', ('base', sname))
        sig, decls = self.kr_signature(f'{sname}_{mname}', params,
                                       extra_first=('this', this_t))
        self.locals = {pn: pt for pn, pt in params}
        self.locals['this'] = this_t
        self.cur_struct = sname
        self.w(sig)
        for d in decls:
            self.w('    ' + d)
        self.emit_block(body, indent=0)
        self.w()

    # -- statements --
    def emit_block(self, blk, indent):
        pad = '    ' * indent
        self.w(pad + '{')
        for s in blk[1]:
            self.emit_stmt(s, indent + 1)
        self.w(pad + '}')

    def emit_stmt(self, s, indent):
        pad = '    ' * indent
        k = s[0]
        if k == 'block':
            self.emit_block(s, indent)
        elif k == 'empty':
            self.w(pad + ';')
        elif k == 'directive':
            self.w(self.fix_directive(s[1]))
        elif k == 'var':
            self.emit_local_var(s, indent)
        elif k == 'expr':
            self.w(pad + self.emit_expr(s[1]) + ';')
        elif k == 'return':
            if s[1] is None:
                self.w(pad + 'return;')
            else:
                self.w(pad + 'return ' + self.emit_expr(s[1]) + ';')
        elif k == 'break':
            self.w(pad + 'break;')
        elif k == 'continue':
            self.w(pad + 'continue;')
        elif k == 'if':
            self.w(pad + 'if (' + self.emit_expr(s[1]) + ')')
            self.emit_stmt_block(s[2], indent)
            if s[3] is not None:
                self.w(pad + 'else')
                self.emit_stmt_block(s[3], indent)
        elif k == 'while':
            self.w(pad + 'while (' + self.emit_expr(s[1]) + ')')
            self.emit_stmt_block(s[2], indent)
        elif k == 'do':
            self.w(pad + 'do')
            self.emit_stmt_block(s[1], indent)
            self.w(pad + 'while (' + self.emit_expr(s[2]) + ');')
        elif k == 'for':
            init = self.emit_expr(s[1]) if s[1] else ''
            cond = self.emit_expr(s[2]) if s[2] else ''
            post = self.emit_expr(s[3]) if s[3] else ''
            self.w(pad + f'for ({init}; {cond}; {post})')
            self.emit_stmt_block(s[4], indent)
        else:
            raise ValueError(k)

    def emit_stmt_block(self, s, indent):
        # emit a sub-statement, adding one indent level unless it's a block
        if s[0] == 'block':
            self.emit_block(s, indent)
        else:
            self.emit_stmt(s, indent + 1)

    def emit_local_var(self, s, indent):
        pad = '    ' * indent
        _, is_extern, vtype, names = s
        for nm in names:
            self.locals[nm] = vtype
        prefix = 'extern ' if is_extern else ''
        self.w(pad + f'{prefix}{emit_group_decl(vtype, names)};')

    # -- expressions --
    def type_of(self, e):
        k = e[0]
        if k == 'group':
            return self.type_of(e[1])
        if k == 'id':
            nm = e[1]
            if nm in self.locals:
                return self.locals[nm]
            if self.cur_struct and nm in self.env.struct_fields.get(self.cur_struct, {}):
                return self.env.struct_fields[self.cur_struct][nm]
            return self.env.globals.get(nm)
        if k == 'member':
            _, op, obj, fld = e
            tobj = self.type_of(obj)
            st = self.struct_of(tobj, deref=(op == '->'))
            if st and fld in self.env.struct_fields.get(st, {}):
                return self.env.struct_fields[st][fld]
            return None
        if k == 'index':
            ta = self.type_of(e[1])
            if ta and ta[0] in ('ptr', 'arr'):
                return ta[-1]
            return None
        if k == 'un':
            if e[1] == '*':
                ta = self.type_of(e[2])
                if ta and ta[0] in ('ptr', 'arr'):
                    return ta[-1]
            if e[1] == '&':
                return ('ptr', self.type_of(e[2]))
            return self.type_of(e[2])
        return None

    def struct_of(self, t, deref):
        """Resolve a type to a struct name; if deref, peel one pointer first."""
        if t is None:
            return None
        if deref:
            if t[0] in ('ptr', 'arr'):
                t = t[-1]
            else:
                return None
        if t[0] == 'base' and t[1] in self.env.struct_fields:
            return t[1]
        return None

    def emit_expr(self, e):
        k = e[0]
        if k == 'num' or k == 'char' or k == 'str':
            return e[1]
        if k == 'id':
            nm = e[1]
            # implicit this->field inside a method
            if self.cur_struct and nm not in self.locals \
                    and nm in self.env.struct_fields.get(self.cur_struct, {}):
                return 'this->' + nm
            return nm
        if k == 'group':
            return '(' + self.emit_expr(e[1]) + ')'
        if k == 'bin':
            return '(' + self.emit_expr(e[2]) + ' ' + e[1] + ' ' + self.emit_expr(e[3]) + ')'
        if k == 'un':
            return '(' + e[1] + self.emit_expr(e[2]) + ')'
        if k == 'post':
            return '(' + self.emit_expr(e[2]) + e[1] + ')'
        if k == 'cond':
            return '(' + self.emit_expr(e[1]) + ' ? ' + self.emit_expr(e[2]) + ' : ' + self.emit_expr(e[3]) + ')'
        if k == 'assign':
            return '(' + self.emit_expr(e[2]) + ' ' + e[1] + ' ' + self.emit_expr(e[3]) + ')'
        if k == 'comma':
            return '(' + ', '.join(self.emit_expr(x) for x in e[1]) + ')'
        if k == 'index':
            return self.emit_expr(e[1]) + '[' + self.emit_expr(e[2]) + ']'
        if k == 'sizeof_type':
            return 'sizeof(' + emit_type_name(e[1]) + ')'
        if k == 'member':
            return self.emit_member_or_method(e, None)
        if k == 'call':
            return self.emit_call(e)
        raise ValueError(k)

    def emit_member_or_method(self, e, call_args):
        _, op, obj, fld = e
        tobj = self.type_of(obj)
        st = self.struct_of(tobj, deref=(op == '->'))
        if call_args is not None and st and fld in self.env.struct_methods.get(st, set()):
            # method call:  obj<op>fld(args) -> st_fld(recv, args)
            if op == '->':
                recv = self.emit_expr(obj)
            else:  # value receiver: pass its address
                recv = '&' + self.paren(obj)
            arglist = [recv] + [self.emit_expr(a) for a in call_args]
            return f'{st}_{fld}(' + ', '.join(arglist) + ')'
        # plain member access
        base = self.emit_expr(obj)
        return f'{base}{op}{fld}'

    def paren(self, e):
        s = self.emit_expr(e)
        if e[0] in ('id', 'group', 'member', 'index'):
            return s
        return '(' + s + ')'

    def emit_call(self, e):
        _, callee, args = e
        if callee[0] == 'member':
            return self.emit_member_or_method(callee, args)
        if callee[0] == 'id':
            nm = callee[1]
            # bare call to a sibling method inside a method body
            if self.cur_struct and nm not in self.env.funcs \
                    and nm in self.env.struct_methods.get(self.cur_struct, set()):
                arglist = ['this'] + [self.emit_expr(a) for a in args]
                return f'{self.cur_struct}_{nm}(' + ', '.join(arglist) + ')'
            return nm + '(' + ', '.join(self.emit_expr(a) for a in args) + ')'
        return self.emit_expr(callee) + '(' + ', '.join(self.emit_expr(a) for a in args) + ')'


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

def prescan_struct_names(srcs):
    names = set()
    for src in srcs:
        toks = lex(src)
        for i, t in enumerate(toks):
            if t.kind == 'kw' and t.val == 'struct' and toks[i + 1].kind == 'id':
                names.add(toks[i + 1].val)
    return names


def transpile(main_src, extra_srcs=(), with_prelude=True):
    """Transpile `main_src` to C.  `extra_srcs` (e.g. included headers) are
    parsed only to populate the type/method environment."""
    all_srcs = [main_src] + list(extra_srcs)
    struct_names = prescan_struct_names(all_srcs)

    env = Env()
    parsed_extra = []
    for src in extra_srcs:
        items = Parser(lex(src), struct_names).parse_unit()
        env.collect(items)
        parsed_extra.append(items)

    main_items = Parser(lex(main_src), struct_names).parse_unit()
    env.collect(main_items)

    return Emitter(env).emit_unit(main_items, with_prelude=with_prelude)


def main(argv):
    import os
    if not argv:
        sys.stderr.write(
            'usage: uplnc2c.py FILE.e [-I included.he ...] [-o OUT.c]\n')
        return 2
    out = None
    includes = []
    infile = None
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == '-o':
            out = argv[i + 1]
            i += 2
        elif a == '-I':
            includes.append(argv[i + 1])
            i += 2
        else:
            infile = a
            i += 1
    main_src = open(infile).read()
    extra = [open(h).read() for h in includes]
    # a header (*.he) emits no prelude (it's #included into a .c)
    with_prelude = not infile.endswith('.he')
    c = transpile(main_src, extra, with_prelude=with_prelude)
    if out:
        open(out, 'w').write(c)
    else:
        sys.stdout.write(c)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
