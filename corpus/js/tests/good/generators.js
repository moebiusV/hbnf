function* g() { yield; yield 1; yield* h(); var x = yield 2; (yield) + 1; yield yield 3; }
