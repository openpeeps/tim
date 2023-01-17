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
- [x] JIT Compiler w/ JSON computation
- [ ] Transpiles to Nim, JavaScript, Python PHP
- [ ] SEO / Semantic Checker
- [x] Language Extension `.timl` 😎
- [ ] Available as a NodeJS Addon (soon)
- [x] Written in Nim language 👑
- [x] Open Source | `MIT` License

## Install as Nimble library
```
nimble install tim
```

## The look
```tim
div.container > div.row.vh-100 > div.align-self-center
  h3: "Tim Engine is Awesome!"
  p.text-muted: "A high-performance, compiled template engine & markup language"
  @include "button"
```

### JavaScript Snippets
Write JavaScript snippets or a component-based functionality direclty in your `.timl` file, using backticks.

````tim
main > div.container > div.row > div.col-lg-4.mx-auto
  @include "button"

  ```js
document.querySelector('button').addEventListener('click', function() {
  console.log("yay!")
});
  ```
````

### Sass Snippets
Bult-in CSS support with SASS via `libsass`.
````tim
div.container.product > div.row > div.col-4.mx-auto
  a.btn.cta-checkout > span: "Go to checkout"

  ```sass
div.product
  btn
    font-weight: bold
  ```
````

This feature **requires** (libsass)[https://github.com/sass/libsass] library

## API Documentation
https://openpeep.github.io/tim/

## Setup in Nim with JIT Compilation

```nim
import tim, tim/engine/meta
export render, precompile

var Tim*: TimEngine
Tim.init(source = "./templates", output = "./storage/templates", minified = false, indent = 4)

# Precompile your `.timl` templates at boot-time
Tim.precompile()

# Render a specific view by name (filename, or subdir.filename_without_ext)
res.send(Tim.render("homepage"))

```


### 🎩 License
Illustration of Tim Berners-Lee [made by Kagan McLeod](https://www.kaganmcleod.com).<br><br>
This is an Open Source Software released under `MIT` license. [Made by Humans from OpenPeep](https://github.com/openpeep).<br>
Copyright &copy; 2022 OpenPeep & Contributors &mdash; All rights reserved.

<a href="https://hetzner.cloud/?ref=Hm0mYGM9NxZ4"><img src="https://openpeep.ro/banners/openpeep-footer.png" width="100%"></a>
