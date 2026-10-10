------------------------------------------------------------------------------
--  command_line_tests.adb
--
--  Copyright (c) 2026 Simon Beàn
--  SPDX-License-Identifier: MIT
--
--  Regression tests for the lithophane program as a whole: every option of
--  the command line, in each of its spellings, the files it writes and the
--  errors it reports.
------------------------------------------------------------------------------

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with AUnit.Assertions; use AUnit.Assertions;

with Lithophane_Config;
with Test_Support;        use Test_Support;
with Test_Support.Meshes; use Test_Support.Meshes;

package body Command_Line_Tests is

   subtype Test_Case is AUnit.Test_Cases.Test_Case'Class;

   LF : constant Character := ASCII.LF;

   Picture : constant String := "picture.ppm";

   --  The picture without border nor threshold, as --save-pgm writes it.
   Picture_PGM : constant String :=
     "P2"
     & LF
     & " 4  3"
     & LF
     & "255"
     & LF
     & " 0 60 120 180"
     & LF
     & " 0 60 120 180"
     & LF
     & " 0 0 0 0"
     & LF;

   Binary_STL : constant String := ".bin.stl";
   ASCII_STL  : constant String := ".ascii.stl";
   File_3MF   : constant String := ".3mf";
   PGM        : constant String := ".pgm";

   procedure Fresh_Scratch is
   begin
      Reset_Scratch;
      Write_Picture (Scratch (Picture));
   end Fresh_Scratch;

   overriding
   procedure Set_Up (T : in out Test) is
      pragma Unreferenced (T);
   begin
      Fresh_Scratch;
   end Set_Up;

   --  Run the program, which is expected to succeed.
   procedure Run_OK (Arguments : String) is
      Result : constant Run_Result := Run (Arguments);
   begin
      Assert
        (Result.Status = 0,
         "lithophane "
         & Arguments
         & " failed with status"
         & Result.Status'Image
         & ": "
         & To_String (Result.Output));
   end Run_OK;

   --  Run the program, which is expected to report Message, to fail and to
   --  write no file.
   procedure Run_Error (Arguments : String; Message : String) is
      Outputs : constant Text_List :=
        [+Binary_STL, +ASCII_STL, +File_3MF, +PGM];
      Result  : Run_Result;
   begin
      for Extension of Outputs loop
         if Exists (Scratch ("test" & To_String (Extension))) then
            Delete_File (Scratch ("test" & To_String (Extension)));
         end if;
      end loop;

      Result := Run (Arguments);
      Assert
        (Result.Status /= 0,
         "lithophane " & Arguments & " did not fail");
      Assert
        (Printed (Result, "Error: " & Message),
         "lithophane "
         & Arguments
         & ": expected the error """
         & Message
         & """, got: "
         & To_String (Result.Output));
      for Extension of Outputs loop
         Assert
           (not Exists (Scratch ("test" & To_String (Extension))),
            "lithophane "
            & Arguments
            & " wrote test"
            & To_String (Extension));
      end loop;
   end Run_Error;

   --  Check which of the files named Name exist.
   procedure Assert_Outputs
     (Name : String; Binary, ASCII, File_3MF, PGM : Boolean := False)
   is
      procedure Check (Extension : String; Expected : Boolean) is
      begin
         Assert
           (Exists (Scratch (Name & Extension)) = Expected,
            Name
            & Extension
            & (if Expected then " is missing" else " should not exist"));
      end Check;
   begin
      Check (Binary_STL, Binary);
      Check (ASCII_STL, ASCII);
      Check (Command_Line_Tests.File_3MF, File_3MF);
      Check (Command_Line_Tests.PGM, PGM);
   end Assert_Outputs;

   --  The bounding box of the binary STL written by the program.
   function STL_Box (Name : String := "test") return Box
   is (Bounding_Box (Read_Binary_STL (Scratch (Name & Binary_STL))));

   procedure Assert_Help (Arguments : String) is
      --  The help goes to standard output.
      Result : constant Run_Result := Run (Arguments, Merge_Stderr => False);
   begin
      Assert (Result.Status = 0, "lithophane " & Arguments & " failed");
      Assert
        (Printed (Result, "Usage: lithophane [options] <input_file>"),
         "lithophane " & Arguments & " did not print the usage");
      for Option of Text_List'[+"--help",
         +"--version",
         +"--save-stl-binary",
         +"--save-stl-ascii",
         +"--save-3mf",
         +"--save-pgm",
         +"--colour",
         +"--output-name",
         +"--height",
         +"--border",
         +"--dimensions",
         +"--filter",
         +"--threshold",
         +"--max-size",
         +"--config",
         +"--interactive"]
      loop
         Assert
           (Printed (Result, To_String (Option)),
            "the help does not mention " & To_String (Option));
      end loop;
      Assert_Outputs ("test");
   end Assert_Help;

   procedure Help (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      Assert_Help ("");
      Assert_Help ("-h");
      Assert_Help ("--help");
      Assert_Help ("-?");
      --  Nothing is generated once the help is asked for.
      Assert_Help ("-a " & Picture & " -h");
   end Help;

   procedure Version (T : in out Test_Case) is
      pragma Unreferenced (T);
      Expected : constant String :=
        "Lithophane " & Lithophane_Config.Crate_Version & LF;
   begin
      for Option of Text_List'[+"-v", +"--version"]
      loop
         declare
            Result : constant Run_Result :=
              Run (To_String (Option) & " " & Picture);
         begin
            Assert (Result.Status = 0, To_String (Option) & " failed");
            Assert
              (Without_CR (To_String (Result.Output)) = Expected,
               To_String (Option)
               & " printed """
               & To_String (Result.Output)
               & """ instead of the version of alire.toml");
         end;
      end loop;
      Assert_Outputs ("test");
   end Version;

   procedure Default_Output (T : in out Test_Case) is
      pragma Unreferenced (T);
      Size : Box;
   begin
      Run_OK (Picture);
      Assert_Outputs ("test", Binary => True);

      --  A border of 20 pixels around the 4 x 3 picture, one unit per
      --  pixel, a relief of 10 on a base of 2.
      Size := STL_Box;
      Assert_Near (Size.Max.px - Size.Min.px, 43.0, "width");
      Assert_Near (Size.Max.py - Size.Min.py, 42.0, "height");
      Assert_Near (Size.Min.pz, -2.0, "base");
      Assert_Near (Size.Max.pz, 10.0, "relief");
      Assert
        (Open_Edges (Read_Binary_STL (Scratch ("test" & Binary_STL))) = 0,
         "the mesh is not closed");
   end Default_Output;

   procedure Output_Formats (T : in out Test_Case) is
      pragma Unreferenced (T);

      procedure Check
        (Options : String; ASCII, File_3MF, PGM : Boolean := False) is
      begin
         Fresh_Scratch;
         Run_OK (Options & " " & Picture);
         --  The binary STL is always written.
         Assert_Outputs ("test", True, ASCII, File_3MF, PGM);
      end Check;
   begin
      Check ("-b");
      Check ("--save-stl-binary");
      Check ("--save-binary");
      Check ("-a", ASCII => True);
      Check ("--save-stl-ascii", ASCII => True);
      Check ("--save-ascii", ASCII => True);
      Check ("-m", File_3MF => True);
      Check ("--save-3mf", File_3MF => True);
      Check ("-p", PGM => True);
      Check ("--save-pgm", PGM => True);
      Check ("-a -m -p", True, True, True);
      Check ("-amp", True, True, True);
      Check ("--save-stl-ascii --save-3mf --save-pgm", True, True, True);
   end Output_Formats;

   --  A colour lithophane is a 3MF file made of one part per filament; no
   --  STL file is written, whatever else is asked for.
   procedure Colour (T : in out Test_Case) is
      pragma Unreferenced (T);

      procedure Check (Arguments : String; PGM : Boolean := False) is
      begin
         Run_OK (Arguments);
         Assert_Outputs ("test", File_3MF => True, PGM => PGM);
         declare
            XML : constant String :=
              To_String (Read_Zip (Scratch ("test.3mf")) (3).Data);
         begin
            for Part of Text_List'[+"white back",
               +"cyan",
               +"magenta",
               +"yellow",
               +"white"]
            loop
               Assert
                 (Contains
                    (XML, "name=""" & To_String (Part) & """ type=""model"""),
                  Arguments & ": no " & To_String (Part) & " part");
            end loop;
            Assert
              (Occurrences (XML, "<component ") = 5,
               Arguments & ": the parts are not assembled");
         end;
         Delete_File (Scratch ("test.3mf"));
         if PGM then
            Delete_File (Scratch ("test.pgm"));
         end if;
      end Check;
   begin
      Write_Colour_Picture (Scratch (Picture));
      Check ("-C " & Picture);
      Check ("--colour " & Picture);
      Check (Picture & " -C");
      Check ("-C -m " & Picture);
      Check ("-C -a -b " & Picture);
      Check ("-Cp " & Picture, PGM => True);
      Write_File (Scratch ("config.toml"), "colour = true" & LF);
      Check ("-c config.toml " & Picture);

      --  The height map is the black of the picture: 0 for a pure colour.
      Run_OK ("-C -p -B 0 -t 0 " & Picture);
      Assert
        (Without_CR (Read_File (Scratch ("test.pgm")))
         = "P2"
           & LF
           & " 4  3"
           & LF
           & "255"
           & LF
           & " 255 255 255 255"
           & LF
           & " 204 102 255 0"
           & LF
           & " 255 255 255 255"
           & LF,
         "unexpected height map: " & Read_File (Scratch ("test.pgm")));

      --  A picture without colour gives the white parts alone.
      Fresh_Scratch;
      Run_OK ("-C " & Picture);
      declare
         XML : constant String :=
           To_String (Read_Zip (Scratch ("test.3mf")) (3).Data);
      begin
         Assert
           (Occurrences (XML, "<mesh>") = 2
            and then Contains (XML, "name=""white back""")
            and then Contains (XML, "name=""white"""),
            "expected the white parts alone for a grey picture");
      end;
   end Colour;

   procedure Output_Name (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      Run_OK ("-o short -a " & Picture);
      Run_OK ("-oattached -a " & Picture);
      Run_OK ("--output-name=long -a " & Picture);
      Run_OK ("--output-name separate -a " & Picture);
      Assert_Outputs ("short", Binary => True, ASCII => True);
      Assert_Outputs ("attached", Binary => True, ASCII => True);
      Assert_Outputs ("long", Binary => True, ASCII => True);
      Assert_Outputs ("separate", Binary => True, ASCII => True);
      Assert_Outputs ("test");
   end Output_Name;

   procedure Height (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      for Option of Text_List'[+"-H 5",
         +"-H5",
         +"--height=5",
         +"--height 5",
         +"-H 5.0",
         +"-H 9 -H 5"]
      loop
         Fresh_Scratch;
         Run_OK (To_String (Option) & " " & Picture);
         Assert_Near (STL_Box.Max.pz, 5.0, To_String (Option) & ": relief");
         Assert_Near (STL_Box.Min.pz, -2.0, To_String (Option) & ": base");
      end loop;

      Run_Error ("-H 0 " & Picture, "invalid height value ""0""");
      Run_Error ("-H -3 " & Picture, "invalid height value ""-3""");
      Run_Error ("--height=tall " & Picture, "invalid height value ""tall""");
   end Height;

   procedure Border (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      for Option of Text_List'[+"-B 2",
         +"-B2",
         +"--border=2",
         +"--border 2"]
      loop
         Fresh_Scratch;
         Run_OK (To_String (Option) & " " & Picture);
         Assert_Near
           (STL_Box.Max.px - STL_Box.Min.px, 7.0, To_String (Option) & ": X");
         Assert_Near
           (STL_Box.Max.py - STL_Box.Min.py, 6.0, To_String (Option) & ": Y");
      end loop;

      Run_OK ("-B 0 " & Picture);
      Assert_Near (STL_Box.Max.px - STL_Box.Min.px, 3.0, "no border: X");
      Assert_Near (STL_Box.Max.py - STL_Box.Min.py, 2.0, "no border: Y");

      Fresh_Scratch;
      Run_Error ("-B -1 " & Picture, "invalid border value ""-1""");
      Run_Error ("--border=wide " & Picture, "invalid border value ""wide""");
   end Border;

   procedure Max_Size (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      --  With a border of 1 the image is 6 x 5 pixels.
      for Option of Text_List'[+"-M 4",
         +"-M4",
         +"--max-size=4",
         +"--max-size 4"]
      loop
         Fresh_Scratch;
         Run_OK ("-B 1 " & To_String (Option) & " " & Picture);
         Assert_Near
           (STL_Box.Max.px - STL_Box.Min.px, 3.0, To_String (Option) & ": X");
         Assert_Near
           (STL_Box.Max.py - STL_Box.Min.py, 2.0, To_String (Option) & ": Y");
      end loop;

      --  0 is no limit, and an image that fits is left as it is.
      for Option of Text_List'[+"-M 0",
         +"-M 6",
         +"-M 100"]
      loop
         Fresh_Scratch;
         Run_OK ("-B 1 " & To_String (Option) & " " & Picture);
         Assert_Near
           (STL_Box.Max.px - STL_Box.Min.px, 5.0, To_String (Option) & ": X");
         Assert_Near
           (STL_Box.Max.py - STL_Box.Min.py, 4.0, To_String (Option) & ": Y");
      end loop;

      Fresh_Scratch;
      Run_Error ("-M -1 " & Picture, "invalid max-size value ""-1""");
      Run_Error
        ("--max_size=4 " & Picture,
         "invalid command line switch: --max_size");
   end Max_Size;

   procedure Greyscale_Image (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      Run_OK ("-p -B 0 -t 0 " & Picture);
      Assert
        (Without_CR (Read_File (Scratch ("test" & PGM))) = Picture_PGM,
         "unexpected PGM file: " & Read_File (Scratch ("test" & PGM)));

      --  The PGM holds the border too.
      Run_OK ("-p -B 2 -t 0 -o border " & Picture);
      Assert
        (Contains
           (Without_CR (Read_File (Scratch ("border" & PGM))),
            "P2" & LF & " 8  7" & LF & "255" & LF),
         "the PGM file is not 8 x 7 pixels with a border of 2");
   end Greyscale_Image;

   procedure Threshold (T : in out Test_Case) is
      pragma Unreferenced (T);

      --  The first row of the picture once the threshold is applied.
      procedure Check (Options : String; Row : String) is
      begin
         Fresh_Scratch;
         Run_OK ("-p -B 0 " & Options & " " & Picture);
         Assert
           (Contains
              (Without_CR (Read_File (Scratch ("test" & PGM))),
               "255" & LF & Row & LF),
            Options
            & ": expected the row """
            & Row
            & """ in "
            & Read_File (Scratch ("test" & PGM)));
      end Check;
   begin
      --  The pixels whose height is below the threshold are cut to 0.0,
      --  i.e. to white: by default (0.5) the grey 180 is.
      Check ("", " 0 60 120 255");
      Check ("-t 0", " 0 60 120 180");
      Check ("-t0", " 0 60 120 180");
      Check ("-t 0.6", " 0 60 255 255");
      Check ("--threshold=0.6", " 0 60 255 255");
      Check ("--threshold 0.6", " 0 60 255 255");
      Check ("-t 1", " 0 255 255 255");

      Run_Error ("-t 1.5 " & Picture, "invalid threshold value ""1.5""");
      Run_Error ("-t -0.5 " & Picture, "invalid threshold value ""-0.5""");
   end Threshold;

   procedure Filter (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      for Option of Text_List'[+"-f sharpen",
         +"-fsharpen",
         +"--filter=sharpen",
         +"--filter sharpen",
         +"--filter sharpen 5",
         +"-f sharpen 3",
         +"--filter SHARPEN",
         +"--filter bartlett",
         +"--filter gauss 7",
         +"--filter square",
         +"--filter none"]
      loop
         Fresh_Scratch;
         Run_OK (To_String (Option) & " " & Picture);
         Assert_Outputs ("test", Binary => True);
      end loop;

      --  The filter is applied to the image: on this one, sharpen with a
      --  kernel of 3 moves the pixels next to the black row.
      Fresh_Scratch;
      Run_OK ("-p -B 0 -t 0 --filter sharpen " & Picture);
      Assert
        (Without_CR (Read_File (Scratch ("test" & PGM))) /= Picture_PGM,
         "sharpen left the image unchanged");
      Run_OK ("-p -B 0 -t 0 --filter none -o none " & Picture);
      Assert
        (Without_CR (Read_File (Scratch ("none" & PGM))) = Picture_PGM,
         "the filter none changed the image");

      Fresh_Scratch;
      Run_Error ("-f blur " & Picture, "unknown filter ""blur""");
      Run_Error
        ("--filter gauss 4 " & Picture, "invalid filter size ""4""");
      Run_Error
        ("--filter gauss 1 " & Picture, "invalid filter size ""1""");
   end Filter;

   procedure Dimensions (T : in out Test_Case) is
      pragma Unreferenced (T);

      --  Size of the 3MF model of the picture without border (3 x 2
      --  units) and a relief of 3 (5 with the base).
      procedure Check (Options : String; Width, Height, Depth : Float) is
         Size : Box;
      begin
         Fresh_Scratch;
         Run_OK ("-m -B 0 -H 3 " & Options & " " & Picture);
         Size := Bounding_Box (Read_3MF (Scratch ("test" & File_3MF)));
         Assert_Near
           (Size.Max.px - Size.Min.px, Width, Options & ": width", 1.0e-3);
         Assert_Near
           (Size.Max.py - Size.Min.py, Height, Options & ": height", 1.0e-3);
         Assert_Near
           (Size.Max.pz - Size.Min.pz, Depth, Options & ": depth", 1.0e-3);

         --  The STL is never scaled.
         Assert_Near (STL_Box.Max.px - STL_Box.Min.px, 3.0, "STL width");
         Assert_Near (STL_Box.Max.pz, 3.0, "STL relief");
      end Check;
   begin
      Check ("", 3.0, 2.0, 5.0);
      Check ("-d 30x10x4", 30.0, 10.0, 4.0);
      Check ("-d30x10x4", 30.0, 10.0, 4.0);
      Check ("--dimensions=30x10x4", 30.0, 10.0, 4.0);
      Check ("--dimensions 30x10x4", 30.0, 10.0, 4.0);
      Check ("-d 30X10X1.5", 30.0, 10.0, 1.5);
      Check ("-d 30x0x0", 30.0, 20.0, 5.0);
      Check ("-d 30xx", 30.0, 20.0, 5.0);
      Check ("-d 30", 30.0, 20.0, 5.0);
      Check ("-d 0x30x0", 45.0, 30.0, 5.0);
      Check ("-d x30", 45.0, 30.0, 5.0);
      Check ("-d 30x0x4", 30.0, 20.0, 4.0);

      Fresh_Scratch;
      Run_Error ("-d 1x2x3x4 " & Picture, "invalid dimensions ""1x2x3x4""");
      Run_Error ("-d wide " & Picture, "invalid dimensions ""wide""");
      Run_Error ("-d -10x10x1 " & Picture, "invalid dimensions ""-10x10x1""");
   end Dimensions;

   --  A depth in --dimensions overrides an explicit --height in the 3MF
   --  file: the user is warned.
   procedure Depth_Overrides_Height_Warning (T : in out Test_Case) is
      pragma Unreferenced (T);
      Warning : constant String :=
        "Warning: the depth given in --dimensions overrides --height";

      procedure Check (Options : String; Expected : Boolean) is
         Result : constant Run_Result := Run (Options & " " & Picture);
      begin
         Assert (Result.Status = 0, "lithophane " & Options & " failed");
         Assert
           (Printed (Result, Warning) = Expected,
            Options
            & (if Expected
               then ": no warning"
               else ": unexpected warning"));
      end Check;
   begin
      Check ("-m -H 3 -d 30x0x4", True);
      Check ("-m -d 30x0x4", False);
      Check ("-m -H 3 -d 30x0x0", False);
      Check ("-H 3 -d 30x0x4", False);
   end Depth_Overrides_Height_Warning;

   --  A short option whose value is attached must not disturb the options
   --  that follow it.
   procedure Options_After_An_Attached_Value (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      Run_OK ("-H5 -a -B2 -p -ojoined -m " & Picture);
      Assert_Outputs ("joined", True, True, True, True);
      Assert_Near (STL_Box ("joined").Max.pz, 5.0, "relief");
      Assert_Near
        (STL_Box ("joined").Max.px - STL_Box ("joined").Min.px, 7.0, "width");
   end Options_After_An_Attached_Value;

   procedure Options_After_The_Input_File (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      Run_OK (Picture & " -a -H 5 --border=2");
      Assert_Outputs ("test", Binary => True, ASCII => True);
      Assert_Near (STL_Box.Max.pz, 5.0, "relief");
      Assert_Near (STL_Box.Max.px - STL_Box.Min.px, 7.0, "width");
   end Options_After_The_Input_File;

   procedure Invalid_Command_Lines (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      Run_Error ("-z " & Picture, "invalid command line switch: -z");
      Run_Error
        ("--bogus " & Picture, "invalid command line switch: --bogus");
      Run_Error
        ("--bogus=1 " & Picture, "invalid command line switch: --bogus");
      Run_Error
        ("--save-pgm=1 " & Picture,
         "invalid command line switch: --save-pgm (it takes no parameter)");
      Run_Error (Picture & " -o", "missing parameter for switch: -o");
      Run_Error
        (Picture & " --height", "missing parameter for switch: --height");
      Run_Error
        ("--height -a " & Picture, "missing parameter for switch: --height");
      Run_Error
        (Picture & " other.ppm",
         "more than one input image file given: """
         & Picture
         & """ and ""other.ppm""");
      Run_Error ("-a -m", "no input image file given.");
   end Invalid_Command_Lines;

   procedure Invalid_Input_Files (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      Run_Error
        ("missing.png",
         "cannot open input image file ""missing.png"" (no such file)");

      Write_File (Scratch ("notes.txt"), "This is not a picture." & LF);
      Run_Error
        ("notes.txt",
         """notes.txt"" is not in an image format GID recognises");
   end Invalid_Input_Files;

   --  A config file that cannot be loaded stops the program, wherever -c
   --  stands.
   procedure Invalid_Config_Files (T : in out Test_Case) is
      pragma Unreferenced (T);
      Missing : constant String :=
        "cannot load config file ""missing.toml""";
   begin
      Run_Error ("-c missing.toml " & Picture, Missing);
      Run_Error (Picture & " -c missing.toml", Missing);
      Run_Error ("-a --config=missing.toml " & Picture, Missing);

      Write_File (Scratch ("broken.toml"), "this is not TOML" & LF);
      Run_Error
        ("-c broken.toml " & Picture,
         "cannot load config file ""broken.toml""");
   end Invalid_Config_Files;

   procedure Config_File (T : in out Test_Case) is
      pragma Unreferenced (T);
      Config : constant String :=
        "input-name = """
        & Picture
        & """"
        & LF
        & "output-name = ""configured"""
        & LF
        & "save-ascii = true"
        & LF
        & "border_size = 2"
        & LF
        & "height = 4.0"
        & LF;
   begin
      for Option of Text_List'[+"-c config.toml",
         +"-cconfig.toml",
         +"--config=config.toml",
         +"--config config.toml"]
      loop
         Fresh_Scratch;
         Write_File (Scratch ("config.toml"), Config);
         Run_OK (To_String (Option));
         Assert_Outputs ("configured", Binary => True, ASCII => True);
         Assert_Near
           (STL_Box ("configured").Max.pz, 4.0, To_String (Option) & ": Z");
         Assert_Near
           (STL_Box ("configured").Max.px - STL_Box ("configured").Min.px,
            7.0,
            To_String (Option) & ": X");
      end loop;
   end Config_File;

   --  The config file has the last word: its keys override the matching
   --  arguments of the command line, before or after -c. The command line
   --  decides for the keys the file leaves out.
   procedure Config_File_And_Options (T : in out Test_Case) is
      pragma Unreferenced (T);

      procedure Check (Arguments : String) is
      begin
         Fresh_Scratch;
         Write_File
           (Scratch ("config.toml"),
            "input-name = """
            & Picture
            & """"
            & LF
            & "output-name = ""configured"""
            & LF
            & "save-binary = false"
            & LF
            & "height = 4.0"
            & LF);
         Run_OK (Arguments);

         --  From the file: the name, no binary STL, the height. From the
         --  command line: the ASCII STL and the border (in the PGM).
         Assert_Outputs ("configured", ASCII => True, PGM => True);
         Assert_Outputs ("named");
         Assert
           (Contains
              (Read_File (Scratch ("configured" & ASCII_STL)),
               " 4.00000E+00" & LF),
            Arguments & ": the relief is not 4 high");
         Assert
           (not Contains
              (Read_File (Scratch ("configured" & ASCII_STL)), " 7.00000E+00"),
            Arguments & ": the height of the command line was used");
         Assert
           (Contains
              (Without_CR (Read_File (Scratch ("configured" & PGM))),
               "P2" & LF & " 6  5" & LF),
            Arguments & ": the border of the command line was not used");
      end Check;
   begin
      Check ("-b -a -p -B 1 -H 7 -o named missing.png -c config.toml");
      Check ("-c config.toml -b -a -p -B 1 -H 7 -o named missing.png");
      Check ("-b -a -H 7 -c config.toml -p -B 1 -o named");

      --  The input file of the command line is used when the config file
      --  names none, on either side of -c.
      Fresh_Scratch;
      Write_File
        (Scratch ("config.toml"), "output-name = ""configured""" & LF);
      Run_OK (Picture & " -c config.toml");
      Assert_Outputs ("configured", Binary => True);
      Fresh_Scratch;
      Write_File
        (Scratch ("config.toml"), "output-name = ""configured""" & LF);
      Run_OK ("-c config.toml " & Picture);
      Assert_Outputs ("configured", Binary => True);
   end Config_File_And_Options;

   overriding
   procedure Register_Tests (T : in out Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Help'Access, "-h, --help, -? and no argument");
      Register_Routine (T, Version'Access, "-v and --version");
      Register_Routine
        (T, Default_Output'Access, "a picture alone gives test.bin.stl");
      Register_Routine
        (T, Output_Formats'Access, "-b, -a, -m, -p and their long forms");
      Register_Routine
        (T, Colour'Access, "-C and --colour give a 3MF file of parts");
      Register_Routine (T, Output_Name'Access, "-o and --output-name");
      Register_Routine (T, Height'Access, "-H and --height");
      Register_Routine (T, Border'Access, "-B and --border");
      Register_Routine (T, Max_Size'Access, "-M and --max-size");
      Register_Routine (T, Greyscale_Image'Access, "PGM file of the picture");
      Register_Routine (T, Threshold'Access, "-t and --threshold");
      Register_Routine (T, Filter'Access, "-f and --filter, with a size");
      Register_Routine (T, Dimensions'Access, "-d and --dimensions");
      Register_Routine
        (T,
         Depth_Overrides_Height_Warning'Access,
         "warning when a depth overrides --height");
      Register_Routine
        (T,
         Options_After_An_Attached_Value'Access,
         "options after a short option with an attached value");
      Register_Routine
        (T,
         Options_After_The_Input_File'Access,
         "options after the input file");
      Register_Routine
        (T, Invalid_Command_Lines'Access, "invalid command lines");
      Register_Routine (T, Invalid_Input_Files'Access, "invalid input files");
      Register_Routine
        (T, Invalid_Config_Files'Access, "missing or malformed config file");
      Register_Routine (T, Config_File'Access, "-c and --config");
      Register_Routine
        (T,
         Config_File_And_Options'Access,
         "a config file overrides the command line");
   end Register_Tests;

end Command_Line_Tests;
