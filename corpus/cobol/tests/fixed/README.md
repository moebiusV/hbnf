Programs in the fixed reference format, read by `corpus/cobol/cobol-fixed.hbnf` (`tests/cobol.sh`; `cobc -fixed` is the reference where it is
installed).  Not read: text that begins in the indicator column (column 7) after six blanks is read as text where cobc refuses it, a word or a number
continued with `-` (only literals and picture strings are), a tab is one column.
