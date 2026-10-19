--  The Ada interface against the same fixtures as net_main.c, and the same output.
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces; use Interfaces;
with Net; use Net;

procedure Net_Main is

   function Img (N : Long_Long_Integer) return String is
      S : constant String := Long_Long_Integer'Image (N);
   begin
      return (if S (S'First) = ' ' then S (S'First + 1 .. S'Last) else S);
   end Img;

   --  V in hexadecimal, at least W digits.
   function Hx (V : Unsigned_64; W : Natural) return String is
      Digs : constant String := "0123456789abcdef";
      R    : String (1 .. 16);
      X    : Unsigned_64 := V;
      K    : Natural := 17;
   begin
      loop
         K := K - 1;
         R (K) := Digs (Natural (X mod 16) + 1);
         X := X / 16;
         exit when X = 0;
      end loop;
      return [1 .. Natural'Max (0, W - (17 - K)) => '0'] & R (K .. 16);
   end Hx;

   --  Octets from hexadecimal digits.
   function X (S : String) return Byte_Array is
      R : Byte_Array (0 .. S'Length / 2 - 1);
      function D (C : Character) return Unsigned_8 is
        (if C in '0' .. '9' then Character'Pos (C) - 48
         else Character'Pos (C) - 87);
   begin
      for K in R'Range loop
         R (K) := D (S (S'First + 2 * K)) * 16 + D (S (S'First + 2 * K + 1));
      end loop;
      return R;
   end X;

   function T (S : String) return Byte_Array is
      R : Byte_Array (0 .. S'Length - 1);
   begin
      for K in R'Range loop
         R (K) := Unsigned_8 (Character'Pos (S (S'First + K)));
      end loop;
      return R;
   end T;

   function Eth (Rest : Byte_Array) return Byte_Array is
     (X ("ffffffffffff001122334455") & Rest);

   function Same (A : Octets; B : Byte_Array) return Boolean is
   begin
      if Natural (A.Length) /= B'Length then
         return False;
      end if;
      for K in B'Range loop
         if A.Element (K - B'First) /= B (K) then
            return False;
         end if;
      end loop;
      return True;
   end Same;

   procedure Show (What : String; B : Byte_Array) is
      E   : Bnf_Ethernet_T;
      Ok  : Boolean;
      Err : Parse_Error;
   begin
      Parse_Bytes (B, E, Ok, Err);
      if not Ok then
         Put_Line (What & ": error at octet " & Img (Long_Long_Integer (Err.At_Octet))
                   & ": " & To_String (Err.Message));
         return;
      end if;
      Put (What & ": ethertype=" & Hx (Unsigned_64 (E.Ethertype), 4)
           & " kind=" & Img (Long_Long_Integer (E.Payload.Alt)));
      case E.Payload.Alt is
         when 1 =>
            declare
               Ip : constant Bnf_Ipv4_T := E.Payload.Ip;
            begin
               Put (" ipv4 ihl=" & Img (Long_Long_Integer (Ip.Ihl))
                    & " len=" & Img (Long_Long_Integer (Ip.Total_Length))
                    & " ttl=" & Img (Long_Long_Integer (Ip.Ttl))
                    & " proto=" & Img (Long_Long_Integer (Ip.Protocol))
                    & " src=" & Hx (Unsigned_64 (Ip.Src), 8)
                    & " dst=" & Hx (Unsigned_64 (Ip.Dst), 8)
                    & " opts=" & Img (Long_Long_Integer (Ip.Options.Length)));
               case Ip.Payload.Alt is
                  when 1 =>
                     Put (" tcp " & Img (Long_Long_Integer (Ip.Payload.T.Src_Port))
                          & ">" & Img (Long_Long_Integer (Ip.Payload.T.Dst_Port))
                          & " seq=" & Img (Long_Long_Integer (Ip.Payload.T.Seq_Num))
                          & " syn=" & Img (Long_Long_Integer (Ip.Payload.T.Syn))
                          & " data=" & Img (Long_Long_Integer (Ip.Payload.T.Payload.Length)));
                  when 2 =>
                     Put (" udp " & Img (Long_Long_Integer (Ip.Payload.U.Src_Port))
                          & ">" & Img (Long_Long_Integer (Ip.Payload.U.Dst_Port))
                          & " len=" & Img (Long_Long_Integer (Ip.Payload.U.Length))
                          & " data=" & Img (Long_Long_Integer (Ip.Payload.U.Payload.Length)));
                  when 3 =>
                     Put (" data=" & Img (Long_Long_Integer (Ip.Payload.Rest.Length)));
               end case;
            end;
         when 2 =>
            Put (" arp oper=" & Img (Long_Long_Integer (E.Payload.A.Oper))
                 & " spa=" & Hx (Unsigned_64 (E.Payload.A.Spa), 8)
                 & " tpa=" & Hx (Unsigned_64 (E.Payload.A.Tpa), 8));
         when 3 =>
            Put (" ipv6 flow=" & Hx (Unsigned_64 (E.Payload.V6.Flow_Label), 5)
                 & " next=" & Img (Long_Long_Integer (E.Payload.V6.Next_Header))
                 & " hop=" & Img (Long_Long_Integer (E.Payload.V6.Hop_Limit))
                 & " data=" & Img (Long_Long_Integer (E.Payload.V6.Payload.Length)));
         when 4 =>
            Put (" raw=" & Img (Long_Long_Integer (E.Payload.Rest.Length)));
      end case;
      New_Line;

      --  and back: the bytes read are the bytes written
      declare
         Out_B : Octets;
         Ok2   : Boolean;
         Msg   : Unbounded_String;
      begin
         Emit_Bytes (E, Out_B, Ok2, Msg);
         if not Ok2 then
            Put_Line ("  emit: error: " & To_String (Msg));
         elsif Same (Out_B, B) then
            Put_Line ("  emit: " & Img (Long_Long_Integer (Out_B.Length))
                      & " octets, identical");
         else
            Put_Line ("  emit: DIFFERENT (" & Img (Long_Long_Integer (Out_B.Length))
                      & " octets)");
         end if;
      end;
   end Show;

   procedure Bad_Emit (What : String; E : Bnf_Ethernet_T) is
      Out_B : Octets;
      Ok    : Boolean;
      Msg   : Unbounded_String;
   begin
      Emit_Bytes (E, Out_B, Ok, Msg);
      if Ok then
         Put_Line (What & ": written (" & Img (Long_Long_Integer (Out_B.Length))
                   & " octets)");
      else
         Put_Line (What & ": " & To_String (Msg));
      end if;
   end Bad_Emit;

   Ip : constant Byte_Array :=
     Eth (X ("0800") & X ("460000201234400040" & "01abcd") & X ("0a0000010a000002")
          & X ("01010100") & T ("hi!!"));
   Tcp : constant Byte_Array :=
     Eth (X ("0800") & X ("4500002c000100004006" & "0000") & X ("c0a80001c0a80002")
          & X ("1f90005000000001" & "00000000" & "50022000") & X ("00000000")
          & T ("ping"));
   Udp : constant Byte_Array :=
     Eth (X ("0800") & X ("4500001f000200004011" & "0000") & X ("0a0000010a000002")
          & X ("0035123400" & "0b0000") & T ("abc"));
   Arp : constant Byte_Array :=
     Eth (X ("0806") & X ("0001080006040001") & X ("001122334455c0a80001")
          & X ("000000000000c0a80002"));
   V6 : constant Byte_Array :=
     Eth (X ("86dd") & X ("6001234500041140")
          & X ("20010db8000000000000000000000001")
          & X ("20010db8000000000000000000000002") & T ("abcd"));
   Other : constant Byte_Array := Eth (X ("88cc0102"));   --  LLDP: not listed

   E  : Bnf_Ethernet_T;
   Ok : Boolean;
   Er : Parse_Error;
begin
   Show ("ipv4", Ip);
   Show ("tcp", Tcp);
   Show ("udp", Udp);
   Show ("arp", Arp);
   Show ("ipv6", V6);
   Show ("unlisted ethertype", Other);
   Show ("short", Ip (Ip'First .. Ip'First + 9));

   Parse_Bytes (Tcp, E, Ok, Er);
   declare
      C : Bnf_Ethernet_T := E;
   begin
      C.Payload.Ip.Ihl := 16;
      Bad_Emit ("ihl 16", C);
   end;
   declare
      C : Bnf_Ethernet_T := E;
   begin
      C.Payload.Ip.Options := Octet_Vectors.To_Vector (0, 4);
      Bad_Emit ("options longer than ihl says", C);
   end;
   declare
      C  : Bnf_Ethernet_T := E;
      AE : Bnf_Ethernet_T;
   begin
      Parse_Bytes (Arp, AE, Ok, Er);
      C.Payload := (Alt => 2, A => AE.Payload.A);
      Bad_Emit ("arp payload for an ipv4 ethertype", C);
   end;
   declare
      C : Bnf_Ethernet_T := E;
   begin
      C.Ethertype := 16#1234#;
      Bad_Emit ("ethertype not in the list", C);
   end;
end Net_Main;
