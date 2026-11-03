= Edge cases: `code` and *bold _nested italic_ text*

A line that would start a list in Typst:

- not at the start of a paragraph, but 1. here and = here

\- escaped dash, \# hash, \_ underscore, a \$ sign, an \@mention and \<b\>tags\</b\>.

1986. A year at the start of a line (a paragraph, not a list)

Links: #link("https://a.example/p?q=1&r=2")[plain], #link("https://b.example")[titled], #link("https://c.example/auto"),
and an image #image("img/pic.png", alt: "the alt text").

Snake\_case\_identifier and file\_name.txt stay words; _real italic_ and *strong* and #strike[gone] are marks.
Math-like 2 \* 3 \* 4 stays text, as does a lone \* star or a\_b.

````
no language, with a `tick` inside and ``` in the middle? no.
````

````text
four ticks hold ``` three
````

#line(length: 100%)
