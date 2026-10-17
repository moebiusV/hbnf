%{
/* toy.l — the lexer half of the toy language, the way a parse.y has one:
 * keywords first so they win ties, one WORD and one NUMBER, strings strdup'd.
 * The input is a NUL-terminated buffer read whole, as hbnf's parse_text does. */
#include <string.h>
#include "y.tab.h"
%}
%option noyywrap nounput noinput
%%
pass            return PASS;
block           return BLOCK;
match           return MATCH;
in              return IN;
out             return OUT;
on              return ON;
proto           return PROTO;
from            return FROM;
to              return TO;
port            return PORT;
[0-9]+          { yylval.number = strtoll(yytext, NULL, 10); return NUMBER; }
[A-Za-z0-9_.:/-]+ { yylval.string = strdup(yytext); return WORD; }
[ \t\r\n]+      ;
.               return yytext[0];
%%
