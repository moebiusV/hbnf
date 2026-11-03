       IDENTIFICATION DIVISION.
       PROGRAM-ID. triage9.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       77  short    PIC X(4) VALUE 'ABC '.
       77  location PIC 9.
       PROCEDURE DIVISION.
           MOVE 1 TO location
           DISPLAY short location
           STOP RUN.
