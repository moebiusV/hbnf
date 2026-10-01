# Ada functional style

A contributor's guide. Ada here is written as a strongly typed functional
pipeline: minimize mutable state, drop the boilerplate loops, and favor a
readable expression over a procedural block. Not "code golf" and not point-free
cleverness. Ada 2012 and 2022 features do the work. Each point shows the
imperative form to avoid, then the functional form to write.

## Core expressions and immutability

**1. Constants by default.** Declare a variable only when it must mutate after
initialization.

```ada
--  wrong
X : Integer := 0;
X := Compute (Y);
```

```ada
--  right
X : constant Integer := Compute (Y);
```

**2. Expression functions.** A function that just computes a value is an
expression function, not a `begin ... end` body.

```ada
--  wrong
function Double (X : Integer) return Integer is
begin
   return X * 2;
end Double;
```

```ada
--  right
function Double (X : Integer) return Integer is (X * 2);
```

**3. `if` expressions, not `if` statements.** Initialize in the declaration;
never assign inside a branch.

```ada
--  wrong
Result : Integer;
if X > 0 then
   Result := X;
else
   Result := 0;
end if;
```

```ada
--  right
Result : constant Integer := (if X > 0 then X else 0);
```

**4. `case` expressions, not `case` statements.** The compiler checks that the
alternatives are exhaustive.

```ada
--  wrong
Kind : Token_Kind;
case K is
   when Red    => Kind := T_Stop;
   when Green  => Kind := T_Go;
   when Yellow => Kind := T_Slow;
end case;
```

```ada
--  right
Kind : constant Token_Kind :=
   (case K is
       when Red    => T_Stop,
       when Green  => T_Go,
       when Yellow => T_Slow);
```

**5. `declare` expressions for a local temp.** When an expression needs a
temporary to avoid computing twice, a `declare` expression keeps it an
expression function instead of falling back to a body.

```ada
--  wrong
function Area (R : Float) return Float is
   S : constant Float := R * R;
begin
   return Pi * S;
end Area;
```

```ada
--  right
function Area (R : Float) return Float is
   (declare S : constant Float := R * R; begin Pi * S);
```

**6. No `out` / `in out` parameters.** A function takes inputs and returns new
state; it does not mutate its arguments.

```ada
--  wrong
procedure Set_Status (C : in out Context; S : Status) is
begin
   C.Status := S;
end Set_Status;
```

```ada
--  right
function With_Status (C : Context; S : Status) return Context is
   (C with delta Status => S);
```

**7. Delta aggregates for one-field updates.** Return a new copy with the field
changed; do not overwrite a field of an existing record.

```ada
--  wrong
New_State : State := Old_State;
New_State.Status := Active;
```

```ada
--  right
New_State : constant State := (Old_State with delta Status => Active);
```

**8. Container aggregates.** Initialize with `[...]`, not a run of `.Append` or
`.Insert` calls.

```ada
--  wrong
V : Vectors.Vector;
V.Append (1);
V.Append (2);
V.Append (3);
```

```ada
--  right
V : constant Vectors.Vector := [1, 2, 3];
```

## Loops, iteration and reductions

**9. No imperative `while` / `for` to accumulate.** A loop that builds a total,
a string, or a value is a fold or a comprehension in disguise.

```ada
--  wrong
Total : Integer := 0;
for I of Values loop
   Total := Total + I;
end loop;
```

```ada
--  right
Total : constant Integer := Values'Reduce ("+", 0);
```

**10. Quantified expressions for searches.** `for all` / `for some` replace a
loop that walks a structure looking for a condition.

```ada
--  wrong
All_Active : Boolean := True;
for Node of Tree loop
   if not Node.Is_Active then
      All_Active := False;
      exit;
   end if;
end loop;
```

```ada
--  right
All_Active : constant Boolean := (for all Node of Tree => Node.Is_Active);
```

**11. Filter at the iterator with `when`.** When a loop must run for side
effects, filter with `when` rather than an `if` inside the body.

```ada
--  wrong
for Item of List loop
   if Item.Is_Valid then
      Process (Item);
   end if;
end loop;
```

```ada
--  right
for Item of List when Item.Is_Valid loop
   Process (Item);
end loop;
```

**12. `'Reduce` for folds.** A stateful accumulator becomes a fold.

```ada
--  wrong
Combined : Unbounded_String := Null_Unbounded_String;
for I of Parts loop
   Combined := Combined & I;
end loop;
```

```ada
--  right
Combined : constant Unbounded_String :=
   Parts'Reduce ("&", Null_Unbounded_String);
```

**13. Array comprehensions for maps.** `[for X of Source => F]` transforms a
structure declaratively.

```ada
--  wrong
Squares : Int_Array := (others => 0);
for I in Source'Range loop
   Squares (I) := Source (I) * Source (I);
end loop;
```

```ada
--  right
Squares : constant Int_Array := [for X of Source => X * X];
```

**14. Bounded recursion for tree walks.** Walk a tree by recursion that returns
a value and passes immutable context, not by a global cursor and flags.

```ada
--  wrong
Count : Natural := 0;
procedure Walk (N : Node) is
begin
   if N.Is_Match then
      Count := Count + 1;      --  global state
   end if;
   for C of N.Children loop
      Walk (C);
   end loop;
end Walk;
```

```ada
--  right
function Count_Matches (N : Node) return Natural is
   ((if N.Is_Match then 1 else 0)
    + [for C of N.Children => Count_Matches (C)]'Reduce ("+", 0));
```

## Types, contracts and architecture

**15. Subtypes over procedural validation.** Let the type system enforce
validity; do not write defensive `if ... then raise`.

```ada
--  wrong
procedure Check (X : Integer) is
begin
   if X < 0 then
      raise Constraint_Error;
   end if;
   --  use X
end Check;
```

```ada
--  right
subtype Index is Integer range 1 .. 100;
--  an out-of-range value cannot be built; no check needed
```

**16. Declarative predicates.** A type should refuse to hold invalid data.

```ada
--  wrong
procedure Set_Mode (M : Integer) is
begin
   if M not in 0 | 1 | 2 then
      raise Constraint_Error;
   end if;
   --  use M
end Set_Mode;
```

```ada
--  right
type Mode is new Integer with
   Static_Predicate => Mode in 0 | 1 | 2;
```

**17. `Pre` / `Post` conditions.** Push requirements to the subprogram boundary;
keep the body the transformation only.

```ada
--  wrong
function Pop (S : Stack) return Element is
begin
   if Is_Empty (S) then
      raise Constraint_Error;
   end if;
   --  ...
end Pop;
```

```ada
--  right
function Pop (S : Stack) return Element
   with Pre => not Is_Empty (S);
```

**18. Isolate side effects.** I/O, files and the network live at the edges; the
core is a pure `Data -> Transformation -> New_Data` pipeline.

```ada
--  wrong: the core does I/O
function Process (Data : Input_Data) return Output_Data is
begin
   Put_Line ("processing");        --  I/O in the core
   Write_Log (Data.Name);          --  side effect in the core
   return Transform (Data);
end Process;
```

```ada
--  right: the core is pure, the caller does I/O
function Process (Data : Input_Data) return Output_Data is
   (Transform (Data));

--  at the edge:
Put_Line (Image (Process (Data)));
```

**19. Extended return for a complex immutable object.** Build it in an extended
return; the caller then sees it as a constant.

```ada
--  wrong
function Make_Config return Config is
   C : Config := Null_Config;
begin
   C.Name := ...;
   C.Port := ...;
   return C;
end Make_Config;
```

```ada
--  right
function Make_Config return Config is
begin
   return C : Config do
      C.Name := ...;
      C.Port := ...;
   end return;
end Make_Config;
```

**20. Name intermediates over point-free density.** Readability and explicit
data flow trump brevity.

```ada
--  wrong: one dense pipeline
Total : constant Integer :=
   [for X of Values when X > 0 => X * 2]'Reduce ("+", 0);
```

```ada
--  right: named steps
Positive : constant Int_Array := [for X of Values when X > 0 => X];
Doubled  : constant Int_Array := [for X of Positive => X * 2];
Total    : constant Integer   := Doubled'Reduce ("+", 0);
```

## Beyond the twenty

**Compiler switches are your linter.** Build strict, and treat warnings as
errors in development.

```ada
package Compiler is
   for Default_Switches ("Ada") use
     ("-gnat2022", "-gnatwa", "-gnatVa", "-gnato", "-gnatwe");
end Compiler;
```

`-gnatwe` is right for development but brittle in a package rebuilt against
each new GNAT, so a shipped package may leave it out.

**SPARK for core logic.** A package with no side effects and no hidden state can
be marked, and SPARK then refuses any accidental aliasing, side effect or
uninitialized state.

```ada
pragma SPARK_Mode (On);
```

**`Unbounded_String` composed functionally.** Return and compose with `&`, never
a mutable buffer with `Append`.

```ada
--  wrong
Buffer : Unbounded_String := Null_Unbounded_String;
Append (Buffer, "prefix:");
Append (Buffer, Value);
```

```ada
--  right
Result : constant Unbounded_String := "prefix:" & Value;
```

**Short-circuit `and then` / `or else`, always.** Never plain `and` / `or` for
boolean logic: the second operand may raise or cost needlessly.

```ada
--  wrong: 10 / X is evaluated even when X = 0
if X /= 0 and 10 / X > 2 then
   ...
end if;
```

```ada
--  right
if X /= 0 and then 10 / X > 2 then
   ...
end if;
```
