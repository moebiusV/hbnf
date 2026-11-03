       IDENTIFICATION DIVISION.
       PROGRAM-ID. mismatch.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       77  x PIC 9.
       PROCEDURE DIVISION.
           ADD 1 TO x
           END-SUBTRACT
           STOP RUN.
