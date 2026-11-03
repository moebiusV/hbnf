       IDENTIFICATION DIVISION.
       PROGRAM-ID. triage4.
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT f ASSIGN "f.dat" ORGANIZATION SEQUENTIAL.
       DATA DIVISION.
       FILE SECTION.
       FD  f.
       01  f-rec PIC X.
       WORKING-STORAGE SECTION.
       77  foo PIC X.
       77  i PIC 9.
       77  j PIC 9.
       PROCEDURE DIVISION.
       DECLARATIVES.
       dec SECTION. USE EXCEPTION CONDITION EC-BOUNDS.
           CONTINUE.
       dbg SECTION.
           USE FOR DEBUGGING ON ALL REFERENCES OF i
                                ALL j.
           CONTINUE.
       END DECLARATIVES.
       main-sec SECTION.
           ACCEPT foo FROM ESCAPE
           ACCEPT foo
               ESCAPE
                   CONTINUE
               NOT ON ESCAPE
                   CONTINUE
           END-ACCEPT
           OPEN EXCLUSIVE INPUT f
           CLOSE f
           STOP RUN.
