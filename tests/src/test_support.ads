------------------------------------------------------------------------------
--  test_support.ads
--
--  Helpers shared by the regression tests: float comparison, a scratch
--  directory for the files the tests generate, the golden files, the tiny
--  picture used as input and a way to run the lithophane program.
------------------------------------------------------------------------------

with Ada.Strings.Unbounded;

with Lithophane; use Lithophane;

package Test_Support is

   procedure Assert_Near
     (Actual    : Float;
      Expected  : Float;
      What      : String;
      Tolerance : Float := 1.0e-4);

   --  Empty the scratch directory (bin/scratch, next to the test driver).
   procedure Reset_Scratch;

   --  Full name of the file Name in the scratch directory.
   function Scratch (Name : String) return String;

   --  Full name of the file Name in tests/golden.
   function Golden (Name : String) return String;

   function Exists (Path : String) return Boolean;
   function Read_File (Path : String) return String;
   procedure Write_File (Path : String; Content : String);
   procedure Delete_File (Path : String);

   function Contains (Text : String; Pattern : String) return Boolean;
   function Occurrences (Text : String; Pattern : String) return Natural;

   --  Text without its carriage returns, to compare text files whatever the
   --  line terminator of the platform.
   function Without_CR (Text : String) return String;

   --  Compare the file Path with the golden file Name. When the environment
   --  variable LITHOPHANE_UPDATE_GOLDEN is set, the golden file is replaced
   --  by Path instead.
   procedure Assert_Matches_Golden
     (Path : String; Name : String; Is_Text : Boolean);

   --  The picture used by the tests, as a binary PPM (4 x 3 pixels): the
   --  two top rows are the greys 0, 60, 120 and 180, the bottom row is
   --  black.
   Picture_Width  : constant := 4;
   Picture_Height : constant := 3;
   procedure Write_Picture (Path : String);

   --  A Width x Height matrix, indexed from 1, filled with Grey.
   function Flat_Matrix
     (Width : Positive; Height : Positive; Grey : Grey_Type)
      return Matrix_Grey_Access;

   type Text_List is
     array (Positive range <>) of Ada.Strings.Unbounded.Unbounded_String;

   function "+"
     (Source : String) return Ada.Strings.Unbounded.Unbounded_String
   renames Ada.Strings.Unbounded.To_Unbounded_String;

   type Run_Result is record
      Status : Integer;
      Output : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Run the lithophane program in the scratch directory with the blank
   --  separated Arguments. Output holds what it wrote on standard output
   --  and, when Merge_Stderr is set, on standard error.
   function Run
     (Arguments : String; Merge_Stderr : Boolean := True) return Run_Result;

   function Printed (Result : Run_Result; Pattern : String) return Boolean;

end Test_Support;
