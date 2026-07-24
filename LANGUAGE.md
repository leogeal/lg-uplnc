# UPLNC Language Specification, Version 0

Status: project specification for the language implemented by this repository.

This document defines the source language accepted by the current `lpp1` and
`langc` toolchain. It records the tested language contract, including deliberate
UPLNC behavior that differs from C. The original compiler paper remains the
historical design reference; this document takes precedence for the evolved
implementation in `src/`.

Version 0 is intentionally implementation-oriented. Rules described as
"implementation limits" are not desirable language properties, but programs
must observe them to compile reliably with this version. Parser recovery after
an error is not part of the language.

## 1. Conventions

Grammar fragments use this EBNF notation:

- `"text"` is a literal token.
- `name` names another production.
- `[ item ]` means zero or one occurrence.
- `{ item }` means zero or more occurrences.
- `( a | b )` selects one alternative.

`struct-name` and `method-name` are identifiers declared in the corresponding
context. Literal metanames refer to the lexical forms in section 3.

Whitespace may separate tokens unless a production says otherwise. A
conforming program is one that satisfies the grammar and semantic constraints,
does not exceed the limits in section 14, and does not execute undefined
behavior described in section 13.

## 2. Source Processing

UPLNC source normally uses `.e` files. Textually included declarations commonly
use `.he`, but the suffix has no language meaning.

The toolchain processes a translation unit as follows:

1. `lpp1` reads the source, removes comments, expands object-like macros, and
   processes includes.
2. `langc` parses the resulting text and emits assembly for one selected target.
3. The driver assembles one or more units and links them with other objects and
   libraries.

### 2.1 Preprocessor directives

The supported directives are:

```ebnf
define-directive  = "#define" identifier replacement-text ;
include-directive = "#include" ( '"' path '"' | "<" path ">" ) ;
```

`#define` creates an object-like macro. The replacement is the rest of the
physical line after leading whitespace. Macro arguments, conditionals,
stringification, token pasting, undefinition, and predefined macros are not
supported. Replacement text is inserted once and is not recursively rescanned.
A macro is visible after its definition through the remainder of preprocessing,
including subsequently included files.

A quoted include is resolved relative to the file containing the directive. An
angle-bracket include is resolved relative to the preprocessor's working
directory. There is no language-level include search path.

Only `/* ... */` comments are supported. They may span lines and do not nest.
`//` is not a comment.

## 3. Lexical Structure

### 3.1 Whitespace and identifiers

Space, horizontal tab, and newline separate tokens. Source is ASCII-oriented.

```ebnf
identifier        = identifier-start { identifier-continue } ;
identifier-start  = "A" ... "Z" | "a" ... "z" | "_" ;
identifier-continue = identifier-start | "0" ... "9" ;
```

An identifier contains at most 15 characters. Identifiers are case-sensitive.
The following words have syntactic meaning and should not be used as ordinary
identifiers:

```text
break case char const continue default do double else enum extern float
for func if int long method return sizeof struct switch unsigned var vastart
while
```

### 3.2 Integer literals

Decimal and lowercase hexadecimal integer literals are supported:

```ebnf
decimal-integer = digit { digit } ;
hex-integer     = "0x" hex-digit { hex-digit } ;
digit           = "0" ... "9" ;
hex-digit       = digit | "a" ... "f" ;
```

There are no integer suffixes. A value through `2147483647` is an `int`
literal. A larger value is represented as a 64-bit literal; it has type `long
long` on i386 and the word-sized `int` type on 64-bit targets. Decimal literals
may not exceed `9223372036854775807`. Hexadecimal literals may contain at most
16 digits. A hex value whose high bit is set preserves that bit pattern, but a
bare literal does not acquire an unsigned type.

A sign immediately before digits is accepted as part of number scanning, but
has the same expression meaning as unary `+` or `-`. Portable source should not
depend on this lexical detail.

### 3.3 Floating-point literals

```ebnf
floating-literal = digits "." [ digits ] [ exponent ]
                 | digits exponent ;
digits           = digit { digit } ;
exponent         = ( "e" | "E" ) [ "+" | "-" ] digits ;
```

A floating-point literal has type `double`. At least one digit must precede the
decimal point, so `0.5` is valid and `.5` is not. Hexadecimal floating-point
literals and suffixes are not supported.

### 3.4 Character and string literals

Character and string literals use single and double quotes respectively. The
recognized escapes are:

| Escape | Value |
|---|---:|
| `\n` | newline, 10 |
| `\t` | horizontal tab, 9 |
| `\b` | backspace, 8 |
| `\f` | form feed, 12 |
| `\x` for any other `x` | `x` itself |

A character literal is an `int`. Conforming version 0 source uses exactly one
character or escape in a character literal. The compiler accepts multi-character
literals, but their value is implementation-defined.

A string literal is a NUL-terminated array stored in read-only program data and
used as a `*char` value. Adjacent string-literal concatenation is not supported.
Conforming literals do not cross a physical source line.

## 4. Types and Target Model

UPLNC has scalar, array, structure, and method-slot types. It has no `void`,
Boolean, union, function-signature, or general user-defined alias type.

### 4.1 Base types

```ebnf
base-type = "char"
          | "unsigned" "char"
          | "int"
          | "long"
          | "unsigned"
          | "unsigned" "long"
          | "long" "long"
          | "unsigned" "long" "long"
          | "float"
          | "double"
          | struct-name ;
```

`long` is an alias for the target word-sized `int`. `unsigned long` is an
alias for `unsigned`. Forms such as `unsigned int`, `long int`, and `signed`
are not part of version 0.

| Type | i386 size | 64-bit target size | Meaning |
|---|---:|---:|---|
| `char` | 1 | 1 | signed 8-bit integer |
| `unsigned char` | 1 | 1 | unsigned 8-bit integer |
| `int`, `long` | 4 | 8 | signed target word |
| `unsigned`, `unsigned long` | 4 | 8 | unsigned target word |
| `long long` | 8 | 8 | signed 64-bit integer |
| `unsigned long long` | 8 | 8 | unsigned 64-bit integer |
| `float` | 4 | 4 | IEEE single-precision storage |
| `double` | 8 | 8 | IEEE double precision |
| any pointer | 4 | 8 | target address word |

The 64-bit targets are `x86_64`, `arm64`, `riscv64`, and `mips64`. The first
three are little-endian; `mips64` is big-endian. i386 is little-endian.

This word model deliberately differs from common 64-bit C ABIs, where C `int`
is usually 32 bits.

### 4.2 Constructed types

Pointers and arrays use prefix type syntax:

```ebnf
type = base-type
     | "*" type
     | "[" constant-expression "]" type ;
```

Examples:

```text
*int        pointer to int
**char      pointer to pointer to char
[8]char     array of eight char
[4]*int     array of four pointers to int
*[4]int     pointer to an array of four int
```

An array dimension must be a positive integer constant expression. Arrays are
stored contiguously with no padding between elements. There are no
parenthesized declarators or typed function pointers.

### 4.3 Structure layout

Structure fields remain in declaration order. A method slot occupies no data.
The first data field has offset zero. Each field consumes its size rounded up
to the target's structure-layout unit: 4 bytes on i386, x86_64, arm64, and
riscv64; 8 bytes on mips64. The structure size is the sum of those rounded
field extents. `sizeof` reports the resulting size.

This is the UPLNC layout, not a promise of C structure ABI compatibility.

## 5. Translation Units and Names

```ebnf
translation-unit = { external-declaration } ;

external-declaration = variable-declaration
                     | enum-declaration
                     | struct-declaration
                     | function-declaration
                     | function-definition
                     | method-definition ;
```

Structure names, global objects, functions, and enum constants are visible from
their declaration to the end of the translation unit. External symbols from
separately compiled units share the linker namespace. UPLNC has no module or
namespace declaration and no internal-linkage qualifier.

A function called before any declaration is assumed to return `int`. This
supports traditional external calls, but a declaration must precede a call when
the actual return type is a pointer, byte type, `double`, or structure. A
prototype should also precede any call whose variadic status matters.

Local names become visible at their declaration. Redeclaring an active local
name is an error; shadowing is not supported. A control-flow statement removes
locals introduced in its body when that statement ends. Braces used as a plain
compound statement do not create a separate name scope in version 0.

## 6. Declarations

### 6.1 Variables

UPLNC accepts either type-first or name-first declarations:

```ebnf
variable-declaration = "var" { variable-qualifier }
                       ( type ":" declarator-list
                       | declarator-list ":" type )
                       [ "=" initializer ] ";" ;
variable-qualifier   = "extern" | "const" ;
declarator-list      = identifier { "," identifier } ;
initializer          = assignment-expression ;
```

`extern` is valid only at file scope and declares storage defined elsewhere.
An uninitialized defined global has all bits zero. An uninitialized local has
an indeterminate value.

An initializer applies to the last name in a declaration and therefore must
follow the complete declarator list:

```text
var int:a,b = 42;
var a,b:int = 42;
```

Split declarations when more than one object needs an initializer.

A local initializer may be any expression assignable to the declared type and
is evaluated at the declaration point. A global initializer must reduce to an
integer constant, one 64-bit integer literal, or one floating-point literal
(optionally negated). Integer globals cannot use floating literals. `float` and
`double` globals require a floating literal such as `1.0`. Global arrays and
structures cannot be initialized in version 0. An `extern` declaration cannot
have an initializer.

`const` allows initialization and rejects later direct assignment or increment
through that declared name. It is shallow: it does not make pointees immutable,
and writes through an alias are not diagnosed. A direct `array[index]` target
whose base is a const array is also rejected; nested aggregate accesses are not
part of the const guarantee. Initialized const globals are emitted in read-only
storage.

### 6.2 Enumerations

```ebnf
enum-declaration = "enum" "{" [ enumerator-list [ "," ] ] "}" ";" ;
enumerator-list  = enumerator { "," enumerator } ;
enumerator       = identifier [ "=" constant-expression ] ;
```

Enumerations are anonymous collections of global `int` constants, not distinct
types. The first implicit value is zero. Each later implicit value is one more
than the preceding value. An explicit value may use previously declared enum
constants. A trailing comma is allowed.

### 6.3 Structures

```ebnf
struct-declaration = "struct" identifier "{" { struct-member } "}" ";" ;
struct-member      = field-declaration | method-slot ;
field-declaration  = ( type [ ":" ] identifier-list
                     | identifier-list ":" type ) ";" ;
identifier-list    = identifier { "," identifier } ;
method-slot        = "func" ( type identifier | identifier [ ":" type ] ) ";" ;
```

The structure name immediately becomes a type name. Fields are selected with
`.` from a structure and `->` from a pointer to a structure.

Member names within one structure must be unique. A structure may refer to
itself through a pointer, but must not contain itself directly.

A method slot declares a statically dispatched method name for the structure
and carries the method's return type — written before the name or after a
trailing colon, defaulting to `int`. A structure or `float` return type is
rejected (use `double`). The slot consumes no object storage and is the
method's authoritative declaration: every call site reads the return type
from it. See section 7.3.

## 7. Functions and Methods

### 7.1 Functions

```ebnf
function-declaration = function-head [ return-clause ] ";" ;
function-definition  = function-head [ return-clause ] statement ;
function-head        = "func" identifier "(" [ parameter-list ] ")" ;
return-clause        = ":" type ;
parameter-list       = named-parameters [ "," "..." ] | "..." ;
named-parameters     = parameter { "," parameter } ;
parameter            = [ "const" ]
                       ( type [ ":" ] identifier
                       | identifier ":" type ) ;
```

Without a return clause, a function returns `int`. A declaration ends in `;`;
a definition is followed by its body, normally a compound statement.

Parameters are passed by value for scalar and pointer types. Structure and
array parameter declarations are rejected; declare a pointer parameter
instead. A `float` parameter or return type is also rejected; use `double` at
function boundaries. A `const` parameter has the same shallow direct-write
restriction as a const local.

Call arguments must have representations compatible with the corresponding
parameters. The compiler records return and variadic information but does not
perform complete prototype-based argument type checking.
Calls to a declared nonvariadic function must provide exactly its named
arguments. A variadic call must provide at least its named arguments.

`return;` is allowed. A returned expression is converted to the declared return
type. Falling through the function body or using `return;` leaves the scalar
return value unspecified. A hosted program conventionally defines
`func main(...)` and returns an integer status, but `main` is not otherwise
special to the language.

### 7.2 Variadic functions

A final `...` makes a function variadic. Within its definition, `vastart()`
returns a `*int` pointing to the first variadic word. Successive arguments are
read as `p[0]`, `p[1]`, and so on. There is no `va_end` operation.

Pointer and word-sized integer arguments occupy one word slot each. A
`double` variadic argument is passed as its raw bits through the same slot
sequence: one word slot on the 64-bit targets and two consecutive 4-byte
slots on i386. The reader recovers it by treating the slot address as a
`*double` and, on i386, advancing the cursor by two words. This is UPLNC's
own variadic convention between UPLNC functions; a declaration with `...`
must be visible at the call site for it to apply, and passing floating
values to *external* C variadic functions remains target-dependent. 64-bit
integer variadic arguments are unsupported on i386. Variadic methods,
variadic structure-returning functions, and variadic functions with
floating-point named parameters are unsupported. Section 14 lists
register-target argument-count limits.

### 7.3 Methods

```ebnf
method-definition = "method" struct-name ( "." | "::" ) method-name
                    "(" [ named-parameters ] ")" [ return-clause ] statement ;
```

The method name must first appear as a method slot in the named structure.
The slot's type is the method's return type; a definition may repeat it in a
return clause, which must then match the slot, and inherits it otherwise.
Calling an undeclared method is a compile-time error. A method call uses
ordinary postfix syntax:

```text
object.method(argument)
pointer->method(argument)
```

Dispatch is static from the receiver type. The receiver is passed by address as
an implicit `*Struct` parameter named `this`. Inside a method, an unqualified
field or method-slot name is resolved through `this`, so `value = x` is
equivalent to `this->value = x` when `value` is a field.

Methods have function parity for scalars: they may return any scalar type
declared on their slot (word integers, pointers, byte types, 64-bit integers,
`double`) and may take `double` parameters, which follow the same per-target
argument conventions as function calls. Version 0 methods are not variadic
and cannot return structures. Method overloading and virtual dispatch are not
supported.

### 7.4 Structure values and returns

Assignment between named structure lvalues copies the complete structure:

```text
left = right;
```

The source and destination must have equal size. Assignment through a
dereferenced structure pointer is not supported; copy named objects or fields.

A function may return a named structure type. Its return expression must be a
named structure lvalue or a materialized call to another structure-returning
function. Returning `*p` as a structure is not supported. Calls may be assigned
to a structure, selected with `.`, returned onward, discarded, or supplied as
an argument. Every reachable return from a structure-returning function must
provide a structure expression; falling through or using `return;` leaves the
destination unspecified and is not conforming version 0 code.

In an ordinary expression or argument position, a structure value decays to
its address. This is a deliberate non-C rule: passing a named structure to a
`*Struct` parameter aliases the caller's object. Passing a structure-returning
call points at a temporary instead. There are no by-value structure parameters.
This decay exists for call and discard contexts; a structure value is not a
general pointer expression for arithmetic or assignment to unrelated types.

## 8. Statements

```ebnf
statement = ";"
          | variable-declaration
          | expression ";"
          | compound-statement
          | if-statement
          | while-statement
          | do-statement
          | for-statement
          | switch-statement
          | return-statement
          | "break" ";"
          | "continue" ";" ;

compound-statement = "{" { statement } "}" ;
if-statement       = "if" "(" expression ")" statement
                     [ "else" statement ] ;
while-statement    = "while" "(" expression ")" statement ;
do-statement       = "do" statement "while" "(" expression ")" ";" ;
for-statement      = "for" "(" expression ";" expression ";"
                     [ expression ] ")" statement ;
return-statement   = "return" [ expression ] ";" ;
```

Unlike C, the initialization and condition expressions of `for` are required,
and a declaration cannot appear in its initialization clause. The update
expression may be omitted.

`break` exits the nearest loop or switch. `continue` continues the nearest
enclosing loop; using it without an enclosing loop is invalid. In a `do` loop,
`continue` proceeds to the condition.

### 8.1 Switch

```ebnf
switch-statement = "switch" "(" expression ")" "{"
                   { switch-item } "}" ;
switch-item      = "case" constant-expression ":"
                 | "default" ":"
                 | statement ;
```

The controlling expression is evaluated once and converted to `int`; a
floating value is truncated. Case values are integer constant expressions and must
be unique; at most one `default` is allowed. Labels must occur directly in the
switch body. Execution falls through between labels unless redirected by a
statement. `break` exits only the switch, while `continue` targets an enclosing
loop.

## 9. Expressions

### 9.1 Grammar and precedence

The following grammar is ordered from lowest to highest precedence:

```ebnf
expression             = assignment-expression
                         { "," assignment-expression } ;
assignment-expression  = conditional-expression
                         [ "=" assignment-expression ] ;
conditional-expression = logical-or-expression
                         [ "?" conditional-expression ":"
                               conditional-expression ] ;
logical-or-expression  = logical-and-expression
                         { "||" logical-and-expression } ;
logical-and-expression = bitwise-or-expression
                         { "&&" bitwise-or-expression } ;
bitwise-or-expression  = bitwise-xor-expression
                         { "|" bitwise-xor-expression } ;
bitwise-xor-expression = bitwise-and-expression
                         { "^" bitwise-and-expression } ;
bitwise-and-expression = equality-expression
                         { "&" equality-expression } ;
equality-expression    = relational-expression
                         { ( "==" | "!=" ) relational-expression } ;
relational-expression  = shift-expression
                         { ( "<" | "<=" | ">" | ">=" ) shift-expression } ;
shift-expression       = additive-expression
                         { ( "<<" | ">>" ) additive-expression } ;
additive-expression    = multiplicative-expression
                         { ( "+" | "-" ) multiplicative-expression } ;
multiplicative-expression = unary-expression
                         { ( "*" | "/" | "%" ) unary-expression } ;
unary-expression       = postfix-expression
                       | ( "++" | "--" | "+" | "-" | "*" | "!" | "~" | "&" )
                         unary-expression ;
postfix-expression     = primary-expression { postfix-suffix }
                         [ "++" | "--" ] ;
postfix-suffix         = "[" expression "]"
                       | "(" [ argument-list ] ")"
                       | "." identifier
                       | "->" identifier ;
argument-list          = assignment-expression
                         { "," assignment-expression } ;
primary-expression     = identifier
                       | integer-literal
                       | floating-literal
                       | character-literal
                       | string-literal
                       | "(" expression ")"
                       | "sizeof" "(" type ")"
                       | "vastart" "(" ")" ;
```

Assignment and conditional expressions associate right-to-left. Arithmetic,
shift, comparison, and bitwise operators associate left-to-right. Parentheses
are required to use an assignment or comma expression as a conditional arm or
as one function argument.

Only simple `=` assignment exists. Compound assignment operators and casts are
not supported.

### 9.2 Values and lvalues

Named variables, dereferenced pointers, array elements, and data fields are
lvalues. Assignment, address-of, and increment/decrement require an appropriate
lvalue. Assignment evaluates to the converted value stored in its destination.
Prefix increment/decrement evaluates to the new value; postfix evaluates to the
old value.

Array and structure lvalues decay to addresses when an ordinary scalar value is
required. A bare function name and `&function` both produce its code address.
Because there is no function type, function addresses are stored in an `int` or
other word-sized scalar and called with postfix `()`.

Indirect calls return `int` and support only integer or pointer arguments.
Typed `double`, byte, pointer, or structure returns require a direct call to a
declared function. Calling a stored address with an incompatible signature is
undefined.

### 9.3 Arithmetic and pointers

`+`, `-`, `*`, and `/` operate on integers and floating values. `%`, shifts,
and bitwise operators require integer values. If either arithmetic operand is
floating, integer operands are converted to `double` and the result is
`double`.

Adding an integer to a pointer, or a pointer to an integer, scales the integer
by the pointed-to type size. Subtracting an integer from a pointer behaves
similarly. Subtracting two pointers to the same element type yields the element
distance as `int`. Adding two pointers or subtracting a pointer from an integer
is invalid. `a[i]` is equivalent to `*(a + i)`.

Signed integer division truncates toward zero; remainder has the corresponding
sign. Unsigned division and remainder use unsigned arithmetic. Right shift is
arithmetic for signed word and signed 64-bit values, and logical for unsigned
word and unsigned 64-bit values.

### 9.4 Logical and comparison operations

Zero integer, null pointer, and positive or negative floating zero are false.
Other scalar values are true, including a floating NaN. `!`, comparisons,
`&&`, and `||` produce `int` zero or one.

`&&` and `||` short-circuit. The condition of `?:` is evaluated first and only
the selected arm is evaluated. The comma operator evaluates its operands in
order and yields the last value. Other operand and argument evaluation order is
unspecified; programs must not depend on competing side effects.

Integer comparisons are unsigned if either word-sized operand is unsigned. A
mixed 64-bit comparison is unsigned if either operand is unsigned. Floating
comparisons follow IEEE unordered behavior: comparison with NaN makes `!=`
true and `==`, `<`, `<=`, `>`, and `>=` false.

### 9.5 `sizeof`

`sizeof(type)` is an integer constant reporting the target size in bytes. The
expression form `sizeof expression` is not supported, and the operand type is
written using UPLNC prefix syntax.

## 10. Conversions

There is no cast syntax. Conversions occur for assignment, initialization,
return, conditional arms, and mixed arithmetic. Calls do not use complete
prototype information to convert arguments; each argument must already have an
ABI-compatible representation as described in section 7.1.

- `char` loads sign-extend to `int`.
- `unsigned char` loads zero-extend to `int`; like C, its value then uses signed
  word operations because every value from 0 through 255 fits in `int`.
- Storing or returning a byte type keeps the low eight bits, then applies the
  declared signedness.
- When either integer operand is 64-bit, the result is 64-bit. If either is
  unsigned, the result is unsigned.
- Otherwise, when either integer operand is `unsigned`, the result is
  `unsigned`; remaining integer arithmetic produces `int`.
- Integer-to-floating conversion produces `double` and respects unsigned
  magnitude.
- Floating-to-integer conversion truncates toward zero. It is defined only when
  the truncated value is representable by the corresponding signed integer
  conversion used on the target.
- Loading `float` widens it to `double`. Floating expressions are evaluated as
  `double`; assignment to `float` narrows the stored value.
- The two arms of `?:` convert to `double` if either is floating. If either arm
  is an explicit 64-bit integer, the usual signed/unsigned 64-bit result is
  used. Otherwise the result preserves the then-arm type; pointer arms should
  have the same type. This last rule differs from C for mixed `int` and
  `unsigned` arms.

Pointers and target-word integers use the same machine representation. Version
0 permits their assignment without explicit casts, which is how untyped
function addresses and some C library declarations are represented. Such a
conversion is only meaningful when the value is a valid address for the target.

## 11. Constant Expressions

An integer constant expression may contain integer and character literals,
previously declared enum constants, `sizeof(type)`, parentheses, unary `-`,
`!`, and `~`, and the integer arithmetic, shift, bitwise, comparison, and
logical binary operators. Every operand must itself be constant. It may not
read an object, call a function, assign, or use `?:`.

Array dimensions, enum values, and case labels must fold to a signed 32-bit
`int` value. Integer global initializers use the same folding rules and may
additionally be a single 64-bit literal. Computed 64-bit constant expressions
are not supported in version 0.

## 12. Separate Compilation and Interoperation

Each source file is a translation unit. A declaration in a `.he` file is only
textual inclusion; it does not create a module. Programs may compile units
separately and link their global functions and objects by name.

`langdrv.pl` selects the established platform calling convention and object
format for `i386`, `x86_64`, `arm64`, `riscv64`, and `mips64`. Scalar calls can
interoperate with C when declarations agree with UPLNC's target sizes and the
supported ABI subset. In particular, UPLNC's 64-bit `int`, structure layout,
structure return convention, methods, variadic cursor, and untyped indirect
calls are not general C ABI promises.

The language itself supplies no standard library. Programs may declare and link
platform functions or use the project's small `lib/` layer.

### 12.1 Debug information

`langc -g` (or `langdrv.pl -g`) adds DWARF debug information to the generated
assembly on every target. It never changes the generated instructions; the
addition is line tables built from `.file`/`.loc` directives, call-frame
unwind data in the strippable `.debug_frame` section rather than `.eh_frame`,
and type and variable descriptions in `.debug_info`. These compiler-generated
debug sections are not loaded at runtime. Linker-generated allocated metadata,
such as a GNU build ID, may still differ between debug and non-debug links.

With `-g` a DWARF debugger can set breakpoints by file and line, step by
statement, produce call-stack backtraces with parameter values, and evaluate
variables: parameters, locals, and defined globals are typed (including
structure members, pointers, and arrays), so `print`, `info locals`, and
`ptype` work. A local that the optimizer promoted into a register carries a
location naming that register, which is exact for the whole function body
(promotion assigns one register for the function's lifetime); the callee-saved
registers used in non-leaf functions are covered by unwind annotations, so a
promoted variable in an outer frame is read from its save slot even when the
current frame reuses the same register. The compile unit records the compile-
time working directory (`DW_AT_comp_dir`), so sources named by relative paths
are found from any directory the debugger runs in. One accuracy rule is
deliberate: block-scoped locals appear as plain function-level variables, so
two block locals sharing a name are both listed. Line and file attribution
follows the preprocessor's line markers across `#include`, and separately
compiled `-g` units link with each unit's line table intact.

## 13. Undefined and Unspecified Behavior

The compiler does not insert general runtime checks. Behavior is undefined for:

- dereferencing an invalid, null, expired, or insufficiently aligned pointer;
- accessing outside an array or object;
- reading an uninitialized automatic object;
- signed overflow, division by zero, or signed minimum divided by `-1`;
- a negative shift or a shift count outside the promoted left operand width;
- converting a floating value outside the corresponding signed conversion
  range used by the target;
- modifying a string literal or other read-only storage;
- calling through an invalid address or incompatible indirect-call signature;
- violating a platform function's ABI or library contract.

Unsigned integer arithmetic wraps modulo `2^N`, where `N` is the width of its type. Object
addresses and layout outside the rules in this document are target-dependent.
Except for short-circuit operators, `?:`, and comma, expression evaluation order
is unspecified.

## 14. Current Implementation Limits

The version 0 implementation diagnoses or restricts the following:

| Area | Limit |
|---|---|
| Physical source line | 158 bytes before newline |
| Identifier | 15 characters |
| Include nesting | 8 nested included files |
| Resolved include path | 159 bytes (the including file's directory + the quoted name) |
| Preprocessor macros | 299 definitions; 6000-byte shared name/body pool |
| String literals | 16000-byte pool per translation unit, including NULs |
| Floating and wide literals | 200 entries and a 4000-byte text pool per unit |
| Numeric token | 47 characters |
| `switch` | 256 case labels |
| Active loops/switches | 74 |
| Diagnostics | compilation stops after 30 errors |
| Mangled method name | `Struct.method` must fit in 15 characters |

Additional ABI-dependent restrictions are:

- On x86_64 and arm64, a direct call may use at most six integer-class
  arguments alongside at most eight floating arguments.
- On register targets, a variadic function must leave an argument register for
  its variadic tail, and a known variadic call cannot exceed the target's
  argument-register count: six on x86_64 and arm64, eight on riscv64 and
  mips64.
- A floating variadic argument travels as raw bits in integer argument slots
  (two 4-byte slots on i386) and requires the callee's `...` declaration to be
  visible at the call site. On i386, 64-bit integer variadic arguments are
  unsupported.
- On register targets, a structure-returning call cannot combine floating
  arguments with the hidden result pointer, and its explicit arguments must
  leave one argument register free for that pointer.
- An indirect call is limited to integer/pointer arguments and an `int` return.
  On register targets its arguments cannot exceed the target argument-register
  count.
- Methods follow the function argument and return conventions for scalars
  (including `double`); they cannot be variadic or return structures. On
  register targets a method call's arguments plus the receiver observe the
  same register-count limits as function calls.

These limits describe this compiler release, not a commitment that later
language versions must retain them.

## 15. Unsupported C Constructs

UPLNC is C-like but is not C. Version 0 does not include, among other things:

- `void`, `bool`, `short`, `signed`, unions, bit-fields, or typedefs;
- C declarator syntax, casts, typed function pointers, or function types;
- compound assignments, `goto`, labels outside `switch`, or inline assembly;
- `static`, `register`, `volatile`, `restrict`, or transitive const types;
- designated, aggregate, or multiple-declarator initializers;
- by-value structure parameters or the platform C structure ABI;
- function-like macros, conditional preprocessing, or `//` comments;
- exceptions, dynamic dispatch, generics, modules, or namespaces.

Code should use only the forms specified above even when error recovery or an
internal compiler name happens to accept additional text.
