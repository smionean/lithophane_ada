------------------------------------------------------------------------------
--  config_tests.adb
--
--  Copyright (c) 2026 Simon Beàn
--  SPDX-License-Identifier: MIT
--
--  Regression tests for Lithophane.Parse_Config: the keys of the TOML file
--  override the settings, a missing or invalid key keeps its value, a
--  file that cannot be loaded is an error.
------------------------------------------------------------------------------

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with AUnit.Assertions; use AUnit.Assertions;

with Lithophane;   use Lithophane;
with Test_Support; use Test_Support;

package body Config_Tests is

   subtype Test_Case is AUnit.Test_Cases.Test_Case'Class;

   LF : constant Character := ASCII.LF;

   --  The settings once a config file holding Content has been read.
   function Parsed (Content : String) return Settings_Record is
      File     : constant String := Scratch ("config.toml");
      Settings : Settings_Record;
   begin
      Reset_Scratch;
      Write_File (File, Content);
      Settings.config := To_Unbounded_String (File);
      Parse_Config (Settings);
      return Settings;
   end Parsed;

   --  The settings as they are before a config file is read.
   function Defaults return Settings_Record is
      Settings : Settings_Record;
   begin
      Settings.config := To_Unbounded_String (Scratch ("config.toml"));
      return Settings;
   end Defaults;

   procedure Every_Key (T : in out Test_Case) is
      pragma Unreferenced (T);
      Settings : constant Settings_Record :=
        Parsed
          ("input-name = ""picture.png"""
           & LF
           & "output-name = ""result"""
           & LF
           & "filter = ""sharpen"""
           & LF
           & "filter_size = 5"
           & LF
           & "filter_threshold = 0.25"
           & LF
           & "border_size = 7"
           & LF
           & "save-ascii = true"
           & LF
           & "save-binary = false"
           & LF
           & "save-3mf = true"
           & LF
           & "save-pgm = true"
           & LF
           & "colour = true"
           & LF
           & "height = 4.5"
           & LF
           & "max_size = 800"
           & LF
           & "dimensions = { width = 100.0, height = 80.0, depth = 1.5 }"
           & LF);
   begin
      Assert (To_String (Settings.filename) = "picture.png", "input-name");
      Assert (To_String (Settings.outfilename) = "result", "output-name");
      Assert (Settings.filter = sharpen, "filter");
      Assert (Settings.filter_size = 5, "filter_size");
      Assert_Near (Float (Settings.filter_threshold), 0.25, "threshold");
      Assert (Settings.border = 7, "border_size");
      Assert (Settings.save_as_ascii, "save-ascii");
      Assert (not Settings.save_as_binary, "save-binary");
      Assert (Settings.save_as_3mf, "save-3mf");
      Assert (Settings.save_pgm, "save-pgm");
      Assert (Settings.colour, "colour");
      Assert_Near (Settings.height, 4.5, "height");
      Assert (Settings.height_is_set, "height is not flagged as given");
      Assert (Settings.max_size = 800, "max_size");
      Assert_Near (Settings.dimensions.width, 100.0, "dimensions.width");
      Assert_Near (Settings.dimensions.height, 80.0, "dimensions.height");
      Assert_Near (Settings.dimensions.depth, 1.5, "dimensions.depth");
   end Every_Key;

   procedure Missing_Keys_Keep_Their_Value (T : in out Test_Case) is
      pragma Unreferenced (T);
      Settings : constant Settings_Record := Parsed ("border_size = 3" & LF);
      Expected : Settings_Record := Defaults;
   begin
      Expected.border := 3;
      Assert (Settings = Expected, "another setting than border has changed");
      Assert (not Settings.height_is_set, "height is flagged as given");
   end Missing_Keys_Keep_Their_Value;

   procedure Invalid_Values_Are_Ignored (T : in out Test_Case) is
      pragma Unreferenced (T);

      procedure Check (Line : String) is
      begin
         Assert
           (Parsed (Line & LF) = Defaults, """" & Line & """ was not ignored");
      end Check;
   begin
      Check ("filter = ""blur""");
      Check ("filter = 3");
      Check ("filter_size = 4");
      Check ("filter_size = -3");
      Check ("filter_size = ""5""");
      Check ("filter_threshold = 1.5");
      Check ("filter_threshold = -0.1");
      Check ("border_size = -1");
      Check ("border_size = 2.5");
      Check ("max_size = -1");
      Check ("height = 0.0");
      Check ("height = -3.0");
      Check ("height = ""tall""");
      Check ("save-ascii = 1");
      Check ("output-name = 12");
      Check ("dimensions = ""100x100x1.5""");
   end Invalid_Values_Are_Ignored;

   procedure Height_May_Be_An_Integer (T : in out Test_Case) is
      pragma Unreferenced (T);
      Settings : constant Settings_Record := Parsed ("height = 4" & LF);
   begin
      Assert_Near (Settings.height, 4.0, "height");
      Assert (Settings.height_is_set, "height is not flagged as given");
   end Height_May_Be_An_Integer;

   procedure No_Limit_And_No_Border (T : in out Test_Case) is
      pragma Unreferenced (T);
      Settings : constant Settings_Record :=
        Parsed ("max_size = 0" & LF & "border_size = 0" & LF);
   begin
      Assert (Settings.max_size = 0, "max_size = 0 was ignored");
      Assert (Settings.border = 0, "border_size = 0 was ignored");
   end No_Limit_And_No_Border;

   procedure Partial_Dimensions (T : in out Test_Case) is
      pragma Unreferenced (T);
      Settings : constant Settings_Record :=
        Parsed ("dimensions = { width = 120, depth = ""thin"" }" & LF);
   begin
      Assert_Near (Settings.dimensions.width, 120.0, "integer width");
      Assert_Near (Settings.dimensions.height, 0.0, "missing height");
      Assert_Near (Settings.dimensions.depth, 0.0, "depth that is no number");
   end Partial_Dimensions;

   procedure Unreadable_File_Is_An_Error (T : in out Test_Case) is
      pragma Unreferenced (T);

      --  Read the config file, which is expected to be refused.
      procedure Check (What : String) is
         Settings : Settings_Record := Defaults;
      begin
         Parse_Config (Settings);
         Assert (False, What & " was accepted");
      exception
         when Config_Error =>
            Assert (Settings = Defaults, What & " changed the settings");
      end Check;
   begin
      Reset_Scratch;
      Check ("a missing file");

      Write_File
        (Scratch ("config.toml"),
         "border_size = 3" & LF & "this is not TOML" & LF);
      Check ("a malformed file");
   end Unreadable_File_Is_An_Error;

   overriding
   procedure Register_Tests (T : in out Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Every_Key'Access, "every key is read");
      Register_Routine
        (T,
         Missing_Keys_Keep_Their_Value'Access,
         "a missing key keeps its value");
      Register_Routine
        (T, Invalid_Values_Are_Ignored'Access, "invalid values are ignored");
      Register_Routine
        (T, Height_May_Be_An_Integer'Access, "height given as an integer");
      Register_Routine
        (T, No_Limit_And_No_Border'Access, "max_size and border_size of 0");
      Register_Routine
        (T, Partial_Dimensions'Access, "dimensions with missing axes");
      Register_Routine
        (T,
         Unreadable_File_Is_An_Error'Access,
         "a missing or malformed file is an error");
   end Register_Tests;

end Config_Tests;
