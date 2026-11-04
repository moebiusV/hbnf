# XML conformance of the parsers of the library benchmark

The same 45 documents through each parser, by the drivers of `bench/libs.sh` (`sh bench/xml-conformance.sh`): 34 break one well-formedness constraint of XML 1.0 each and a conforming parser refuses them; 11 are well-formed, so that refusing everything does not look conformant.  Expat, with its own checks on, is the reference.  The check is done once and kept: each parser's verdicts are stored with a key (its version, the case set, for hbnf the grammar) and rerun only when the key changes.

| parser | refuses the ill-formed | accepts the well-formed | accepts, wrongly |
|---|---:|---:|---|
| expat | 34 of 34 | 11 of 11 | none |
| libxml2 DOM | 34 of 34 | 11 of 11 | none |
| libxml2 SAX2 | 34 of 34 | 11 of 11 | none |
| ElementTree | 34 of 34 | 11 of 11 | none |
| lxml | 34 of 34 | 11 of 11 | none |
| hbnf | 34 of 34 | 11 of 11 | none |
| sax (Node) | 20 of 34 | 10 of 11 | 14 inputs (see below) |
| TinyXML-2 | 9 of 34 | 10 of 11 | 25 inputs (see below) |
| pugixml | 8 of 34 | 11 of 11 | 26 inputs (see below) |
| RapidXML | 7 of 34 | 11 of 11 | 27 inputs (see below) |
| fast-xml-parser | 0 of 34 | 11 of 11 | 34 inputs (see below) |

## Each input

| input | expat | libxml2 DOM | libxml2 SAX2 | ElementTree | lxml | hbnf | sax (Node) | TinyXML-2 | pugixml | RapidXML | fast-xml-parser |
|---|---|---|---|---|---|---|---|---|---|---|---|
| control character U+0001 in text | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | **accept** | **accept** | **accept** | **accept** |
| control character U+0001 in an attribute | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | **accept** | **accept** | **accept** | **accept** |
| duplicate attribute | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | refuse | **accept** | **accept** | **accept** |
| invalid UTF-8 in text (FF FE) | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | **accept** | **accept** | **accept** | **accept** |
| overlong UTF-8 (C0 80) | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | **accept** | **accept** | **accept** | **accept** |
| name containing U+0080 | refuse | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | **accept** | **accept** | **accept** |
| name starting with a digit | refuse | refuse | refuse | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | **accept** |
| character reference &#0; | refuse | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | **accept** | **accept** | **accept** |
| character reference &#x110000; | refuse | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | **accept** | refuse | **accept** |
| character reference &#xD800; (surrogate) | refuse | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | **accept** | **accept** | **accept** |
| character reference &#xFFFE; | refuse | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | **accept** | **accept** | **accept** |
| literal U+FFFE in text | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | **accept** | **accept** | **accept** | **accept** |
| literal ]]> in text | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | **accept** | **accept** | **accept** | **accept** |
| < in an attribute value | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | **accept** | **accept** | **accept** | **accept** |
| -- inside a comment | refuse | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | **accept** | **accept** | **accept** |
| comment ending in ---> | refuse | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | **accept** | **accept** | **accept** |
| undeclared entity &foo; | refuse | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | **accept** | **accept** | **accept** |
| two root elements | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | **accept** | **accept** | **accept** | **accept** |
| no root element, only text | refuse | refuse | refuse | refuse | refuse | refuse | refuse | refuse | refuse | refuse | **accept** |
| mismatched end tag | refuse | refuse | refuse | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | **accept** |
| unterminated element | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | refuse | refuse | refuse | **accept** |
| unquoted attribute value | refuse | refuse | refuse | refuse | refuse | refuse | refuse | refuse | refuse | refuse | **accept** |
| attribute without a value | refuse | refuse | refuse | refuse | refuse | refuse | refuse | refuse | refuse | refuse | **accept** |
| no space between two attributes | refuse | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | refuse | **accept** | **accept** |
| XML declaration not at the start | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | **accept** | **accept** | **accept** | **accept** |
| bad standalone value in the declaration | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | **accept** | **accept** | **accept** | **accept** |
| a bare & in text | refuse | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | **accept** | **accept** | **accept** |
| entity reference without the semicolon | refuse | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | **accept** | **accept** | **accept** |
| text after the root element | refuse | refuse | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | refuse | **accept** |
| processing instruction named XML | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | refuse | **accept** | **accept** | **accept** |
| CDATA section outside the root | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | **accept** | **accept** | **accept** | **accept** |
| DOCTYPE after the root element | refuse | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | **accept** | **accept** | **accept** |
| recursive entity | refuse | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | **accept** | **accept** | **accept** |
| end tag with an attribute | refuse | refuse | refuse | refuse | refuse | refuse | refuse | **accept** | refuse | refuse | **accept** |
| empty element (well-formed) | accept | accept | accept | accept | accept | accept | accept | accept | accept | accept | accept |
| tab and newline in content (well-formed) | accept | accept | accept | accept | accept | accept | accept | accept | accept | accept | accept |
| nested elements and an attribute (well-formed) | accept | accept | accept | accept | accept | accept | accept | accept | accept | accept | accept |
| legal characters: U+10FFFF, UTF-8 text (well-formed) | accept | accept | accept | accept | accept | accept | accept | accept | accept | accept | accept |
| XML declaration with an encoding (well-formed) | accept | accept | accept | accept | accept | accept | accept | accept | accept | accept | accept |
| CDATA with ]] > and <& (well-formed) | accept | accept | accept | accept | accept | accept | accept | accept | accept | accept | accept |
| declared entity and the predefined ones (well-formed) | accept | accept | accept | accept | accept | accept | **refuse** | accept | accept | accept | accept |
| comment and processing instruction (well-formed) | accept | accept | accept | accept | accept | accept | accept | **refuse** | accept | accept | accept |
| byte order mark and declaration (well-formed) | accept | accept | accept | accept | accept | accept | accept | accept | accept | accept | accept |
| names with colon, dash, dot, digit (well-formed) | accept | accept | accept | accept | accept | accept | accept | accept | accept | accept | accept |
| a non-ASCII element name (well-formed) | accept | accept | accept | accept | accept | accept | accept | accept | accept | accept | accept |

A word in bold is a wrong answer.  Where expat itself disagrees with what the input is meant to show: nowhere.
