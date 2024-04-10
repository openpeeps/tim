<p align="center">
  <img src="https://raw.githubusercontent.com/openpeeps/tim/main/.github/timengine.png" alt="Tim - Template Engine" width="200px" height="200px"><br>
  ⚡️ A high-performance template engine & markup language<br>
  <strong>Fast</strong> • <strong>Compiled</strong> • Written in Nim 👑
</p>

<p align="center">
  <code>nimble install tim</code> / <code>npm install timl</code>
</p>

<p align="center">
  <a href="https://openpeeps.github.io/tim/">API reference</a> | <a href="https://github.com/openpeeps/tim/releases">Download</a><br><br>
  <img src="https://github.com/openpeeps/tim/workflows/test/badge.svg" alt="Github Actions"> <img src="https://github.com/openpeeps/tim/workflows/docs/badge.svg" alt="Github Actions">
</p>

## 😍 Key Features
or more like a _todo list_
- Fast & easy to code!
- Caching & Pre-compilation
- Transpiles to **JavaScript** for **Client-Side Rendering**
- Supports embeddable code `json`, `js`, `yaml`, `css`
- Built-in **Browser Sync & Reload**
- Output Minifier
- Written in Nim language 👑

**Tim as a Package**: For developers looking to incorporate Tim's power into their projects, Tim Engine is
also available for Nim development as a Nimble package and for **JavaScript** developers as a native **Node.js** & **Bun** `.addon`.
This allows you to seamlessly integrate Tim compilation within your existing workflow, empowering you to leverage
Tim's capabilities directly within your codebase.<br>
#### Other features
- Available for Nim development via Nimble `nimble install tim`
- Available for JavaScript backend via NPM `npm install timl`
- Built-in AST Interpreter & JIT Rendering 

**Standalone CLI App**<br>
This user-friendly command-line interface allows you to easily compile Tim code
directly to your desired target source code. Simply provide your Tim code as input, and the CLI will
output the equivalent code in `Nim`, `JavaScript`, `Ruby`, or `Python`.

#### Other features
- Available for Linux, MacOS and Windows
- Built-in real-time Server-Side Rendering `SSR` via `ZeroMQ`

### Quick Example
```timl
div.container > div.row > div.col-lg-7.mx-auto
  h1.display-3.fw-bold: "Tim is Awesome"
  a href="https://github.com/openpeeps/tim" title="This is hot!": "Check Tim on GitHub"
```

**👉 Tim Syntax Highlighting plugins**<br>
[VSCode Extension](https://marketplace.visualstudio.com/items?itemName=CletusIgwe.timextension) | [Sublime Text 4](https://packagecontrol.io/packages/tim)

## Tim in action
Check [/example](https://github.com/openpeeps/tim/tree/main/example) folder to better understand Tim's structure.
[Also check the generated HTML file](https://htmlpreview.github.io/?https://raw.githubusercontent.com/openpeeps/tim/main/example/preview.html) 


### Template structure
Tim has its own little filesystem that continuously monitors `.timl` for changes/creation or deletion.
Here is a basic filesystem structure:

<details>
  <summary>See Tim's filesystem structure</summary>

```
storage/
  ast/
    # auto-generated
    # for storing pre-compiled binary .ast nodes
  html/
    # auto-generated
    # for storing html files from static templates
templates/
  layouts/ # main place for layouts. (create the directory manually)
    base.timl
    customer.timl
  partials/ # main place for storing partials (create the directory manually)
    product/
      price.timl
      cta.timl
  views/ # main place for storing views (create the directory manually)
    customer.timl
    products.timl
    product.timl
```
</details>

### Client-Side Rendering
Tim Engine seamlessly shifts rendering to the client side for dynamic interactions, using the intuitive `@client` block statement.

```timl
body
  section#contact > div.container
    div.row > div.col-12 > h3.fw-bold: "Leave a message"
    div#commentForm

  @client target="#commentForm"
    form method="POST" action="/submitComment"
      div.form-floating
        input.form-control type="text" name="username"
          placeholder="Your name" autocomplete="off" required=""
        label: "Your name"
  
      div.form-floating.my-3
        textarea.form-control name="message" style="height: 140px" required="": "Your message"
        label: "Your message"
      div.text-center > button.btn.btn-dark.px-4.rounded-pill type="submit": "Submit your message"
  @end
```

### Data
Tim provides 3 types of data storages. **Global** and **Local** as JsonNode objects for handling immutable data from the app to your `timl` templates,
and **Template** based data at template level using Tim's built-in AST-based interpreter.

1. **Global data** can be passed at precompile-time and is made available globally for all layouts, views and partials.<br>
Note: Using `$app` in a template will mark it as JIT.
```nim
timl.precompile(
  global = %*{
    "year": parseInt(now().format("yyyy"))
  }
)
```

Accessing global data can be done using the `$app` constant:
```timl
footer > div.container > div.row > div.col-12
  small: "&copy; " & $app.year & " &mdash; Made by Humans from OpenPeeps"
```

2. **Local data** can be passed to a template from route's callback (controller).
The constant `$this` can be used to access data from the local storage.<br>
Note: Using `$this` in a template will mark it as JIT.

```nim
timl.render("index", local = %*{
  loggedin: true,
  username: "Johnny Boy"
})
```

```timl
if $this.loggedin:
  h1.fw-bold: "Hello, " & $this.username
  a href="/logout": "Log out"
else:
  h1: "Hello!"
  a href="/login": "Please login to view this page"
```

3. **Template variables** can be declared inside templates using `var` or `const`. The only difference
between these two is that constants are immutable and requires initialization.

The scope of a declared variable is limited to the branch in which it was declared.

```timl
var a = 1       // a global scoped variable
if $a == 1:
  var b = 2     // a block-scoped variable
  echo $a + b   // prints 3
echo $b         // error, undeclared variable
```
_Template variables are known at compile time. So the final output is generated as `.html`.
If the assigned value comes from local or global storage, then it will automatically trigger the JIT flag
and the final result will be saved as `.ast`_

#### Data types
Supported datatypes: `string`, `int`, `float`, `bool`, `array`, `object`

```
var a = "Hello"
var b = 10
var c = 10.5 
var d = true

var e = []      // init an empty array
var f = {}      // init an empty object
```

#### Math
Math is cool.
```
var x = 2 * 2 - 1.5
echo $x  // 2.5
```

#### Debug
Sometimes you want to know what the heck is going on! For debug reasons you can use `echo` to print data.
```
echo "Hello, World!"
echo $this.weirdThing
```

Also, Tim provides an `assert` command so you can unit test your code.
```
var x = "Tim is awesome, right?"
assert $x.type == string
assert $x == "Tim is awesome, right?"
```
_Note, `assert` commands are cleared when in `release` mode_

#### Function

```timl
fn say(x: string): string // forward declaration

fn say(x: string): string =
  return "Hello, " & $x

echo say("Pantzini!")
echo say "Pantzini"       // this works too

// function overloading works too
fn say(x: int): int = 
  return $x * 1

echo say(1)
h1 > span: say(2)
```

#### Conditionals
```timl
var x = 1
if $x == 1 and $x > 0:
  span: "one"
elif $x == 0 or $x < 1:
  span: "zero"
else:
  span: "nope"
```

#### For loop
```timl
var boxes = [
  {
    title: "Chimney Sweep"
    description: "Once feared for the soot they carried,
      these skilled climbers cleaned fireplaces to prevent
      fires and improve indoor air quality" 
  }
  {
    title: "Town Crier"
    description: "With booming voices and ringing bells,
      they delivered news and announcements in the days
      before mass media"
  }
  {
    title: "Ratcatcher"
    description: "These pest controllers faced smelly
      challenges, but their work helped prevent the
      spread of diseases like the plague"
  }
]

div.container > div.row.mb-3
  div.col-12 > h3.fw-bold: "Forgotten Professions"
  for $box in $boxes:
    div.col-lg-4 > div.card > div.card-body
      div.card-title.fw-bold.h4: $box.title
      p.card-text: $box.description
```

#### While loops
```
var
  i = 0
  x = ["fork", "work", "push"]
while $i < $x.high:
  span: $x[$i]
  inc $i
```

`break` command can be used in `for` and `while` loops to immediately leave the loop body
```
for $c in "hello":
  echo $x
  break
```

### Escaping
_todo_

## Embed Code
Tim integrates a variety of embeddable code formats, including: **JavaScript**, **YAML**/**JSON** and **CSS**

### JavaScript block

```timl
@js
  document.addEventListener('DOMContentLoaded', function() {
    console.log("Hello, hello, hello!")
  });
@end
```

### JSON block
Note that JSON and YAML blocks requires identification, a `#someIdent` is required after `@json` or `@yaml`
```timl
@json#sayHelloJson
{"hello": "hello"}
@end
```

### YAML block
Tim can parse and validate YAML contents. 
```timl
@yaml#sayHelloYaml
hello: "hello"
@end
```

#### CSS
_todo_


#### Placeholders
_todo_

#### Standard Library
Tim provides a built-in standard library of functions and small utilities:<br>
`std/system` (loaded by default), `std/[os, strings, arrays, objects, math]`

```timl
// std/system
fn random*(max: int): int
fn len*(x: string): int
fn encode*(x: string): string
fn decode*(x: string): string
fn toString*(x: int): string
fn timl*(code: string): string

// std/math
fn ceil*(x: float): float
fn floor*(x: float): float
fn max*(x: int, y: int): int
fn min*(x: int, y: int): int
fn round*(x: float): float
fn hypot*(x: float, y: float): float
fn log*(x: float, base: float): float
fn pow*(x: float, y: float): float
fn sqrt*(x: float): float
fn cos*(x: float): float
fn sin*(x: float): float
fn tan*(x: float): float
fn acos*(x: float): float
fn asin*(x: float): float
fn rad2deg*(d: float): float
fn deg2rad*(d: float): float
fn atan*(x: float): float
fn atan2*(x: float, y: float): float
fn trunc*(x: float): float

// std/strings
fn endsWith*(s: string, suffix: string): bool
fn startsWith*(s: string, prefix: string): bool
fn capitalize*(s: string): string
fn replace*(s: string, sub: string, by: string): string
fn toLower*(s: string): string
fn contains*(s: string, sub: string): bool
fn parseBool*(s: string): bool
fn parseInt*(s: string): int
fn parseFloat*(s: string): float
fn format*(s: string, a: array): string

// std/arrays
fn contains*(x: array, item: string): bool
fn add*(x: array, item: string): void
fn shift*(x: array): void
fn pop*(x: array): void
fn shuffle*(x: array): void
fn join*(x: array, sep: string): string
fn delete*(x: array, pos: int): void
fn find*(x: array, item: string): int

// std/os
fn absolutePath*(path: string): string
fn dirExists*(path: string): bool
fn fileExists*(path: string): bool
fn normalize*(path: string): string
fn getFilename*(path: string): string
fn isAbsolute*(path: string): bool
fn readFile*(path: string): string
fn isRelative*(path: string, base: string): bool
fn getCurrentDir*(): string
fn join*(head: string, tail: string): string
fn parentDir*(path: string): string
fn walkFiles*(path: string): array
```

## Browser Sync & Reload
Compile your project with `-d:timHotCode` flag, then connect to Tim's WebSocket server to auto reload the page when there are changes on disk.<br>
_Note that this feature is not available when compiling with `-d:release`._

The internal websocket returns `"1"` when detecting changes, otherwise `"0"`
```js
  {
    function connectWatchoutServer() {      
      const watchout = new WebSocket('ws://127.0.0.1:6502/ws');
      watchout.addEventListener('message', (e) => {
        if(e.data == '1') location.reload()
      });
      watchout.addEventListener('close', () => {
        setTimeout(() => {
          console.log('Watchout WebSocket is closed. Try again...')
          connectWatchoutServer()
        }, 300)
      })
    }
    connectWatchoutServer()
  }
```

### Syntax Extensions
- VSCode Extension available in [VS Marketplace](https://marketplace.visualstudio.com/items?itemName=CletusIgwe.timextension) (Thanks to [Cletus Igwe](https://github.com/Uzo2005))
- Sublime Syntax package available in [/editors](https://github.com/openpeeps/tim/blob/main/editors/tim.sublime-syntax)

### ❤ Contributions & Support
- 🐛 Found a bug? [Create a new Issue](https://github.com/openpeeps/tim/issues)
- 👋 Wanna help? [Fork it!](https://github.com/openpeeps/tim/fork)
- 🎉 Spread the word! **Tell your friends about Tim Engine**
- ⚽️ Play with Tim Engine in your next web-project
- 😎 [Get €20 in cloud credits from Hetzner](https://hetzner.cloud/?ref=Hm0mYGM9NxZ4)
- 🥰 [Donate via PayPal address](https://www.paypal.com/donate/?hosted_button_id=RJK3ZTDWPL55C)

### 🎩 License
Tim Engine | `LGPLv3` license. [Made by Humans from OpenPeeps](https://github.com/openpeeps).<br>
Copyright &copy; 2024 OpenPeeps & Contributors &mdash; All rights reserved.
