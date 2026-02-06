// This function provides a simple API for creating and
// manipulating DOM elements reducing the need for verbose
// JavaScript code when working with the DOM.
const timl = function() {
  return {
    el: (tag) => document.createElement(tag),
    attr: (el, key, value) => el.setAttribute(key, value),
    add: (el, par, position = 'beforeend') => par.insertAdjacentElement(position, el)
  }
}
