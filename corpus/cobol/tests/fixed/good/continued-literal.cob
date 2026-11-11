000100 IDENTIFICATION DIVISION.                                         ID3
000200 PROGRAM-ID. T3.                                                  ID3
000300 DATA DIVISION.                                                   
000400 WORKING-STORAGE SECTION.                                         
000500 01 MSG PIC X(60) VALUE "A LONG LITERAL THAT RUNS OUT AT THE RIGHT MARGIN OF THE LINEID000500
000600-    "AND GOES ON IN THE NEXT LINE".                              ID000600
009000 PROCEDURE DIVISION.                                              
009100     STOP RUN.                                                    
