<p align="center">
    <img src="https://raw.githubusercontent.com/openpeep/tim/main/.github/tim.png" width="140px"><br>
    ⚡️ A high-performance compiled template engine inspired by Emmet syntax.<br>
    <strong>Fast</strong> • <strong>Compiled</strong> • Written in Nim language 👑
</p>

_Work in progress_

## 😍 Key Features
- [x] Emmet-syntax 🤓
- [x] Multi-threading | Low memory foot-print 🍃
- [x] Tim as **Nimble library** for Nim programming 👑
- [ ] Tim as a Native NodeJS addon
- [ ] `layouts`, `views` and `partials` logic
- [ ] Variable Assignment
- [ ] `for` Loops & Iterations
- [ ] `if`, `elif`, `else` Conditional Statements
- [ ] `JSON` AST Generator
- [ ] Just-in-time Computation
- [ ] SEO Optimizer
- [ ] Language Extension `.timl` 😎
- [x] Lexer based on [Toktok library](https://github.com/openpeep/toktok)
- [x] Open Source | `MIT` License

## Installing
Tim Engine is different than other Template Engines because it can be used as a standalone binary application,
so it can be called from any programming language exactly like `zip`, `mkdir`, or `ls`.

In this case there are two ways to install Tim.

As a nimble library for the Nim programming language
```
nimble install tim
```

As a standalone binary app. Compile it by yourself or get the latest version
of Tim from GitHub Releases and set Tim to your working `PATH`
```
ln -s /path/to/your/tim /usr/local/bin
```

Tim Compiler is separated in 2 phases. The first phase is involved in tokenizing the syntax via `Lexer` ➤ `Parser` ➤ `AST Nodes` Generation,
and saves the AST output for using later in the second phase, `JIT`. In Just-in-time compilation the Compiler resolves `data assignments`,
`conditional statements` and available `loops` or `iterations`.

## Examples

```timl
section > div.container > div.row.vh-100.align-items-center
    div#card-reminder.col-5.mx-auto > div.bg-light.border.p-4.rounded.shadow-sm
        div.row
            div > small.d-block.text-muted.text-uppercase: "Issue No #5"
            div.col-lg-9.col-12 > h1.fw-bold: "Meet great assets for designers 🔥"
            div.col-lg-3.col-12.text-center
                div.bg-primary.overflow-hidden
                    img.img-fluid
                        src = "https://imgproxy.generated.photos/7B_3uVLgPR17_HmsbJHTelyufws9nIRSTEE2D_FJmLA/rs:fit:256:256/Z3M6Ly9nZW5lcmF0/ZWQtcGhvdG9zL3Ry/YW5zcGFyZW50X3Yz/L3YzXzA2OTc1Nzgu/cG5n.png"
                        width = "110px"
                    style =
                        border-radius: "42%"
                        width, height: "80px"
        div.row > div.col-12
            p.lead.fw-normal: "Start Exploring Communities you're interested in.<br>The first step to find areas' experts in the rooms"
            div.row
                div.col > a.btn.btn-outline-secondary: "Skip for now"
                div.col > a.btn.btn-dark.d-block: "Join Clubhouse 🤟"
```

### About Tim Engine

#### Layouts, Views and Partials
A `view` represent a screen page. It can be wrapped in a specific `layout` and can contain multiple `partials`. All files must end with ``.timl`` extension.

#### Variables
Are simple identifiers that reflects your json object `data`. So a variable can be an `array`, `bool`, `float`, `int`, `object`, `null`, or `string`.
Cannot be defined on `runtime`. Also, a variable cannot hold mixed data. And, variables are typed-safe, so their type cannot be changed during `runtime`.

A variable must be always prefixed with `$`. Variables are `case sensitive`, can be `alphanumerical`, and separated with `_` only.

```js
{
    "user": true,
    "is": {
        "admin": true
    },
    "admin": true,

    // invalid examples
    " ": "Just checking...",
    "you-tell-me": 123,
    "lets.try.again": "Okay",
    "user": false
}
```

```tim
if $user == $is.admin
    a href="/dashboard": "Go to dashboard"
else: 
    a href="/profile": "Go to your Profile"

if $admin:
    span: "Fake admin"
```

Variable nodes are generated based on given `JsonNode` and limited to first level of your `Json` nodes only.
So anything deeper than that is just... `json`. You can use `.` annotation to access other levels.

#### Conditionals, Comparison and Logical Operators
Tim knows about the following conditional statements: `if`, `elif` and `else`.

The following Comparison Operators are valid
- [x] Equal `$a == $b`
- [x] Not Equal `$a != $b`
- [x] Greater than `$a > $b`
- [x] Less than `$a < $b`
- [x] Greater than or Equal `$a >= $b`
- [x] Less than or Equal `$a <= $b`


# Code Syntax
<details>
    <summary>Sublime Text 4</summary>

```yaml
%YAML 1.2
---
# See http://www.sublimetext.com/docs/syntax.html
file_extensions:
  - timl
scope: source.timl
variables:
  ident: '[A-Za-z_][A-Za-z_0-9]*'
contexts:
  main:
    # Strings begin and end with quotes, and use backslashes as an escape
    # character
    - match: '"'
      scope: punctuation.definition.string.begin.timl
      push: double_quoted_string

    # Tim Engine allows single-line comments starting with `#` to end of line
    - match: '#'
      scope: punctuation.definition.comment.timl
      push: line_comment

    - match: '\|'
      scope: markup.bold keyword.operator.logical

    - match: '\*'
      scope: entity.name.tag

    - match: '>'
      scope: punctuation

    - match: ':'
      scope: markup.bold variable.language

    - match: '='
      scope: markup.bold keyword.operator.assignment.timl

    - match: '\b(html|head|meta|link|script|main|section|article|aside|div)\b'
      scope: entity.name.tag.timl

    - match: '\b(h1|h2|h3|h4|h5|h6|a|p|em|b|strong|span)\b'
      scope: entity.name.type.timl

    - match: '\b(-)?[0-9.]+\b'
      scope: constant.numeric.timl

    - match: '\b{{ident}}\b'
      scope: punctuation.definition

  double_quoted_string:
    - meta_scope: string.quoted.double.timl
    - match: '\\.'
      scope: constant.character.escape.timl
    - match: '"'
      scope: punctuation.definition.string.end.timl
      pop: true

  line_comment:
    - meta_scope: comment.line.timl
    - match: $
      pop: true
```

</details>

## Roadmap

### `0.1.0`
- [x] Lexer, Parser, AST, Compiler
- [x] Create Sublime Syntax
- [ ] Create VSCode Syntax (yak)
- [ ] Add tests
- [ ] Talk about it on ycombinator / stackoverflow / producthunt

### ❤ Contributions
If you like this project you can contribute to Tim project by opening new issues, fixing bugs, contribute with code, ideas and you can even [donate via PayPal address](https://www.paypal.com/donate/?hosted_button_id=RJK3ZTDWPL55C) 🥰

### 👑 Discover Nim language
<strong>What's Nim?</strong> Nim is a statically typed compiled systems programming language. It combines successful concepts from mature languages like Python, Ada and Modula. [Find out more about Nim language](https://nim-lang.org/)

<strong>Why Nim?</strong> Performance, fast compilation and C-like freedom. We want to keep code clean, readable, concise, and close to our intention. Also a very good language to learn in 2022.

### 🎩 License
Illustration of Tim Berners-Lee [made by Kagan McLeod](https://www.kaganmcleod.com).<br><br>
This is an Open Source Software released under `MIT` license. [Made by Humans from OpenPeep](https://github.com/openpeep).<br>
Copyright &copy; 2022 OpenPeep & Contributors &mdash; All rights reserved.

<a href="https://hetzner.cloud/?ref=Hm0mYGM9NxZ4"><img src="https://openpeep.ro/banners/openpeep-footer.png" width="100%"></a>
