<p align="center">
    <img src="https://raw.githubusercontent.com/openpeep/tim/main/.github/tim.png" width="140px"><br>
    ⚡️ A high-performance template engine & markup language inspired by Emmet syntax.<br>
    <strong>Fast</strong> • <strong>Compiled</strong> • Written in Nim language 👑
</p>

Tim is a templating engine that provides an elegant markup language inspired by the `Emmet` syntax.
Instead of having closing tags, Tim relies on indentation and whitespace, allowing for clean, readable code and high-speed productivity.

## 😍 Key Features
- [x] Emmet-syntax 🤓
- [ ] Mixins
- [x] `layouts`, `views` and `partials` logic
- [x] `Global`, `Scope`, and `Internal` variables
- [x] `for` Loops
- [x] `if`, `elif`, `else` Conditionals
- [x] Partials via `@include`
- [ ] JIT Evaluator
- [ ] SEO / Semantic Checker
- [x] Language Extension `.timl` 😎
- [ ] Available as a NodeJS Addon (soon)
- [x] Written in Nim language 👑
- [x] Open Source | `MIT` License

## Installing
```
nimble install tim
```

## API Documentation
https://openpeep.github.io/tim/

## Setup

```nim
import tim
export render, precompile

var Tim*: TimEngine.init(
            source = "./templates",
                # directory path to find your `.timl` files
            output = "./storage/templates",
                # directory path to store Binary JSON files for JIT compiler
            minified = false,
                # Whether to minify the final HTML output (enabled by default)
            indent = 4
                # Used to indent your HTML output (ignored when `minified` is true)
        )

# Precompile your `.timl` templates at boot-time
Tim.precompile()

# Render a specific view by name (filename, or subdir.filename_without_ext)
res.send(Tim.render("homepage"))

```

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
    - match: '"'
      scope: punctuation.definition.string.begin.timl
      push: double_quoted_string

    - match: '//'
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

    - match: '\b(html|head|meta|script|body|title)\b'
      scope: entity.name.tag.timl

    - match: '\b(main|section|article|aside|div|footer|header)\b'
      scope: entity.name.tag.timl

    - match: '\b(h1|h2|h3|h4|h5|h6|a|p|em|b|strong|span|u)\b'
      scope: entity.name.type.text.timl

    - match: '\b(table|tbody|td|tfoot|th|thead|tr)\b'
      scope: entity.name.tag.table.timl

    - match: '\b(area|base|br|col|embed|hr|img|input|link|meta|param|source|track|wbr)\b'
      scope: entity.name.tag.selfclosing.timl

    - match: '\b(button|label|select|textarea|legend|datalist|output|option|optgroup)\b'
      scope: entity.name.tag.form.timl

    - match: '\b(ul|ol|dl|dt|dd|li)\b'
      scope: entity.name.tag.list.timl

    - match: '\b(if|elif|else|for|in)\b'
      scope: keyword.control.timl

    - match: '\b(-)?[0-9.]+\b'
      scope: constant.numeric.timl

    - match: '\b(true|false)\b'
      scope: constant.language.timl

    - match: '\b{{ident}}\b'
      scope: punctuation.definition

    - match: '@include'
      scope: keyword.control.import.timl

    - match: '@mixin'
      scope: entity.name.function.timl

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

### `0.1.x`
- [x] Lexer, Parser, AST Generator, Compiler
- [x] SVG Support
- [x] Output Minifier
- [ ] Variable Assignments
- [x] Conditional Statements
- [x] Loops / Iterations
- [x] Mixins implementation
- [ ] SEO Checker
- [ ] Semantic Checker
- [x] Create Sublime Syntax
- [ ] Create VSCode Syntax (yak)
- [ ] Add tests
- [ ] Add Benchmarks
- [ ] Talk about it on ycombinator / stackoverflow / producthunt

### `0.2.x`
- [ ] JIT Evaluator

### 🎩 License
Illustration of Tim Berners-Lee [made by Kagan McLeod](https://www.kaganmcleod.com).<br><br>
This is an Open Source Software released under `MIT` license. [Made by Humans from OpenPeep](https://github.com/openpeep).<br>
Copyright &copy; 2022 OpenPeep & Contributors &mdash; All rights reserved.

<a href="https://hetzner.cloud/?ref=Hm0mYGM9NxZ4"><img src="https://openpeep.ro/banners/openpeep-footer.png" width="100%"></a>
