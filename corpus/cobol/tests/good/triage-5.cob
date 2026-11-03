       @OPTIONS APOST
       IDENTIFICATION DIVISION.
       PROGRAM-ID. triage5.
       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SPECIAL-NAMES.
       SYMBOLIC CONSTANT
         con-1  IS 1
         con-2  "2c".
       DATA DIVISION
       WORKING-STORAGE SECTION.
       01  r2d2 usage bit pic 111 value b'110'.
       01  sw   pic x.
           88  sw-full value "X" or "A" thru "C" or QUOTE.
       PROCEDURE DIVISION.
           DISPLAY WITH CONVERSION "Whatever"
           STOP RUN.
