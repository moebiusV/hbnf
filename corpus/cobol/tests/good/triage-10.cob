       IDENTIFICATION DIVISION.
       PROGRAM-ID. triage10.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  a PIC 99..
       77  p USAGE POINTER.
       78  icon-warn VALUE 2.
       PROCEDURE DIVISION.
           DISPLAY MESSAGE "Important"
                   TITLE "Very important"
                   TYPE = 1
                   ICON IS icon-warn
           ALLOCATE 10 CHARACTERS INITIALIZED LOC 24 RETURNING p
           STOP RUN.
