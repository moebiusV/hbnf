; The POSIX shell command language: the grammar of POSIX.1-2017 section 2.10.2 as the
; standard prints it (posix-shell-1.y, included as it is), the tokens as rules of
; characters (shell-words.hbnf), and what ordered choice needs on top; see shell.md.
;
; White space between tokens is blanks, backslash-newline and comments; a newline is the
; NEWLINE token, so it is not skipped.
dialect ybnf
include "shell-words.hbnf"
include "posix-shell-1.y"
include "shell-fixes.hbnf"
