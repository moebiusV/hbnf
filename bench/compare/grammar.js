// grammar.js — the toy language for tree-sitter 0.27.  Whitespace is an extra,
// `word` names the identifier token so keywords are lexed against it, and the
// two ports are fields so the driver can read them back from the tree.
module.exports = grammar({
  name: 'toy',
  extras: $ => [/\s+/],
  word: $ => $.word,
  rules: {
    config: $ => repeat($.rule),
    rule: $ => seq(
      $.action, $.direction,
      'on', $.word,
      'proto', $.word,
      'from', $.word, 'port', field('from_port', $.number),
      'to', $.word, 'port', field('to_port', $.number)),
    action: $ => choice('pass', 'block', 'match'),
    direction: $ => choice('in', 'out'),
    word: $ => /[A-Za-z0-9_.:\/-]+/,
    number: $ => /[0-9]+/,
  },
});
