class A { #a = 1; #m() { return this.#a } get #g() { return 1 } static #s() {} has(o) { return #a in o } access(o) { return o.#a + o?.#a + this.#m() } }
