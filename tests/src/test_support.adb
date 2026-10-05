------------------------------------------------------------------------------
--  test_support.adb
------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;

with AUnit.Assertions; use AUnit.Assertions;

with GNAT.OS_Lib;

package body Test_Support is

   package Dirs renames Ada.Directories;
   package SU renames Ada.Strings.Unbounded;

   Update_Golden_Variable : constant String := "LITHOPHANE_UPDATE_GOLDEN";

   --  Directory of the test driver; the lithophane program is built next
   --  to it.
   function Driver_Directory return String is
      Name    : constant String := Ada.Command_Line.Command_Name;
      Located : GNAT.OS_Lib.String_Access :=
        GNAT.OS_Lib.Locate_Exec_On_Path (Name);
   begin
      if GNAT.OS_Lib."=" (Located, null) then
         return Dirs.Containing_Directory (Dirs.Full_Name (Name));
      end if;

      declare
         Result : constant String :=
           Dirs.Containing_Directory (Dirs.Full_Name (Located.all));
      begin
         GNAT.OS_Lib.Free (Located);
         return Result;
      end;
   end Driver_Directory;

   --  Computed once, before any test changes the current directory.
   Bin_Dir     : constant String := Driver_Directory;
   Scratch_Dir : constant String := Dirs.Compose (Bin_Dir, "scratch");
   Golden_Dir  : constant String :=
     Dirs.Compose (Dirs.Containing_Directory (Bin_Dir), "golden");
   Program     : constant String :=
     Dirs.Compose (Bin_Dir, "lithophane")
     & GNAT.OS_Lib.Get_Executable_Suffix.all;

   procedure Assert_Near
     (Actual    : Float;
      Expected  : Float;
      What      : String;
      Tolerance : Float := 1.0e-4) is
   begin
      Assert
        (abs (Actual - Expected) <= Tolerance,
         What & ": expected" & Expected'Image & ", got" & Actual'Image);
   end Assert_Near;

   procedure Reset_Scratch is
   begin
      if Dirs.Exists (Scratch_Dir) then
         Dirs.Delete_Tree (Scratch_Dir);
      end if;
      Dirs.Create_Path (Scratch_Dir);
   end Reset_Scratch;

   function Scratch (Name : String) return String
   is (Dirs.Compose (Scratch_Dir, Name));

   function Golden (Name : String) return String
   is (Dirs.Compose (Golden_Dir, Name));

   function Exists (Path : String) return Boolean
   is (Dirs.Exists (Path));

   function Read_File (Path : String) return String is
      F : File_Type;
   begin
      Open (F, In_File, Path);
      declare
         Result : String (1 .. Natural (Size (F)));
      begin
         String'Read (Stream (F), Result);
         Close (F);
         return Result;
      end;
   end Read_File;

   procedure Write_File (Path : String; Content : String) is
      F : File_Type;
   begin
      Create (F, Out_File, Path);
      String'Write (Stream (F), Content);
      Close (F);
   end Write_File;

   procedure Delete_File (Path : String) is
   begin
      Dirs.Delete_File (Path);
   end Delete_File;

   function Contains (Text : String; Pattern : String) return Boolean
   is (Ada.Strings.Fixed.Index (Text, Pattern) /= 0);

   function Occurrences (Text : String; Pattern : String) return Natural
   is (Ada.Strings.Fixed.Count (Text, Pattern));

   function Without_CR (Text : String) return String is
      Result : String (1 .. Text'Length);
      Last   : Natural := 0;
   begin
      for C of Text loop
         if C /= ASCII.CR then
            Last := Last + 1;
            Result (Last) := C;
         end if;
      end loop;
      return Result (1 .. Last);
   end Without_CR;

   procedure Assert_Matches_Golden
     (Path : String; Name : String; Is_Text : Boolean)
   is
      function Load (File : String) return String
      is (if Is_Text then Without_CR (Read_File (File)) else Read_File (File));
   begin
      Assert (Exists (Path), Name & ": " & Path & " was not written");

      if Ada.Environment_Variables.Exists (Update_Golden_Variable) then
         Dirs.Copy_File (Path, Golden (Name));
         return;
      end if;

      Assert
        (Exists (Golden (Name)),
         "golden file "
         & Golden (Name)
         & " is missing; run the tests with "
         & Update_Golden_Variable
         & "=1 to create it");
      Assert
        (Load (Path) = Load (Golden (Name)),
         Path
         & " differs from the golden file "
         & Golden (Name)
         & "; if the change is intended, run the tests with "
         & Update_Golden_Variable
         & "=1");
   end Assert_Matches_Golden;

   procedure Write_Picture (Path : String) is
      Pixels : String (1 .. 3 * Picture_Width * Picture_Height) :=
        [others => Character'Val (0)];
      Next   : Positive := Pixels'First;
   begin
      for Row in 1 .. 2 loop
         for Column in 0 .. Picture_Width - 1 loop
            Pixels (Next .. Next + 2) :=
              [others => Character'Val (60 * Column)];
            Next := Next + 3;
         end loop;
      end loop;
      Write_File
        (Path,
         "P6" & ASCII.LF & "4 3" & ASCII.LF & "255" & ASCII.LF & Pixels);
   end Write_Picture;

   function Flat_Matrix
     (Width : Positive; Height : Positive; Grey : Grey_Type)
      return Matrix_Grey_Access
   is (new Matrix_Grey_Type'(1 .. Width => [1 .. Height => Grey]));

   function Run
     (Arguments : String; Merge_Stderr : Boolean := True) return Run_Result
   is
      Start_Dir : constant String := Dirs.Current_Directory;
      Log       : constant String := "run.log";
      Args      : GNAT.OS_Lib.Argument_List_Access :=
        GNAT.OS_Lib.Argument_String_To_List (Arguments);
      Success   : Boolean;
      Result    : Run_Result;
   begin
      Assert
        (Exists (Program),
         Program & " is missing; build the tests with ""alr build""");

      Dirs.Set_Directory (Scratch_Dir);
      GNAT.OS_Lib.Spawn
        (Program_Name => Program,
         Args         => Args.all,
         Output_File  => Log,
         Success      => Success,
         Return_Code  => Result.Status,
         Err_To_Out   => Merge_Stderr);
      GNAT.OS_Lib.Free (Args);

      if Success then
         Result.Output := SU.To_Unbounded_String (Read_File (Log));
         Dirs.Delete_File (Log);
      end if;
      Dirs.Set_Directory (Start_Dir);

      Assert (Success, "could not run " & Program & " " & Arguments);
      return Result;
   end Run;

   function Printed (Result : Run_Result; Pattern : String) return Boolean
   is (Contains (SU.To_String (Result.Output), Pattern));

end Test_Support;
