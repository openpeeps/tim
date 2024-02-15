<p align="center">
  <img src="https://raw.githubusercontent.com/openpeeps/tim/main/.github/timengine.png" alt="Tim - Template Engine" width="200px" height="200px"><br>
  ⚡️ A high-performance template engine & markup language<br>
  <strong>Fast</strong> • <strong>Compiled</strong> • Written in Nim language 👑
</p>

<p align="center">
  <code>nimble install tim</code>
</p>

<p align="center">
  <a href="https://openpeeps.github.io/tim/">API reference</a><br><br>
  <img src="https://github.com/openpeeps/tim/workflows/test/badge.svg" alt="Github Actions"> <img src="https://github.com/openpeeps/tim/workflows/docs/badge.svg" alt="Github Actions">
</p>


## 😍 Key Features
_todo_

## Quick Example
```timl
div.container > div.row > div.col-lg-7.mx-auto
  h1.display-3.fw-bold: "Tim is Awesome"
```

## Tim in action
Check [/example](https://github.com/openpeeps/tim/tree/main/example) folder to better understand Tim's structure. [Also, check the generated HTML file](https://htmlpreview.github.io/?https://raw.githubusercontent.com/openpeeps/tim/main/example/preview.html) 

### Client-Side Rendering
Tim Engine seamlessly shifts rendering to the client side for dynamic interactions, using the intuitive `@client` block statement.

```timl
body
  section#contact > div.container
    div.row > div.col-12 > h3.fw-bold: "Leave a message"
    div#contact-form

@client target="#contact-form"
  form method="POST" action="comment"
    div > input.form-control type="text" name="username" placeholder="Your name"
    div.my-3 > textarea.form-control name="message": "Your message" style="height: 140px"
    div > button.btn.btn-dark type="submit": "Submit your message"
@end
```
## Embeddable Code
Tim Engine is a versatile template engine. It seamlessly integrates a variety of embeddable code formats, including:
**JavaScript**, **YAML**/**JSON**, **CSS/SCSS** and **Sass**

### JavaScript block

```timl
@js
  document.addEventListener('DOMContentLoaded', function() {
    console.log("Hello, hello, hello!")
  });
@end
```

### JSON block
_todo_

### YAML block
_todo_

#### CSS/SCSS and Sass
_todo_


### ❤ Contributions & Support
- 🐛 Found a bug? [Create a new Issue](https://github.com/openpeeps/tim/issues)
- 👋 Wanna help? [Fork it!](https://github.com/openpeeps/tim/fork)
- 😎 [Get €20 in cloud credits from Hetzner](https://hetzner.cloud/?ref=Hm0mYGM9NxZ4)
- 🥰 [Donate via PayPal address](https://www.paypal.com/donate/?hosted_button_id=RJK3ZTDWPL55C)

### 🎩 License
Tim Engine | `LGPLv3` license. [Made by Humans from OpenPeeps](https://github.com/openpeeps).<br>
Copyright &copy; 2024 OpenPeeps & Contributors &mdash; All rights reserved.
