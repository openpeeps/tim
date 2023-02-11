<p align="center">
  <img src="https://raw.githubusercontent.com/openpeep/tim/main/.github/tim.png" width="140px"><br>
  ⚡️ A high-performance template engine & markup language inspired by Emmet syntax.<br>
  <strong>Fast</strong> • <strong>Compiled</strong> • Written in Nim language 👑
</p>

<p align="center">
  <code>nimble install find</code>
</p>

<p align="center">
  <a href="https://openpeep.github.io/tim/">API reference</a><br><br>
  <img src="https://github.com/openpeep/tim/workflows/test/badge.svg" alt="Github Actions"> <img src="https://github.com/openpeep/tim/workflows/docs/badge.svg" alt="Github Actions">
</p>


<p align="center">
<img src="https://raw.githubusercontent.com/openpeep/tim/main/.github/tim-look.png" width="772px">
</p>

<details align="center">
  <summary>Got Snippets. Want some?</summary>
  <img src="https://raw.githubusercontent.com/openpeep/tim/main/.github/tim-snippets.png" width="772px">
</details>

## 😍 Key Features
- [x] `layouts`, `views` and `partials` logic
- [x] `Global`, `Scope`, and `Internal` variables
- [x] `for` Loop Statements
- [x] `if`/`elif`/`else` Conditional Statements
- [x] Partials via `@include`
- [ ] Mixins
- [ ] SEO / Semantic Checker
- [x] Language Extension `.timl` 😎
- [x] Snippets 🎊
    * JavaScript 🥰
    * JSON 😍 
    * YAML 🤩 w/ Built-in parser via Nyml
    * SASS 🫠 w/ Built-in parser via `libsass`
- [x] Written in Nim language 👑
- [x] Open Source | `MIT` License

## 😎 Library features

- [x] Everything in Basics 
- [x] `Global` and `Scope` data using `JSON` (`std/json` or `pkg/packedjson`)
- [x] Static transpilation to `HTML` files
- [x] ♨️ JIT Compilation using `BSON` AST

## 🌎 Standalone CLI
The CLI is a standalone cross-language application that transpiles your **Tim templates** into source code for the current (supported) language.

Of course, the generated source code will not look very nice, but who cares,
since you'll always have your `.timl` sources and finally, the application will **render at super speed!**

How many times have you heard _"Moustache is slow"_, or _"Pug.js compiling extremely slow"_, or _"...out of memory"_,
or _"Jinja being extremely slow when..."_?

Well, that's no longer the case!

### CLI Features
- [x] Everything in Basics
- [x] `Global` and `Scope` data using language
- [x] Cross-language
- [ ] `.timl` ➡ `.nim`
- [ ] ↳ `.js`
- [ ] ↳ `.rb`
- [ ] ↳ `.py`
- [ ] ↳ `.php` 


## Examples

```json
[
  "apple", "grapefruits", "pineapple", "blueberries", "raspberries", "melons"
]
```

Loops. A simple for loop
```timl
for $item in $this.fruits:
  div > li > span: $item
```

Conditionals
```timl
if $this.fruits[0] == "apple":
  
```

**Objects & Arrays**
You can access an item in array using `[]`
```timl
div > li > h3: $this.fruits[0]
```

**Handling errors**
JIT compiler will print errors at runtime

Let's say we try to access an undefined property name
```timl
button: $this.fruits.name
```

Will result in.
```
Warning: templates/views/system/list.timl
  Undefined property "name"
```

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
Built-in CSS support with SASS via `libsass` (install [libsass](https://github.com/sass/libsass) library)

````tim
div.container.product > div.row > div.col-4.mx-auto
  a.btn.cta-checkout > span: "Go to checkout"

  ```sass
div.product
  btn
    font-weight: bold
  ```
````


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

### ❤ Contributions & Support
- 🐛 Found a bug? [Create a new Issue](https://github.com/openpeep/tim/issues)
- 👋 Wanna help? [Fork it!](https://github.com/openpeep/tim/fork)
- 😎 [Get €20 in cloud credits from Hetzner](https://hetzner.cloud/?ref=Hm0mYGM9NxZ4)
- 🥰 [Donate via PayPal address](https://www.paypal.com/donate/?hosted_button_id=RJK3ZTDWPL55C)

### 🎩 License
Illustration of Tim Berners-Lee [made by Kagan McLeod](https://www.kaganmcleod.com).<br><br>
Tim &mdash; Open Source Software released under `MIT` license. [Made by Humans from OpenPeep](https://github.com/openpeep).<br>
Copyright &copy; 2023 OpenPeep & Contributors &mdash; All rights reserved.