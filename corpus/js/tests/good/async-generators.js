async function* g() { yield 1; yield* h(); for await (const x of y) { yield x } await 1; }
