// Toy.g4 — the toy language for ANTLR 4.  The actions build the same
// information the other parsers do (a count and the sum of both ports), so the
// parse tree need not be kept; ToyMain also runs the default parse-tree mode.
grammar Toy;

@parser::members {
  public long count = 0;
  public long long_sum = 0;
}

config : stmt* EOF ;
stmt   : action dir 'on' WORD 'proto' WORD 'from' WORD 'port' fp=NUMBER
         'to' WORD 'port' tp=NUMBER
         { count++; long_sum += Long.parseLong($fp.text) + Long.parseLong($tp.text); } ;
action : 'pass' | 'block' | 'match' ;
dir    : 'in' | 'out' ;

NUMBER : [0-9]+ ;
WORD   : [A-Za-z0-9_.:/-]+ ;
WS     : [ \t\r\n]+ -> skip ;
