------------------------------------------------------------------------------
--  golden_tests.adb
--
--  Copyright (c) 2026 Simon Beàn
--  SPDX-License-Identifier: MIT
--
--  Compare the files the program writes for the test picture with the ones
--  kept in tests/golden: any change in the output shows up here. When the
--  change is intended, run the tests with LITHOPHANE_UPDATE_GOLDEN=1 to
--  replace the golden files, and review their diff.
------------------------------------------------------------------------------

with AUnit.Assertions; use AUnit.Assertions;

with Test_Support; use Test_Support;

package body Golden_Tests is

   subtype Test_Case is AUnit.Test_Cases.Test_Case'Class;

   Picture : constant String := "picture.ppm";

   overriding
   procedure Set_Up (T : in out Test) is
      pragma Unreferenced (T);
   begin
      Reset_Scratch;
      Write_Picture (Scratch (Picture));
   end Set_Up;

   procedure Generate (Arguments : String) is
      Result : constant Run_Result := Run (Arguments & " " & Picture);
   begin
      Assert (Result.Status = 0, "lithophane " & Arguments & " failed");
   end Generate;

   procedure Relief (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      Generate ("-a -m -p -B 1 -t 0 -H 3 -o relief");
      Assert_Matches_Golden
        (Scratch ("relief.ascii.stl"), "relief.ascii.stl", Is_Text => True);
      Assert_Matches_Golden
        (Scratch ("relief.bin.stl"), "relief.bin.stl", Is_Text => False);
      Assert_Matches_Golden
        (Scratch ("relief.3mf"), "relief.3mf", Is_Text => False);
      Assert_Matches_Golden
        (Scratch ("relief.pgm"), "relief.pgm", Is_Text => True);
   end Relief;

   procedure Sharpened_And_Scaled (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      Generate ("-a -m -p -B 2 -t 0.3 -f sharpen -d 40x0x3 -o sharpened");
      Assert_Matches_Golden
        (Scratch ("sharpened.ascii.stl"),
         "sharpened.ascii.stl",
         Is_Text => True);
      Assert_Matches_Golden
        (Scratch ("sharpened.3mf"), "sharpened.3mf", Is_Text => False);
      Assert_Matches_Golden
        (Scratch ("sharpened.pgm"), "sharpened.pgm", Is_Text => True);
   end Sharpened_And_Scaled;

   procedure Colour (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      Write_Colour_Picture (Scratch (Picture));
      Generate ("-C -p -B 1 -t 0 -H 3 -d 30x0x2 -o colour");
      Assert_Matches_Golden
        (Scratch ("colour.3mf"), "colour.3mf", Is_Text => False);
      Assert_Matches_Golden
        (Scratch ("colour.pgm"), "colour.pgm", Is_Text => True);
   end Colour;

   overriding
   procedure Register_Tests (T : in out Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Relief'Access, "plain relief");
      Register_Routine
        (T, Sharpened_And_Scaled'Access, "sharpened picture, scaled 3MF");
      Register_Routine (T, Colour'Access, "colour lithophane");
   end Register_Tests;

end Golden_Tests;
