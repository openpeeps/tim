<p align="center">
  <img src="https://raw.githubusercontent.com/openpeep/tim/main/.github/tim.png" width="140px"><br>
  ⚡️ A high-performance template engine & markup language inspired by Emmet syntax.<br>
  <strong>Fast</strong> • <strong>Compiled</strong> • Written in Nim language 👑
</p>

<p align="center">
<img src="https://raw.githubusercontent.com/openpeep/tim/main/.github/tim-look.png" width="772px">
</p>
<details align="center">
  <summary>Show me snippets, snippets, snippets! 😍</summary>
  <img src="https://raw.githubusercontent.com/openpeep/tim/main/.github/tim-snippets.png" width="772px">
</details>

## 😍 Key Features
- [x] `layouts`, `views` and `partials` logic
- [x] `Global`, `Scope`, and `Internal` variables
- [x] `for` Loops
- [x] `if`, `elif`, `else` Conditionals
- [x] Partials via `@include`
- [ ] Mixins
- [x] ♨️ JIT Compiler w/ JSON computation
- [x] 🌎 Transpiles to Nim, JavaScript, Python, PHP
- [ ] SEO / Semantic Checker
- [x] Language Extension `.timl` 😎
- [x] Snippets 🎊
    * JavaScript 🥰
    * JSON 😍 
    * YAML 🤩 w/ Built-in parser via Nyml
    * SASS 🫠 w/ Built-in parser via `libsass`
- [x] Written in Nim language 👑
- [x] Open Source | `MIT` License

## CLI app vs Library 
First of all, you should know the differences between the CLI app and the Library.

### Tim CLI
The CLI is a standalone cross-platform application that transpiles your **Tim templates** into source code for the current (supported) language.

Of course, the generated source code will not look very nice, but who cares,
since you have the Tim templates and finally the application will **render at super speed!**

How many times have you heard _"Moustache is slow"_, or _"Pug.js compiling extremely slow"_, or _"...out of memory"_,
or _"Jinja being extremely slow when..."_?

Well, that's no longer the case! If even now, using **Tim Engine**, you complain that something is running slowly, well,
the language you're running is to blame!

### The library
_todo_


## Snippets

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

This feature **requires** [libsass](https://github.com/sass/libsass) library

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
