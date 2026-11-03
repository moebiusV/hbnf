       IDENTIFICATION DIVISION.
       PROGRAM-ID. triage6.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       78  k1    VALUE 10 * 2 + 1.
       01  n     PIC S9(4).
           88  f VALUE IS 100 THRU 128 1000 THRU 1280 -9 THRU -2.
       01  c     PIC X.
           88  h VALUE "X" OR "A" THRU "C".
       01  tbl.
           05  e PIC 9 OCCURS 3 ASCENDING KEY e INDEXED BY ix.
       PROCEDURE DIVISION.
           SEARCH ALL e END
               DISPLAY "none"
             WHEN e (ix) = 1
               CONTINUE
           END-SEARCH
           STOP RUN.
