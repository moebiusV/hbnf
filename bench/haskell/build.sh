#!/bin/sh
# build.sh -- inside the Haskell container, not pinned (the compiles are slow): every parser the rig
# times, into /o/bin.  /w is the repository (read-only), /o the work directory holding the documents,
# the hbnf tape parsers' C and the toml-parser source.
set -eu
H=/w/bench/haskell
mkdir -p /o/bin /tmp/b && cd /tmp/b
EXT="-XBlockArguments -XDeriveDataTypeable -XDeriveGeneric -XDeriveTraversable -XEmptyCase -XFlexibleContexts -XFlexibleInstances -XGeneralizedNewtypeDeriving -XImportQualifiedPost -XLambdaCase -XScopedTypeVariables -XTypeOperators -XTypeSynonymInstances -XViewPatterns -XHaskell2010"

# toml-parser as Debian ships it, and the same modules from the pinned source with Alex and Happy
# run in their optimising modes
ghc -O2 -i$H -outputdir b_base $H/toml/Baseline.hs -o /o/bin/toml-parser > /dev/null
rm -rf tp && mkdir tp && tar xzf /o/toml-parser.tar.gz -C tp --strip-components=1
( cd tp/src && alex -g Toml/Lexer.x -o Toml/Lexer.hs && happy -agc Toml/Parser.y -o Toml/Parser.hs )
ghc -O2 -hide-package toml-parser -itp/src -i$H -outputdir b_tuned $EXT $H/toml/Baseline.hs -o /o/bin/toml-parser-tuned > /dev/null

# JSON: the Alex/Happy grammar written as the tutorials write it, and tuned (strict fields, the
# generators' optimising modes); aeson for what Haskell programs use
for v in plain tuned; do
  rm -rf j_$v && mkdir j_$v
  cp $H/json/$v/* $H/json/Main.hs $H/Timer.hs j_$v/
  ( cd j_$v
    if [ $v = tuned ]; then alex -g Lexer.x -o Lexer.hs && happy -agc Parser.y -o Parser.hs
    else alex Lexer.x -o Lexer.hs && happy Parser.y -o Parser.hs; fi
    ghc -O2 -outputdir obj Main.hs -o /o/bin/json-$v > /dev/null )
done
ghc -O2 -i$H -outputdir b_aeson $H/json/Aeson.hs -o /o/bin/aeson > /dev/null

# YAML: HsYAML's events, and the yaml package (libyaml) into a Value
ghc -O2 -i$H -outputdir b_hsyaml $H/yaml/HsYAML.hs -o /o/bin/hsyaml > /dev/null
ghc -O2 -i$H -outputdir b_yaml $H/yaml/Yaml.hs -o /o/bin/yaml > /dev/null

# the hbnf tape parsers, built as bench/libs/inner.sh builds them
for n in json toml yaml; do
  t=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' /o/$n-tape.c)
  cat /o/$n-tape.c /w/bench/formats/time_tape.c > $n-tape-m.c
  gcc -O2 -w -std=gnu11 -D_GNU_SOURCE -I/w/runtime "-DOUT_T=$t" $n-tape-m.c -o /o/bin/hbnf-$n-tape
done
echo built
