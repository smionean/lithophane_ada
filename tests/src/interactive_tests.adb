------------------------------------------------------------------------------
--  interactive_tests.adb
--
--  Copyright (c) 2026 Simon Beàn
--  SPDX-License-Identifier: MIT
--
--  Regression tests for the interactive mode (-i, --interactive): the
--  answers typed on the standard input must give the very files the
--  matching options of the command line give, and a wrong answer, the
--  choice 0 or the end of the input must stop the program before it writes
--  anything.
--
--  The questions come in this order: input file, threshold, filter (and
--  its size unless the filter is none), border, colour mode, file type
--  (black and white only), dimensions (3MF and colour only), maximum image
--  dimension and output name.
------------------------------------------------------------------------------

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with AUnit.Assertions; use AUnit.Assertions;

with GNAT.OS_Lib;

with Test_Support; use Test_Support;

package body Interactive_Tests is

   subtype Test_Case is AUnit.Test_Cases.Test_Case'Class;

   Picture        : constant String := "picture.ppm";
   Colour_Picture : constant String := "colour.ppm";

   --  Output names: the one answered to the program, the one given to the
   --  command line it is compared with, and the default one, which must
   --  never show up.
   Answered  : constant String := "out";
   Reference : constant String := "ref";
   Default   : constant String := "test";

   Binary_STL : constant String := ".bin.stl";
   ASCII_STL  : constant String := ".ascii.stl";
   File_3MF   : constant String := ".3mf";
   PGM        : constant String := ".pgm";

   Extensions : constant Text_List :=
     [+Binary_STL, +ASCII_STL, +File_3MF, +PGM];

   procedure Fresh_Scratch is
   begin
      Reset_Scratch;
      Write_Picture (Scratch (Picture));
      Write_Colour_Picture (Scratch (Colour_Picture));
   end Fresh_Scratch;

   overriding
   procedure Set_Up (T : in out Test) is
      pragma Unreferenced (T);
   begin
      Fresh_Scratch;
   end Set_Up;

   --  The blank separated Answers, one per line as the program reads them.
   --  A lone underscore stands for an empty line, which picks the default
   --  choice of a menu.
   function Typed (Answers : String) return String is
      Result : Unbounded_String;
      Start  : Positive := Answers'First;

      procedure Take (Word : String) is
      begin
         if Word /= "" then
            Append (Result, (if Word = "_" then "" else Word) & ASCII.LF);
         end if;
      end Take;
   begin
      for I in Answers'Range loop
         if Answers (I) = ' ' then
            Take (Answers (Start .. I - 1));
            Start := I + 1;
         end if;
      end loop;
      Take (Answers (Start .. Answers'Last));
      return To_String (Result);
   end Typed;

   --  Check that the program wrote the files named Name with the Expected
   --  extension and no other; none at all when Expected is empty.
   procedure Assert_Only (Name : String; Expected : String) is
   begin
      for Extension of Extensions loop
         Assert
           (Exists (Scratch (Name & To_String (Extension)))
            = (To_String (Extension) = Expected),
            Name
            & To_String (Extension)
            & (if To_String (Extension) = Expected
               then " is missing"
               else " should not exist"));
      end loop;
   end Assert_Only;

   --  Answer the questions that follow the input file with Answers, the
   --  output name excepted, and check that the only file written is the
   --  one with Extension, identical to the one the command line Options
   --  give for the same picture.
   procedure Check
     (Answers   : String;
      Options   : String;
      Extension : String;
      Switch    : String := "-i";
      Input     : String := Picture)
   is
      What   : constant String := Switch & " with the answers " & Answers;
      Result : Run_Result;
   begin
      Fresh_Scratch;
      Result := Run (Options & " -o " & Reference & " " & Input);
      Assert
        (Result.Status = 0,
         "lithophane " & Options & " failed: " & To_String (Result.Output));

      Result :=
        Run_With_Input
          (Switch, Typed (Input & " " & Answers & " " & Answered));
      Assert
        (Result.Status = 0,
         What
         & " failed with status"
         & Result.Status'Image
         & ": "
         & To_String (Result.Output));
      Assert_Only (Answered, Extension);
      Assert_Only (Default, "");
      Assert
        (Read_File (Scratch (Answered & Extension))
         = Read_File (Scratch (Reference & Extension)),
         What & " does not give the file of lithophane " & Options);
   end Check;

   --  Give the whole of Answers to the program, which is expected to print
   --  Message, to fail and to write no file.
   procedure Check_Stops (Answers : String; Message : String) is
      Result : Run_Result;
   begin
      Fresh_Scratch;
      Result := Run_With_Input ("-i", Typed (Answers));
      Assert
        (Result.Status /= 0, "-i with the answers " & Answers & " succeeded");
      Assert
        (Printed (Result, Message),
         "-i with the answers "
         & Answers
         & ": expected """
         & Message
         & """, got: "
         & To_String (Result.Output));
      Assert_Only (Answered, "");
      Assert_Only (Default, "");
      --  A run stopped before the output name is asked for has none.
      Assert_Only ("", "");
   end Check_Stops;

   procedure Check_Invalid (Answers : String) is
   begin
      Check_Stops (Answers, "Error: invalid answer");
   end Check_Invalid;

   procedure Check_Exit (Answers : String) is
   begin
      Check_Stops (Answers, "Exiting program");
   end Check_Exit;

   procedure Check_End_Of_Input (Answers : String) is
   begin
      Check_Stops
        (Answers,
         "Error: standard input ended before all the questions were"
         & " answered");
   end Check_End_Of_Input;

   procedure Switches (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      Check ("0.5 5 1 1 1 1500", "-b -B 1", Binary_STL, Switch => "-i");
      Check
        ("0.5 5 1 1 1 1500",
         "-b -B 1",
         Binary_STL,
         Switch => "--interactive");
   end Switches;

   --  The other options and the input file of the command line are not
   --  used.
   procedure Command_Line_Ignored (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      Check
        ("0.5 5 1 1 1 1500",
         "-b -B 1",
         Binary_STL,
         Switch => "-i -a -p -B 7 -o " & Default & " " & Colour_Picture);
      Check
        ("0.5 5 1 1 1 1500",
         "-b -B 1",
         Binary_STL,
         Switch => "-a " & Colour_Picture & " -i");
   end Command_Line_Ignored;

   procedure File_Types (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      Check ("0.5 5 1 1 1 1500", "-b -B 1", Binary_STL);
      Check ("0.5 5 1 1 2 1500", "-a -B 1", ASCII_STL);
      Check ("0.5 5 1 1 3 1 2 1500", "-m -B 1 -d 100x150x1.5", File_3MF);
   end File_Types;

   procedure Threshold_And_Border (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      Check ("0.3 5 1 1 1 1500", "-b -t 0.3 -B 1", Binary_STL);
      Check ("1.0 5 4 1 1 1500", "-b -t 1.0 -B 4", Binary_STL);
      Check ("0.0 5 20 1 1 1500", "-b -t 0.0 -B 20", Binary_STL);
      Check ("0.5 5 0 1 1 1500", "-b -B 0", Binary_STL);
   end Threshold_And_Border;

   procedure Filters (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      Check ("0.5 1 3 2 1 1 1500", "-b -B 2 -f bartlett 3", Binary_STL);
      Check ("0.5 2 5 2 1 1 1500", "-b -B 2 -f gauss 5", Binary_STL);
      Check ("0.5 3 3 2 1 1 1500", "-b -B 2 -f square 3", Binary_STL);
      Check ("0.5 4 3 2 1 1 1500", "-b -B 2 -f sharpen 3", Binary_STL);
      Check ("0.5 5 2 1 1 1500", "-b -B 2 -f none", Binary_STL);
   end Filters;

   procedure Dimensions (T : in out Test_Case) is
      pragma Unreferenced (T);

      procedure Check_Size (Answers : String; Size : String) is
      begin
         Check
           ("0.5 5 1 1 3 " & Answers & " 1500",
            "-m -B 1 -d " & Size,
            File_3MF);
      end Check_Size;
   begin
      --  Metric standard sizes.
      Check_Size ("1 1", "90x130x1.5");
      Check_Size ("1 2", "100x150x1.5");
      Check_Size ("1 3", "130x180x1.5");
      Check_Size ("1 4", "150x200x1.5");

      --  Imperial standard sizes.
      Check_Size ("2 1", "89x127x1.5");
      Check_Size ("2 2", "102x152x1.5");
      Check_Size ("2 3", "127x178x1.5");
      Check_Size ("2 4", "203x254x1.5");

      --  Custom dimensions: width, height and depth.
      Check_Size ("3 30 10 4", "30x10x4");
      Check_Size ("3 45.5 0 2.5", "45.5x0x2.5");
   end Dimensions;

   procedure Colour (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      --  No file type is asked for: a colour lithophane is a 3MF file.
      Check
        ("0.5 5 1 2 1 2 1500",
         "-C -B 1 -d 100x150x1.5",
         File_3MF,
         Input => Colour_Picture);
      Check
        ("0.5 5 1 2 3 30 20 1 1500",
         "-C -B 1 -d 30x20x1",
         File_3MF,
         Input => Colour_Picture);
   end Colour;

   procedure Max_Size (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      Check ("0.5 5 1 1 1 2", "-b -B 1 -M 2", Binary_STL);
      Check ("0.5 5 1 1 1 3", "-b -B 1 -M 3", Binary_STL);
      --  0 = no limit.
      Check ("0.5 5 1 1 1 0", "-b -B 1 -M 0", Binary_STL);
   end Max_Size;

   --  An empty answer picks the default choice of a menu: no filter, black
   --  and white, a 3MF file, the second metric or imperial size and 1500
   --  pixels at most.
   procedure Default_Answers (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      Check ("0.5 _ 1 _ _ _ _ _", "-m -B 1 -d 100x150x1.5", File_3MF);
      Check ("0.5 _ 1 _ _ 2 _ _", "-m -B 1 -d 102x152x1.5", File_3MF);
      Check ("0.5 _ 1 _ 1 _", "-b -B 1", Binary_STL);
   end Default_Answers;

   --  0 leaves the program from any menu.
   procedure Exit_Choice (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      Check_Exit (Picture & " 0.5 0 1 1 1 1500 " & Answered);
      Check_Exit (Picture & " 0.5 5 1 0 1 1500 " & Answered);
      Check_Exit (Picture & " 0.5 5 1 1 0 1500 " & Answered);
      Check_Exit (Picture & " 0.5 5 1 1 3 0 2 1500 " & Answered);
      Check_Exit (Picture & " 0.5 5 1 1 3 1 0 1500 " & Answered);
      Check_Exit (Picture & " 0.5 5 1 1 3 2 0 1500 " & Answered);
      Check_Exit (Colour_Picture & " 0.5 5 1 2 0 2 1500 " & Answered);
   end Exit_Choice;

   procedure Invalid_Answers (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      --  Threshold, which has an error message of its own.
      for Threshold of Text_List'[+"half", +"1.5", +"-0.5", +"_"] loop
         Check_Stops
           (Picture
            & " "
            & To_String (Threshold)
            & " 5 1 1 1 1500 "
            & Answered,
            "Error: invalid threshold");
      end loop;

      --  Filter and filter size.
      Check_Invalid (Picture & " 0.5 6 1 1 1 1500 " & Answered);
      Check_Invalid (Picture & " 0.5 gauss 1 1 1 1500 " & Answered);
      Check_Invalid (Picture & " 0.5 -1 1 1 1 1500 " & Answered);
      Check_Invalid (Picture & " 0.5 2 big 1 1 1 1500 " & Answered);
      Check_Invalid (Picture & " 0.5 2 4 1 1 1 1500 " & Answered);
      Check_Invalid (Picture & " 0.5 2 1 1 1 1 1500 " & Answered);
      Check_Invalid (Picture & " 0.5 2 0 1 1 1 1500 " & Answered);

      --  Border.
      Check_Invalid (Picture & " 0.5 5 wide 1 1 1500 " & Answered);
      Check_Invalid (Picture & " 0.5 5 -3 1 1 1500 " & Answered);
      Check_Invalid (Picture & " 0.5 5 _ 1 1 1500 " & Answered);

      --  Colour mode and file type.
      Check_Invalid (Picture & " 0.5 5 1 3 1 1500 " & Answered);
      Check_Invalid (Picture & " 0.5 5 1 grey 1 1500 " & Answered);
      Check_Invalid (Picture & " 0.5 5 1 1 4 1500 " & Answered);
      Check_Invalid (Picture & " 0.5 5 1 1 stl 1500 " & Answered);

      --  Dimensions.
      Check_Invalid (Picture & " 0.5 5 1 1 3 4 2 1500 " & Answered);
      Check_Invalid (Picture & " 0.5 5 1 1 3 1 5 1500 " & Answered);
      Check_Invalid (Picture & " 0.5 5 1 1 3 2 5 1500 " & Answered);
      Check_Invalid (Picture & " 0.5 5 1 1 3 3 wide 10 4 1500 " & Answered);
      Check_Invalid (Picture & " 0.5 5 1 1 3 3 30 high 4 1500 " & Answered);
      Check_Invalid (Picture & " 0.5 5 1 1 3 3 30 10 deep 1500 " & Answered);

      --  Maximum image dimension.
      Check_Invalid (Picture & " 0.5 5 1 1 1 large " & Answered);
      Check_Invalid (Picture & " 0.5 5 1 1 1 -1 " & Answered);
   end Invalid_Answers;

   --  The standard input may end at any question.
   procedure End_Of_Input (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      Check_End_Of_Input ("");
      Check_End_Of_Input (Picture);
      Check_End_Of_Input (Picture & " 0.5");
      Check_End_Of_Input (Picture & " 0.5 2");
      Check_End_Of_Input (Picture & " 0.5 5");
      Check_End_Of_Input (Picture & " 0.5 5 1");
      Check_End_Of_Input (Picture & " 0.5 5 1 1");
      Check_End_Of_Input (Picture & " 0.5 5 1 1 3");
      Check_End_Of_Input (Picture & " 0.5 5 1 1 3 1");
      Check_End_Of_Input (Picture & " 0.5 5 1 1 3 3 30 10");
      Check_End_Of_Input (Picture & " 0.5 5 1 1 3 1 2");
      Check_End_Of_Input (Picture & " 0.5 5 1 1 1 1500");
   end End_Of_Input;

   --  An empty output name keeps the default one.
   procedure Default_Output_Name (T : in out Test_Case) is
      pragma Unreferenced (T);
      Result : Run_Result;
   begin
      Result := Run ("-b -B 1 -o " & Reference & " " & Picture);
      Assert (Result.Status = 0, "the reference run failed");

      Result :=
        Run_With_Input ("-i", Typed (Picture & " 0.5 5 1 1 1 1500 _"));
      Assert
        (Result.Status = 0,
         "an empty output name failed: " & To_String (Result.Output));
      Assert
        (Printed (Result, "Output filename (default " & Default & ")"),
         "the default output name is not shown");
      Assert_Only (Default, Binary_STL);
      Assert_Only ("", "");
      Assert
        (Read_File (Scratch (Default & Binary_STL))
         = Read_File (Scratch (Reference & Binary_STL)),
         "an empty output name does not give the expected file");
   end Default_Output_Name;

   --  A terminal puts quotes around a file dropped on it, or a backslash
   --  before its blanks, and may add a blank after it: none of them is part
   --  of the name.
   procedure Quoted_File_Names (T : in out Test_Case) is
      pragma Unreferenced (T);

      LF      : constant Character := ASCII.LF;
      Spaced  : constant String := "my picture.ppm";
      Answers : constant String :=
        "0.5" & LF & "5" & LF & "1" & LF & "1" & LF & "1" & LF & "1500" & LF;

      procedure Check_Names (Input : String; Output : String; Name : String)
      is
         Result : Run_Result;
      begin
         Fresh_Scratch;
         Write_Picture (Scratch (Spaced));
         Result := Run ("-b -B 1 -o " & Reference & " " & Picture);
         Assert (Result.Status = 0, "the reference run failed");

         Result :=
           Run_With_Input ("-i", Input & LF & Answers & Output & LF);
         Assert
           (Result.Status = 0,
            "the file names "
            & Input
            & " and "
            & Output
            & " failed: "
            & To_String (Result.Output));
         Assert_Only (Name, Binary_STL);
         Assert
           (Read_File (Scratch (Name & Binary_STL))
            = Read_File (Scratch (Reference & Binary_STL)),
            "the file names "
            & Input
            & " and "
            & Output
            & " do not give the expected file");
      end Check_Names;
   begin
      Check_Names ("'" & Picture & "'", "'" & Answered & "'", Answered);
      Check_Names ("""" & Picture & """", """" & Answered & """", Answered);
      Check_Names ("'" & Spaced & "'", "'my out'", "my out");
      Check_Names (" '" & Spaced & "' ", "  " & Answered & " ", Answered);
      Check_Names (Spaced, Answered, Answered);
      --  Quotes that are not a pair around the name belong to it.
      Check_Names (Picture, "it's", "it's");
      Check_Names (Picture, "'" & Answered, "'" & Answered);
      --  An empty pair of quotes is an empty answer: the default name.
      Check_Names (Picture, "''", Default);

      --  Backslashes escape the next character, except inside quotes and
      --  where they separate directories.
      if GNAT.OS_Lib.Directory_Separator /= '\' then
         Check_Names ("my\ picture.ppm", "my\ out", "my out");
         Check_Names ("my\ picture.ppm ", "it\'s\ \(1\)", "it's (1)");
         Check_Names (Picture, "a\\b", "a\b");
         Check_Names (Picture, "'a\ b'", "a\ b");
         Check_Names (Picture, Answered & "\", Answered & "\");
      end if;
   end Quoted_File_Names;

   procedure Missing_Input_File (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      Check_Stops
        ("missing.ppm 0.5 5 1 1 1 1500 " & Answered,
         "Error: cannot open input image file ""missing.ppm""");
   end Missing_Input_File;

   overriding
   procedure Register_Tests (T : in out Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Switches'Access, "-i and --interactive");
      Register_Routine
        (T,
         Command_Line_Ignored'Access,
         "the rest of the command line is ignored");
      Register_Routine
        (T, File_Types'Access, "STL binary, STL ASCII and 3MF");
      Register_Routine
        (T, Threshold_And_Border'Access, "threshold and border");
      Register_Routine (T, Filters'Access, "filters, with a size");
      Register_Routine
        (T, Dimensions'Access, "metric, imperial and custom dimensions");
      Register_Routine (T, Colour'Access, "colour lithophane");
      Register_Routine (T, Max_Size'Access, "maximum image dimension");
      Register_Routine
        (T, Default_Answers'Access, "empty answers pick the defaults");
      Register_Routine
        (T,
         Default_Output_Name'Access,
         "an empty output name keeps the default");
      Register_Routine
        (T, Quoted_File_Names'Access, "quotes and blanks around file names");
      Register_Routine (T, Exit_Choice'Access, "0 leaves the program");
      Register_Routine (T, Invalid_Answers'Access, "invalid answers");
      Register_Routine (T, End_Of_Input'Access, "end of the standard input");
      Register_Routine (T, Missing_Input_File'Access, "missing input file");
   end Register_Tests;

end Interactive_Tests;
