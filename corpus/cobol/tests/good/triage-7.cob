       IDENTIFICATION DIVISION.
       PROGRAM-ID. triage7.
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT f ASSIGN "f.dat" ORGANIZATION INDEXED
               ACCESS DYNAMIC RECORD KEY f-key.
       DATA DIVISION.
       FILE SECTION.
       FD  f.
       01  f-rec.
           05  f-key PIC X.
       WORKING-STORAGE SECTION.
       01  grp.
           05  fld PIC X(4).
       PROCEDURE DIVISION.
           DISPLAY 1.23E0
           DISPLAY 543.12345E10
           DISPLAY -5.5e-3
           UNLOCK f
           UNLOCK f RECORD
           STOP RUN.
