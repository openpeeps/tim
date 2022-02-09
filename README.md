<p align="center">
    <img src="https://raw.githubusercontent.com/openpeep/tim/main/.github/tim.png" width="140px"><br>
    ⚡️ A high-performance compiled template engine inspired by Emmet syntax.<br>
    <strong>Fast</strong> • <strong>Dependency free</strong> • Written in Nim language 👑
</p>

_Work in progress_

## 😍 Key Features
- [x] Emmet-syntax 🤓
- [x] Multi-threading | Low memory foot-print 🍃
- [x] Tim as **Nimble library** for Nim programming 👑
- [x] **Tim as Binary** for calling from other programming languages 🥳
- [ ] `layouts`, `views` and `partials` logic
- [ ] Variable Assignment
- [ ] `for` Loops & Iterations
- [ ] `if`, `elif`, `else` Conditional Statements
- [ ] `JSON` AST Generator
- [ ] Just-in-time Compilation
- [ ] Semantic Checker & SEO Optimizer
- [ ] Language Extension `.timl` 😎
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

## Using Tim from other programming languages

<details>
    <summary>NodeJS example</summary>

JIT compiler on request, using `.timl.ast`, `spawn`

```js
const http = require('http');
const { spawn } = require('child_process');
const server = http.createServer();

const Views = {
    'profile': './storage/tim/jit/profile.timl.ast'         // add content example of this timl.ast
}

const User = {
    data: {
        name: 'Tim Berners-Lee',
        username: 'tim.berners.lee',
    },
    
    json: () => JSON.stringify(User.data)
}

server.on('request', (request, response) => {
    if (request.url === '/profile') {
        var htmlPage = ""

        // Spawn a process to Tim Engine for JIT of the given AST,
        // providing data as a stringified JSON with `--data` flag
        const tim = spawn('tim', ['--ast', Views.profile, '--data', User.json()]);
        
        process.stdin.pipe(tim.stdin)
        for await (const html of tim.stdout) {
            htmlPage += data
        };
        res.end(htmlPage)
    } else {
        res.writeHead(404, {'Content-Type': 'text/html'})
        res.end('404 | Route not found')
    }
});

server.listen(3000);
```
</details>

## Examples
_todo_

## Roadmap
_to add roadmap_

### ❤ Contributions
If you like this project you can contribute to Tim project by opening new issues, fixing bugs, contribute with code, ideas and you can even [donate via PayPal address](https://www.paypal.com/donate/?hosted_button_id=RJK3ZTDWPL55C) 🥰

### 👑 Discover Nim language
<strong>What's Nim?</strong> Nim is a statically typed compiled systems programming language. It combines successful concepts from mature languages like Python, Ada and Modula. [Find out more about Nim language](https://nim-lang.org/)

<strong>Why Nim?</strong> Performance, fast compilation and C-like freedom. We want to keep code clean, readable, concise, and close to our intention. Also a very good language to learn in 2022.

### 🎩 License
Illustration of Tim Berners-Lee [made by Kagan McLeod](https://www.kaganmcleod.com).<br><br>
This is an Open Source Software released under `MIT` license. [Developed by Humans from OpenPeep](https://github.com/openpeep).<br>
Copyright &copy; 2022 OpenPeep & Contributors &mdash; All rights reserved.
