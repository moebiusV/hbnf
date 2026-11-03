"use strict";
class Point { #x; #y; constructor(x, y) { this.#x = x; this.#y = y; } get x() { return this.#x } static from({x, y}) { return new Point(x, y) } toString() { return `(${this.#x}, ${this.#y})` } }
const pts = [[1, 2], [3, 4]].map(([x, y]) => new Point(x, y));
for (const p of pts) console.log(`${p}`);
export_ = async function* () { for await (const q of pts) yield q?.x ?? 0 };
