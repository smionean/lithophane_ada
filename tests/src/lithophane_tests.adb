------------------------------------------------------------------------------
--  lithophane_tests.adb
--
--  Copyright (c) 2026 Simon Beàn
--  SPDX-License-Identifier: MIT
--
--  Test driver: runs every regression test and reports the result. The
--  exit status is a failure when a test fails.
------------------------------------------------------------------------------

with Ada.Command_Line;

with AUnit;
with AUnit.Reporter.Text;
with AUnit.Run;
with AUnit.Test_Cases;
with AUnit.Test_Suites;

with Command_Line_Tests;
with Config_Tests;
with File3mf_Tests;
with Filters_Tests;
with Golden_Tests;
with Image_Utilities_Tests;
with Mesh_Tests;
with STL_Tests;

procedure Lithophane_Tests is

   use type AUnit.Status;

   subtype Test_Case_Access is AUnit.Test_Cases.Test_Case_Access;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite :=
        AUnit.Test_Suites.New_Suite;
   begin
      Result.Add_Test (Test_Case_Access'(new Filters_Tests.Test));
      Result.Add_Test (Test_Case_Access'(new Image_Utilities_Tests.Test));
      Result.Add_Test (Test_Case_Access'(new Mesh_Tests.Test));
      Result.Add_Test (Test_Case_Access'(new STL_Tests.Test));
      Result.Add_Test (Test_Case_Access'(new File3mf_Tests.Test));
      Result.Add_Test (Test_Case_Access'(new Config_Tests.Test));
      Result.Add_Test (Test_Case_Access'(new Command_Line_Tests.Test));
      Result.Add_Test (Test_Case_Access'(new Golden_Tests.Test));
      return Result;
   end Suite;

   function Run is new AUnit.Run.Test_Runner_With_Status (Suite);

   Reporter : AUnit.Reporter.Text.Text_Reporter;

begin
   if Run (Reporter) /= AUnit.Success then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Lithophane_Tests;
