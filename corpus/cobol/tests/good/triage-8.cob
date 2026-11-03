       IDENTIFICATION DIVISION.
       PROGRAM-ID. triage8.
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
       77  x PIC X(4).
       77  l PIC 9.
       COMMUNICATION SECTION.
       CD  commname FOR INITIAL INPUT.
       01  crec.
           03  cname1 PIC X(87).
       PROCEDURE DIVISION.
           DISABLE INPUT commname WITH KEY cname1.
           DISPLAY "Length " l LENGTH x
           OPEN I-O f ALLOWING NO OTHERS
           CLOSE f
           OPEN I-O f ALLOWING ALL
           CLOSE f
           OPEN I-O f FOR LOCK
           CLOSE f
           STOP RUN.
