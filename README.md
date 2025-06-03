<p align="center">
  <img src="https://raw.githubusercontent.com/openpeeps/tim/main/.github/timengine.png" alt="Tim - Template Engine" width="200px" height="200px"><br>
  ⚡️ A universal, high-performance templating engine & markup language<br>
  <strong>Fast</strong> • <strong>Compiled</strong> • <strong>Source-to-Source</strong> • <strong>Interpreter</strong><br>
</p>

<p align="center">
  <code>nimble install tim</code> / <code>npm install @openpeeps/tim</code>
</p>

## Key features
- Fast, compiled, clean syntax
- Template engine + Hybrid programming language
- Source-to-Source transpilation to Nim, Go, JavaScript
- Standalone CLI & AST-based Interpreter
- Standard Library
- Transpiles timl code to JavaScript snippets for **Client-Side Rendering**
- Built-in **Browser Sync & Reload**
- Built-in Package Manager
- Written in Nim language 👑

## About
Tim Engine is reinventing the way we write front-end layouts.

Think about HTML but without the `<` `>` nightmares!

So it's time to bring the `template engine` phrase back in Google Trends!

## The thing is...
When it comes to performance, JIT (Just-In-Time) compilation can be a double-edged sword. While it provides a nice boost during 
development, its overhead can slow down the interpreter in production environments.

For development purposes, leveraging the internal interpreter makes sense due to its speed and ease of use. However, for production 
scenarios, consider bundling your front-end application or transpiling to your preferred target source (Nim, JavaScript, Ruby and more)
to minimize overhead and ensure optimal performance.

## Tim Engine CLI
The `⚑` tells that the commands contains additional flags. For printing flags and any extra information use `tim -h` or `tim --help`.
```
Source-to-Source
  src <timl> ⚑                   Transpile `timl` to a target source
  ast <timl> <output> ⚑          Serialize template to binary AST
  repr <ast> <ext> ⚑             Deserialize binary AST to target source
Microservice
  new <config> ⚑                 Initialize a Tim Engine config file
  api <config> ⚑                 Run Tim Engine transpiler as a HTTP API Server
  build <ast> ⚑                  Build pluggable templates from `.timl` to `.so` (requires Nim)
  bundle <config> ⚑              Bundle a standalone front-end app from project (requires Nim)
Development
  install <pkg> ⚑                Install a package from remote source
  uninstall <pkg> ⚑              Uninstall a package from local source
```

## Tim Engine Language
Tim is more than just a templating engine. It's a language! Tim's syntax is very similar with Nim's syntax

**Variables**
```timl
// a mutable variable using `var`
var title = "Tim is Awesome"

// a immutable variable using `const`
const name = "Tim Engine"
```

**Data Types**
```
// single quote strings: 'Single line strings'
// double quote strings: "Awesome is Awesome"

// triple quote strings are usually used for
// defining JavaScript scripts or stylesheets

// Integers: 123 + 2
// Float numbers: 15.5 * 10
// Boolean: `true` or `false`
```

**Functions**
```timl
fn hi(x: string): string =
  return $x & "!"

// wait, you can define function bodies within brackets!
fn hiAgain(x: string): string {
  return $x & "!"
}

// calling the function
h1.fw-bold > span: hi("Hello World")
```

### Source-to-Source transpilation
Keep your logic 100% portable while transpiling your front-end to other target sources.

Use Tim as a development tool and transpile your code to your to your desired target
source code at compile-time with zero-cost runtime.

Currently supported source languages, `JavaScript`, `Nim`, `Python`, `HTML`.
**Note** transpiling to HTML will invoke the built-in AST interpreter. While for the other target sources will
translate code to selected target


### API Render Server
Tim Engine exposes a local HTTP API server that listens to `http://`, enabling source to source transpilation programatically


### Parse JSON, YAML and Markdown
Tim provides built-in functionality for parsing JSON, YAML and Markdown contents.

While at runtime you have `json`, `jsonRemote`, `yaml`, `yamlRemote`, `markdown` and `markdownRemote` for reading contents
from local or remote sources. Here is an example

### Package Manager
Use Tim's built-in package manager to install packages for Tim engine.

### Theme Manager
Use Tim's built-in theme manager to create theme management systems for your web app.