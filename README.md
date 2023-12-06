A fast, compiled, multi-threading templating engine and markup language written in Nim
Can be used from Nim, Node/Bun (as addon) or as a standalone CLI application.

## Key features
- Fast, compiled, multi-threading
- Transpile `timl` to your favorite language [See Supported languages](#supported-languages)
- As a Nimble library for `Nim` development
- Available for **Node** & **Bun** [Tim Engine for NodeJS and Bun](#tim-for-javascript)
- Easy to learn, intuitive syntax
- Built-in Browser Sync & Reload
- Written in Nim language
- Open Source | MIT License

## Examples
Tim requires the following directories to be created `layouts`, `views`, `partials`. Also,
pre-compile to binary AST and static HTML

Using Tim as a Nimble library:

```tim
div.container > div.row > div.col-12
  h1.display-3: "Tim is awesome!"
  p: "This is Tim Engine, a fast template-engine & markup language"
  for $x in $items:
    span: $x
```

```nim
import tim

# Create a singleton of `Tim`
var timl = newTim("./templates", "./storage", currentSourcePath(), minify = true, indent = 2)

# tell Tim to precompile available `.timl` templates.
# this must be called once in the main state of your application
timl.precompile(flush = true, waitThread = true)

timl.render("index")
```

### CLI
Work in progress

- 🐛 Found a bug? [Create a new Issue](https://github.com/openpeeps/bro/issues)
- 👋 Wanna help? [Fork it!](https://github.com/openpeeps/bro/fork)
- 😎 [Get €20 in cloud credits from Hetzner](https://hetzner.cloud/?ref=Hm0mYGM9NxZ4)
- 🥰 [Donate to OpenPeeps via PayPal address](https://www.paypal.com/donate/?hosted_button_id=RJK3ZTDWPL55C)

## 🎩 License 
Tim Engine is an Open Source software released under LGPLv3. Proudly made in 🇪🇺 Europe [by Humans from OpenPeeps](https://github.com/openpeeps).
Copyright &copy; 2023 OpenPeeps & Contributors &mdash; All rights reserved.