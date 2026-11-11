000100 IDENTIFICATION DIVISION.                                         ID3
000200 PROGRAM-ID. T3.                                                  ID3
000300 DATA DIVISION.                                                   
000400 WORKING-STORAGE SECTION.                                         
000500 01 MSG PIC X(60) VALUE "A LITERAL THAT RUNS OUT AT THE RIGHT MARGIN OF THE LINE
000600-    AND GOES ON WITHOUT A QUOTE".                                
009000 PROCEDURE DIVISION.                                              
009100     STOP RUN.                                                    
